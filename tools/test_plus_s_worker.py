"""Check plus-S input, decode and configuration boundaries without downloading weights."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image, ImageDraw, ImageOps
from tokenizers import Tokenizer, models

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


plus = load('plus', ROOT / 'Sources/Baker/Resources/plus_s_worker.py')
worker = load('formula', ROOT / 'Sources/Baker/Resources/formula_worker.py')


class PlusTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.image = self.root / 'image.png'
        image = Image.new('RGB', (120, 40), 'white')
        ImageDraw.Draw(image).text((20, 10), 'x + 1 = 0', fill='black')
        image.save(self.image)
        for name in ['formula_model.ort', 'tokenizer.json', 'config.json']:
            (self.root / name).touch()
        self.config = self.root / 'settings.json'
        self.config.write_text(json.dumps({'engine': 'plus-s', 'model_dir': str(self.root)}))
        self.tokenizer = Tokenizer(models.WordLevel({'<s>': 0, '<pad>': 1, '</s>': 2, 'x': 3}, unk_token='<pad>'))
        self.tokenizer.add_special_tokens(['<s>', '<pad>', '</s>'])

    def test_engine_settings_and_bounds(self):
        settings = worker.read_settings(self.config)
        self.assertEqual((settings['engine'], settings['max_new_tokens']), ('plus-s', 1024))
        self.config.write_text(json.dumps({'engine': 'plus-s', 'model_dir': str(self.root), 'max_new_tokens': 1025}))
        with self.assertRaises(ValueError): worker.read_settings(self.config)

    def test_missing_graph_is_not_ready(self):
        (self.root / 'formula_model.ort').unlink()
        with self.assertRaisesRegex(ValueError, 'formula_model.ort'): worker.read_settings(self.config)

    def test_pixels_are_bounded_single_channel(self):
        pixels = plus.prepare_image(self.image, 4800)
        self.assertEqual(pixels.shape, (1, 1, 384, 384))
        self.assertEqual(pixels.dtype, np.float32)
        self.assertTrue(np.isfinite(pixels).all())
        with self.assertRaises(ValueError): plus.prepare_image(self.image, 4799)

    def test_transparent_and_dark_input(self):
        expected = plus.prepare_image(self.image, 4800)
        with Image.open(self.image) as source: image = source.convert('RGB')
        ImageOps.invert(image).save(self.image)
        np.testing.assert_array_equal(expected, plus.prepare_image(self.image, 4800))
        transparent = Image.new('RGBA', image.size, 'black')
        transparent.putalpha(ImageOps.invert(image.convert('L')))
        transparent.save(self.image)
        np.testing.assert_allclose(expected, plus.prepare_image(self.image, 4800), atol=1e-6)

    def test_blank_and_extreme_aspect(self):
        Image.new('RGB', (10, 10), 'white').save(self.image)
        with self.assertRaisesRegex(ValueError, 'contrast'): plus.prepare_image(self.image, 1000)
        image = Image.new('RGB', (1000, 2), 'white')
        ImageDraw.Draw(image).line((0, 0, 999, 0), fill='black')
        image.save(self.image)
        with self.assertRaisesRegex(ValueError, 'aspect ratio'): plus.prepare_image(self.image, 3000)

    def test_eos_and_no_fabricated_score(self):
        result = plus.decode_tokens([0, 0, 3, 2, 3], self.tokenizer, 1024)
        self.assertEqual(result, {'latex': 'x', 'model': 'pp-formulanet-plus-s-fp32-ort-v1'})
        self.assertNotIn('confidence', result)
        with self.assertRaises(plus.TokenLimitError): plus.decode_tokens([0, 3], self.tokenizer, 1024)
        with self.assertRaises(plus.TokenLimitError): plus.decode_tokens([0, 3, 2], self.tokenizer, 2)
        with self.assertRaisesRegex(ValueError, 'no LaTeX'): plus.decode_tokens([0, 2], self.tokenizer, 1024)

    def test_metadata_rejected_before_native_load(self):
        settings = worker.read_settings(self.config)
        (self.root / 'config.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'configuration'): plus.recognise(self.image, settings)


if __name__ == '__main__': unittest.main()
