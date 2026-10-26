"""Prepare a separate PDF engine asset and pinned app descriptor; never upload."""
import argparse
import gzip
import hashlib
import json
import re
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def package(source, destination, engine_id='pdf-engine-v1.0.0', signing_identity='-'):
    version = re.fullmatch(r'pdf-engine-v(\d+\.\d+\.\d+)', engine_id)
    if not version: raise ValueError('Use an engine ID such as pdf-engine-v1.0.0')
    if destination.exists():
        raise ValueError('Use a fresh output folder; existing packages are preserved')
    if json.loads((source / 'document-engine.json').read_text()).get('engine') != 'baker-small-ocr-1':
        raise ValueError('Select the tested small PDF engine')
    for name in ['python/bin/python3.12', 'worker/pdf_candidate.py', 'model/model.safetensors', 'adapter/adapters.safetensors', 'layout.onnx', 'PROVENANCE.json']:
        if not (source / name).is_file():
            raise ValueError('The selected PDF engine is incomplete: ' + name)
    # Verify weights against the existing source manifest. Native file hashes may
    # have changed during app signing, so the final inventory is generated below.
    original = json.loads((source / 'manifest.json').read_text())
    for name, entry in original['files'].items():
        if Path(name).suffix in {'.onnx', '.safetensors'} and not name.startswith('mfr/'):
            path = source / name
            if sha256(path) != entry['sha256']:
                raise ValueError('Source model mismatch: ' + name)
    destination.mkdir(parents=True)
    engine = destination / 'PDFEngine'
    shutil.copytree(source, engine, symlinks=True, ignore=shutil.ignore_patterns('mfr', 'formula-model.json', '__pycache__', '*.pyc', 'installation.json', 'payload-manifest.json'))
    legal = engine / 'Legal'
    legal.mkdir(exist_ok=True)
    shutil.copy2(ROOT / 'LICENSE', legal / 'LICENSE')
    shutil.copy2(ROOT / 'docs/legal/third-party.md', legal / 'THIRD-PARTY.md')
    for path in engine.rglob('*'):
        if path.is_file() and not path.is_symlink() and (path.suffix in {'.so', '.dylib'} or path.stat().st_mode & 0o111):
            with path.open('rb') as stream:
                magic = stream.read(4)
            if magic in {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'}:
                subprocess.run(['codesign', '--force', '--sign', signing_identity, str(path)], check=True, capture_output=True)
    inventory = {}
    for path in sorted(engine.rglob('*')):
        name = str(path.relative_to(engine))
        if path.is_symlink():
            if not path.resolve().is_relative_to(engine.resolve()):
                raise ValueError('Engine contains an external symlink: ' + name)
            inventory[name] = {'kind': 'symlink', 'target': str(path.readlink())}
        elif path.is_file():
            inventory[name] = {'kind': 'file', 'bytes': path.stat().st_size, 'sha256': sha256(path)}
    manifest = engine / 'payload-manifest.json'
    # Replace the pre-signing inventory inherited from the original engine.
    original['files'] = {name: {'bytes': entry['bytes'], 'sha256': entry['sha256']} for name, entry in inventory.items() if entry['kind'] == 'file' and name != 'manifest.json'}
    original['payload_bytes'] = sum(entry['bytes'] for entry in original['files'].values())
    (engine / 'manifest.json').write_text(json.dumps(original, indent=2) + '\n')
    inventory['manifest.json'] = {'kind': 'file', 'bytes': (engine / 'manifest.json').stat().st_size, 'sha256': sha256(engine / 'manifest.json')}
    manifest.write_text(json.dumps({'engine_id': engine_id, 'files': inventory}, indent=2) + '\n')
    archive = destination / f'Baker-PDF-Engine-{version.group(1)}-arm64.tar.gz'
    def stable_metadata(entry):
        entry.uid = entry.gid = 0
        entry.uname = entry.gname = ''
        entry.mtime = 0
        entry.pax_headers = {}
        return entry
    # Rebuilding unchanged content must not force users to download a new hash.
    with archive.open('wb') as output, gzip.GzipFile(filename='', mode='wb', fileobj=output, mtime=0, compresslevel=6) as compressed:
        with tarfile.open(fileobj=compressed, mode='w') as bundle:
            bundle.add(engine, arcname='PDFEngine', filter=stable_metadata)
    descriptor = {'schema': 1, 'engine_id': engine_id, 'architecture': 'arm64', 'minimum_macos': original['minimum_macos'],
                  'available': False, 'url': f'https://github.com/PentagonToy/Baker/releases/download/{engine_id}/{archive.name}',
                  'archive_bytes': archive.stat().st_size, 'archive_sha256': sha256(archive),
                  'unpacked_bytes': sum(e.get('bytes', 0) for e in inventory.values()) + manifest.stat().st_size,
                  'manifest_sha256': sha256(manifest)}
    (destination / 'pdf-engine.json').write_text(json.dumps(descriptor, indent=2) + '\n')
    (destination / 'SHA256SUMS').write_text(f'{descriptor["archive_sha256"]}  {archive.name}\n')
    print(json.dumps(descriptor, indent=2), flush=True)
    return descriptor


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--engine-id', default='pdf-engine-v1.0.0')
    parser.add_argument('--signing-identity', default='-')
    args = parser.parse_args()
    package(args.source, args.destination, args.engine_id, args.signing_identity)
