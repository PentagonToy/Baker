"""Check Texo boundaries and incremental cache ownership without downloading models."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


texo = load("texo", ROOT / "Sources/Baker/Resources/texo_worker.py")
worker = load("formula", ROOT / "Sources/Baker/Resources/formula_worker.py")


class TexoTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.image = self.root / "image.png"
        image = Image.new("RGB", (60, 30), "white")
        image.putpixel((20, 15), (0, 0, 0))
        image.save(self.image)
        metadata = {"decoder": dict(vocab_size=687, bos_token_id=0, eos_token_id=2, pad_token_id=1, decoder_layers=2, d_model=384)}
        (self.root / "config.json").write_text(json.dumps(metadata))
        for name in ["encoder_model.onnx", "decoder_model.onnx", "decoder_with_past_model.onnx", "tokenizer.json"]:
            (self.root / name).touch()
        self.config = self.root / "settings.json"
        self.config.write_text(json.dumps({"engine": "texo", "model_dir": str(self.root)}))

    def test_engine_specific_files_and_limits(self):
        settings = worker.read_settings(self.config)
        self.assertEqual(settings["max_new_tokens"], 512)
        (self.root / "decoder_with_past_model.onnx").unlink()
        with self.assertRaisesRegex(ValueError, "incomplete"):
            worker.read_settings(self.config)

    def test_texo_preserves_the_archive_token_bound(self):
        self.config.write_text(json.dumps({"engine": "texo", "model_dir": str(self.root), "max_new_tokens": 513}))
        with self.assertRaisesRegex(ValueError, "max_new_tokens"):
            worker.read_settings(self.config)

    def test_unknown_engine_does_not_fall_back(self):
        self.config.write_text(json.dumps({"engine": "other", "model_dir": str(self.root)}))
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            worker.read_settings(self.config)

    def test_transparency_and_extreme_aspect_are_bounded(self):
        Image.new("RGBA", (20, 20), (0, 0, 0, 0)).save(self.image)
        with self.assertRaisesRegex(ValueError, "contrast"):
            texo.prepare_image(self.image, 1000)
        image = Image.new("RGB", (10000, 2), "white")
        for x in range(10000):
            image.putpixel((x, 0), (0, 0, 0))
        image.save(self.image)
        with self.assertRaisesRegex(ValueError, "aspect ratio"):
            texo.prepare_image(self.image, 30000)

    def test_pixel_shape_type_and_normalisation(self):
        pixels = texo.prepare_image(self.image, 2000)
        self.assertEqual(pixels.shape, (1, 3, 384, 384))
        self.assertEqual(pixels.dtype, np.float32)
        self.assertTrue(np.isfinite(pixels).all())
        self.assertTrue(pixels.flags.c_contiguous)

    def test_light_and_dark_equations_have_identical_model_pixels(self):
        image = Image.new("RGB", (120, 50), (230, 230, 230))
        draw = ImageDraw.Draw(image)
        draw.text((15, 15), "x + 1 = 0", fill=(25, 25, 25))
        image.save(self.image)
        expected = texo.prepare_image(self.image, 10000)
        ImageOps.invert(image).save(self.image)
        np.testing.assert_array_equal(texo.prepare_image(self.image, 10000), expected)

    def test_black_frame_does_not_invert_a_white_formula_panel(self):
        image = Image.new("RGB", (120, 50), "black")
        draw = ImageDraw.Draw(image)
        draw.rectangle((2, 2, 117, 47), fill="white")
        draw.text((15, 15), "x + 1 = 0", fill="black")
        image.save(self.image)
        with patch.object(ImageOps, "invert", side_effect=AssertionError("white panel inverted")):
            texo.prepare_image(self.image, 10000)

    def decode(self, emitted, limit=8, invalid=False):
        import onnxruntime
        import tokenizers
        calls = []
        cache_names = [f"present.{layer}.{kind}.{part}" for layer in range(2) for kind in ["decoder", "encoder"] for part in ["key", "value"]]

        class Session:
            def __init__(inner, path, **kwargs):
                inner.name = Path(path).name

            def get_outputs(inner):
                names = cache_names if inner.name == "decoder_model.onnx" else [n for n in cache_names if ".decoder." in n]
                return [type("Output", (), {"name": name})() for name in ["logits"] + names]

            def run(inner, names, feed):
                if inner.name == "encoder_model.onnx":
                    return [np.zeros((1, 144, 2048), np.float32)]
                calls.append((inner.name, feed))
                logits = np.zeros((1, 1, 687), np.float32)
                logits[0, 0, emitted[min(len(calls) - 1, len(emitted) - 1)]] = np.nan if invalid else 10
                return [logits] + [np.full((1, 16, len(calls), 24), len(calls), np.float32) for _ in inner.get_outputs()[1:]]

        class Tokens:
            def decode(inner, ids, **kwargs):
                self.assertEqual(ids, [7, 8])
                return "x+1"

        with patch.object(onnxruntime, "InferenceSession", Session), patch.object(tokenizers.Tokenizer, "from_file", return_value=Tokens()):
            settings = worker.read_settings(self.config)
            settings["max_new_tokens"] = limit
            result = texo.recognise(self.image, settings)
        return result, calls

    def test_only_latest_token_and_updated_decoder_cache_are_reused(self):
        result, calls = self.decode([7, 8, 2])
        self.assertEqual(result["diagnostics"]["tokenCount"], 2)
        self.assertEqual(calls[1][1]["input_ids"].tolist(), [[7]])
        self.assertEqual(calls[2][1]["input_ids"].tolist(), [[8]])
        self.assertTrue(np.all(calls[2][1]["past_key_values.0.decoder.key"] == 2))
        self.assertTrue(np.all(calls[2][1]["past_key_values.0.encoder.key"] == 1))

    def test_exhaustion_and_invalid_logits_never_return_partial_latex(self):
        with self.assertRaises(texo.TokenLimitError):
            self.decode([7], limit=1)
        with self.assertRaisesRegex(ValueError, "invalid logits"):
            self.decode([7], invalid=True)


if __name__ == "__main__":
    unittest.main()
