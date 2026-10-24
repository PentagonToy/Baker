"""Package verified plus-S FP32 files, provenance and notices without downloading or publishing."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import tarfile

ROOT = Path(__file__).resolve().parents[1]
TAG = 'formula-models-v1.1.0'
ASSET = 'Baker-PP-FormulaNet-plus-S-fp32-ort-v1.tar.gz'


def fingerprint(path):
    with path.open('rb') as stream:
        return {'bytes': path.stat().st_size, 'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}


def package(model, upstream, processor, validation, destination):
    if destination.exists():
        raise ValueError('Choose a fresh package directory')
    pins = json.loads((ROOT / 'tools/plus-s-upstream.json').read_text())
    conversion = json.loads((model / 'conversion.json').read_text())
    for name, expected in pins['files'].items():
        if fingerprint(upstream / name) != expected:
            raise ValueError('Upstream integrity differs: ' + name)
    if conversion['revision'] != pins['revision'] or conversion['inputs'] != pins['files']:
        raise ValueError('Conversion provenance differs from pinned model')
    check = json.loads(validation.read_text())
    if check['count'] != 158 or check['matching_predictions'] != 158 or check['matching_tokens'] != 158:
        raise ValueError('Require complete native-reference parity before packaging')
    if check['model_files'] != conversion['outputs'] or check['worker_sha256'] != fingerprint(ROOT / 'Sources/Baker/Resources/plus_s_worker.py')['sha256']:
        raise ValueError('Validation does not identify these model and worker files')
    if fingerprint(processor)['sha256'] != '4a2c197634a210a90cca7bf3f417ce594b610db0058d2ccfa060dc2dcfb752eb':
        raise ValueError('PaddleX 3.7.2 processor source differs')
    folder = destination / 'plus-s'
    folder.mkdir(parents=True)
    inventory = {}
    for name in ['formula_model.ort', 'tokenizer.json', 'config.json']:
        expected = conversion['outputs'][name]
        if fingerprint(model / name) != expected:
            raise ValueError('Converted model integrity differs: ' + name)
        shutil.copyfile(model / name, folder / name)
        inventory[name] = expected
    shutil.copyfile(upstream / 'README.md', folder / 'README.md')
    inventory['README.md'] = fingerprint(folder / 'README.md')
    legal = folder / 'legal'; legal.mkdir()
    for original, name in [(ROOT / 'LICENSE', 'Baker-AGPL-3.0.txt'), (ROOT / 'Sources/Baker/Resources/FormulaNotices/Apache-2.0.txt', 'Apache-2.0.txt'), (ROOT / 'Sources/Baker/Resources/FormulaNotices/NOTICE.txt', 'NOTICE.txt')]:
        shutil.copyfile(original, legal / name)
    sources = folder / 'source'; sources.mkdir()
    for name in ['tools/optimise_plus_s.py', 'tools/plus-s-upstream.json', 'tools/package_plus_s.py', 'Sources/Baker/Resources/plus_s_worker.py', 'Sources/Baker/Resources/formula_worker.py', 'Sources/Baker/Resources/formula_model_install.py']:
        shutil.copyfile(ROOT / name, sources / Path(name).name)
    shutil.copyfile(processor, sources / 'paddlex-3.7.2-processors.py')
    shutil.copyfile(upstream / 'config.json', sources / 'upstream-config.json')
    shutil.copyfile(model / 'conversion.json', folder / 'CONVERSION.json')
    shutil.copyfile(validation, folder / 'VALIDATION.json')
    shutil.copyfile(ROOT / 'docs/models/README.md', folder / 'PACKAGE.md')
    provenance = {'engine': 'plus-s', 'repository': pins['repository'], 'revision': pins['revision'], 'licence': 'Apache-2.0 for upstream model and PaddleX code; AGPL-3.0-only for Baker integration', 'processor': {'package': 'paddlex', 'version': '3.7.2', **fingerprint(processor)}, 'changes': conversion['optimisation'], 'source_state': 'Exact packaging and worker snapshots are included and hashed. No training, quantisation or captures included.', 'compatibility': 'CPU ORT format; tested on Apple M1 Pro with ONNX Runtime 1.23.2 and the Baker runtime. Other machines require validation.'}
    (folder / 'PROVENANCE.json').write_text(json.dumps(provenance, indent=2) + '\n')
    extras = {str(p.relative_to(folder)): fingerprint(p) for p in sorted(folder.rglob('*')) if p.is_file() and str(p.relative_to(folder)) not in inventory}
    archive = destination / ASSET
    with archive.open('wb') as raw, gzip.GzipFile(fileobj=raw, mode='wb', filename='', mtime=0) as zipped, tarfile.open(fileobj=zipped, mode='w') as bundle:
        for path in sorted(folder.rglob('*')):
            if not path.is_file(): continue
            info = bundle.gettarinfo(str(path), arcname=str(path.relative_to(folder)))
            info.uid = info.gid = info.mtime = 0; info.uname = info.gname = ''; info.mode = 0o644
            with path.open('rb') as stream: bundle.addfile(info, stream)
    descriptor = {'repository': pins['repository'], 'revision': pins['revision'], 'variant': 'fp32-ort-v1', 'files': inventory, 'archive': {**fingerprint(archive), 'url': f'https://github.com/PentagonToy/Baker/releases/download/{TAG}/{ASSET}', 'files': extras}}
    (destination / 'plus-s-model.json').write_text(json.dumps(descriptor, indent=2) + '\n')
    shutil.copyfile(ROOT / 'docs/models/README.md', destination / 'README.md')
    (destination / 'SHA256SUMS').write_text(''.join(f"{fingerprint(p)['sha256']}  {p.name}\n" for p in sorted(destination.iterdir()) if p.is_file()))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ['model', 'upstream', 'processor', 'validation', 'destination']:
        parser.add_argument('--' + key, type=Path, required=True)
    args = parser.parse_args()
    package(args.model, args.upstream, args.processor, args.validation, args.destination)
