"""Check formula archive integrity and reject unsafe or incomplete payloads."""
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('installer', Path(__file__).resolve().parents[1] / 'Sources/Baker/Resources/formula_model_install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / 'model.tar.gz'
        self.stage = self.root / 'stage'
        self.data = b'authored model fixture'
        self.file = {'bytes': len(self.data), 'sha256': hashlib.sha256(self.data).hexdigest()}

    def bundle(self, name='encoder.onnx', kind=tarfile.REGTYPE, duplicate=False):
        with tarfile.open(self.archive, 'w:gz') as output:
            for _ in range(2 if duplicate else 1):
                info = tarfile.TarInfo(name)
                info.type = kind
                info.size = len(self.data) if kind == tarfile.REGTYPE else 0
                output.addfile(info, io.BytesIO(self.data))
        return {'files': {'encoder.onnx': self.file}, 'archive': {
            'bytes': self.archive.stat().st_size,
            'sha256': hashlib.sha256(self.archive.read_bytes()).hexdigest(), 'files': {}}}

    def reject(self, manifest):
        with self.assertRaises(ValueError): installer.unpack(self.archive, manifest, self.stage)
        self.assertFalse(self.stage.exists())

    def test_valid(self):
        installer.unpack(self.archive, self.bundle(), self.stage)
        self.assertEqual((self.stage / 'encoder.onnx').read_bytes(), self.data)

    def test_archive_hash(self):
        manifest = self.bundle(); manifest['archive']['sha256'] = '0' * 64
        self.reject(manifest)

    def test_file_hash(self):
        manifest = self.bundle(); manifest['files']['encoder.onnx'] = {**self.file, 'sha256': '0' * 64}
        self.reject(manifest)

    def test_paths(self):
        for name in ['../outside', '/outside', 'unknown']:
            with self.subTest(name=name): self.reject(self.bundle(name))

    def test_symlink(self): self.reject(self.bundle(kind=tarfile.SYMTYPE))
    def test_duplicate(self): self.reject(self.bundle(duplicate=True))

    def test_incomplete(self):
        manifest = self.bundle(); manifest['archive']['files']['legal/LICENSE'] = self.file
        self.reject(manifest)

    def test_preserve_existing(self):
        manifest = self.bundle(); self.stage.mkdir(); (self.stage / 'user-file').write_text('keep')
        with self.assertRaises(ValueError): installer.unpack(self.archive, manifest, self.stage)
        self.assertEqual((self.stage / 'user-file').read_text(), 'keep')


if __name__ == '__main__': unittest.main()
