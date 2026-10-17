"""Assemble the verified small OCR payload and retain the fast capture formula model."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import re

ROOT = Path(__file__).resolve().parents[2]


def prepare(source, formula, destination):
    manifest = json.loads((source / 'manifest.json').read_text())
    for name, entry in manifest['files'].items():
        path = source / name
        if not path.resolve().is_relative_to(source.resolve()):
            raise ValueError('Payload path leaves the selected engine')
        if hashlib.file_digest(path.open('rb'), 'sha256').hexdigest() != entry['sha256']:
            raise ValueError('Selected engine integrity check failed: ' + name)
    if destination.exists():
        raise ValueError('Use a fresh engine destination')
    shutil.copytree(source, destination, symlinks=True)
    for name in ['mfr', 'formula-model.json']:
        target = destination / name
        if (formula / name).is_dir(): shutil.copytree(formula / name, target)
        else: shutil.copy2(formula / name, target)
    for name in ['pdf_candidate.py', 'minimal.py', 'pdf_text.py', 'layout.py', 'evaluate.py', 'vision.js']:
        shutil.copy2(ROOT / 'tools/recognition' / name, destination / 'worker' / name)
    shutil.copy2(ROOT / 'Sources/Baker/Resources/document_reconstruction.py', destination / 'worker/document_reconstruction.py')
    shutil.copy2(ROOT / 'tools/recognition/model-provenance.json', destination / 'PROVENANCE.json')
    shutil.copytree(ROOT / 'tools/recognition/notices', destination / 'notices')
    (destination / 'document-engine.json').write_text(json.dumps({'engine': 'baker-small-ocr-1'}))
    files = {}
    for path in destination.rglob('*'):
        if path.is_file() and not path.is_symlink() and path.name != 'manifest.json':
            files[str(path.relative_to(destination))] = {'bytes': path.stat().st_size, 'sha256': hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()}
    minimum = (14, 0)
    for path in destination.rglob('*'):
        if path.is_file() and (path.suffix in ('.so', '.dylib') or path.stat().st_mode & 0o111):
            result = subprocess.run(['vtool', '-show-build', str(path)], capture_output=True, text=True)
            for value in re.findall(r'minos (\d+(?:\.\d+)+)', result.stdout):
                version = tuple(map(int, value.split('.')))
                minimum = max(minimum, version)
    manifest.update(files=files, payload_bytes=sum(item['bytes'] for item in files.values()), minimum_macos='.'.join(map(str, minimum)), engine='baker-small-ocr-1')
    (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['source', 'formula', 'destination']: parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    prepare(args.source, args.formula, args.destination)
