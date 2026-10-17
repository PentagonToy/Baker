"""Formula-worker boundaries and optional real local-model regression."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image

WORKER = Path(__file__).resolve().parents[1] / "Sources/Baker/Resources/formula_worker.py"
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("formula_worker", WORKER)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)
PROCESSOR = {"size": {"height": 384, "width": 384}, "do_resize": True, "do_center_crop": False, "resample": 3, "do_rescale": True, "do_normalize": True, "image_mean": [0.5] * 3, "image_std": [0.5] * 3, "rescale_factor": 1 / 255}
MODEL = {"decoder_start_token_id": 1, "eos_token_id": 2, "pad_token_id": 0}


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.image = self.root / "image.png"
        Image.new("RGB", (16, 16), "white").save(self.image)
        for name in ("encoder_model.onnx", "decoder_model.onnx", "tokenizer.json", "preprocessor_config.json", "config.json"):
            (self.root / name).touch()
        self.config = self.root / "settings.json"
        self.config.write_text(json.dumps({"model_dir": str(self.root)}))
        self.addCleanup(self.temporary.cleanup)

    def test_missing_model_fails_before_runtime(self):
        self.config.write_text("{}")
        with self.assertRaisesRegex(ValueError, "model_dir"):
            worker.read_settings(self.config)

    def test_incomplete_model_rejected(self):
        (self.root / "encoder_model.onnx").unlink()
        with self.assertRaisesRegex(ValueError, "incomplete"):
            worker.read_settings(self.config)

    def test_limits_reject_boolean_negative_and_unbounded_values(self):
        for key, value in [("threads", True), ("threads", 3), ("max_new_tokens", 513), ("max_image_pixels", -1), ("timeout_seconds", 121)]:
            with self.subTest(key=key, value=value):
                self.config.write_text(json.dumps({"model_dir": str(self.root), key: value}))
                with self.assertRaises(ValueError):
                    worker.read_settings(self.config)

    def test_normalisation_and_transparency(self):
        Image.new("RGBA", (16, 16), (0, 0, 0, 0)).save(self.image)
        pixels = worker.prepare_image(self.image, 256, PROCESSOR)
        self.assertEqual(pixels.shape, (1, 3, 384, 384))
        self.assertEqual(pixels.dtype, np.float32)
        self.assertTrue(np.all(pixels == 1))
        Image.new("RGB", (16, 16), "black").save(self.image)
        self.assertTrue(np.all(worker.prepare_image(self.image, 256, PROCESSOR) == -1))

    def test_pixel_limit_checked_before_decode(self):
        with self.assertRaisesRegex(ValueError, "pixel limit"), patch.object(Image.Image, "load", side_effect=AssertionError("pixels loaded")):
            worker.prepare_image(self.image, 255, PROCESSOR)

    def test_wrong_preprocessing_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "preprocessing"):
            worker.prepare_image(self.image, 256, {**PROCESSOR, "do_center_crop": True})

    def test_greedy_eos_and_token_limit(self):
        class Decoder:
            def __init__(self, tokens): self.tokens = iter(tokens)
            def run(self, outputs, inputs):
                ids = inputs["input_ids"]
                logits = np.zeros((1, ids.shape[1], 1868), np.float32)
                logits[0, -1, next(self.tokens)] = 1
                return [logits]
        class Tokenizer:
            def decode(self, tokens, skip_special_tokens):
                self.tokens = tokens
                return "x"
        tokenizer = Tokenizer()
        result = worker.decode_tokens(Decoder([10, 2]), None, tokenizer, MODEL, 2, time.monotonic() + 10)
        self.assertEqual(result["latex"], "x")
        self.assertEqual(result["confidence_method"], "geometric_mean_token_probability_v1")
        self.assertAlmostEqual(result["confidence"], float(np.e / (1867 + np.e)), places=8)
        self.assertEqual(tokenizer.tokens, [10])
        with self.assertRaisesRegex(ValueError, "token limit"):
            worker.decode_tokens(Decoder([10]), None, tokenizer, MODEL, 1, time.monotonic() + 10)
        with self.assertRaises(TimeoutError):
            worker.decode_tokens(Decoder([]), None, tokenizer, MODEL, 1, time.monotonic() - 1)

    def test_confidence_is_stable_and_excludes_eos(self):
        class Decoder:
            def __init__(self): self.step = 0
            def run(self, outputs, inputs):
                n = inputs["input_ids"].shape[1]
                values = np.full((1, n, 1868), -10000., np.float32)
                if self.step == 0:
                    values[0, -1, 10] = 10000.
                    values[0, -1, 11] = 10000.
                else: values[0, -1, 2] = 10000.
                self.step += 1
                return [values]
        class Tokenizer:
            def decode(self, *args, **kwargs): return "x"
        result = worker.decode_tokens(Decoder(), None, Tokenizer(), MODEL, 2, time.monotonic() + 10)
        self.assertAlmostEqual(result["confidence"], .5)
        self.assertEqual(result["diagnostics"]["tokenCount"], 1)
        self.assertEqual(result["diagnostics"]["ambiguousTokenCount"], 1)
        self.assertAlmostEqual(result["diagnostics"]["minimumTokenProbability"], .5)

    def test_json_stdout_and_diagnostics_stderr(self):
        def recognise(*args):
            print("diagnostic")
            return {"latex": "x"}
        output, errors = io.StringIO(), io.StringIO()
        with patch.object(sys, "argv", [str(WORKER), str(self.image), str(self.config)]), patch.object(worker, "recognise", recognise), contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            self.assertEqual(worker.main(), 0)
        self.assertEqual(json.loads(output.getvalue()), {"latex": "x"})
        self.assertEqual(errors.getvalue(), "diagnostic\n")

    def test_hard_deadline_emits_one_json_and_exits(self):
        self.config.write_text(json.dumps({"model_dir": str(self.root), "timeout_seconds": 1}))
        code = "import runpy,sys,time; w=runpy.run_path(sys.argv[1]); w['main'].__globals__['recognise']=lambda *args:time.sleep(10); sys.argv=sys.argv[1:]; raise SystemExit(w['main']())"
        result = subprocess.run([sys.executable, "-c", code, str(WORKER), str(self.image), str(self.config)], capture_output=True, text=True, timeout=4)
        self.assertEqual(result.returncode, 1)
        self.assertIn("time limit", json.loads(result.stdout)["error"])
        self.assertEqual(len(result.stdout.splitlines()), 1)

    def test_model_variant_identity_is_explicit(self):
        self.assertEqual(worker.model_identity(self.root), "pix2text-mfr-1.5-pinned")
        metadata = self.root / "baker-model.json"
        metadata.write_text(json.dumps({"variant": "mlp-int8-v1"}))
        self.assertEqual(worker.model_identity(self.root), "pix2text-mfr-1.5-mlp-int8-v1")
        metadata.write_text(json.dumps({"variant": "unknown"}))
        with self.assertRaises(ValueError): worker.model_identity(self.root)

    @unittest.skipUnless(os.environ.get("BAKER_FORMULA_CONFIG") and os.environ.get("BAKER_FORMULA_FIXTURE"), "Set BAKER_FORMULA_CONFIG and BAKER_FORMULA_FIXTURE to test prepared local weights.")
    def test_real_stix_formula(self):
        fixture = os.environ["BAKER_FORMULA_FIXTURE"]
        result = subprocess.run([sys.executable, str(WORKER), fixture, os.environ["BAKER_FORMULA_CONFIG"]], capture_output=True, text=True, timeout=50)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        latex = "".join(json.loads(result.stdout)["latex"].split())
        self.assertEqual(latex, "x^{2}+y^{2}=z^{2}")
        config = json.loads(Path(os.environ["BAKER_FORMULA_CONFIG"]).read_text())
        config["max_new_tokens"] = 1
        self.config.write_text(json.dumps(config))
        limited = subprocess.run([sys.executable, str(WORKER), fixture, str(self.config)], capture_output=True, text=True, timeout=50)
        self.assertEqual(limited.returncode, 1)
        payload = json.loads(limited.stdout)
        self.assertIn("token limit", payload["error"])
        self.assertNotIn("latex", payload)


if __name__ == "__main__":
    unittest.main()
