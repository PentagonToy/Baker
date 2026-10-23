"""Package verified formula weights, notices and source; never download or publish."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import tarfile

ROOT = Path(__file__).resolve().parents[1]
TEXO_SOURCE = '7773a3ef26cae12106bc724d800fd931c5fca903'


def fingerprint(path):
    with path.open('rb') as stream:
        return {'bytes': path.stat().st_size, 'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}


def package(mfr, texo, texo_source, mit_notice, destination):
    if destination.exists():
        raise ValueError('Choose a fresh output directory')
    destination.mkdir(parents=True)
    for engine, source, descriptor_name, asset in [
        ('mfr', mfr, 'formula-model.json', 'Baker-Pix2Text-MFR-1.5-mlp-int8-v1.tar.gz'),
        ('texo', texo, 'texo-model.json', 'Baker-Texo-transfer-onnx-v1.tar.gz')]:
        descriptor = json.loads((ROOT / 'Sources/Baker/Resources' / descriptor_name).read_text())
        descriptor.pop('archive', None)
        descriptor.pop('bundledOnly', None)
        folder = destination / engine
        folder.mkdir()
        for name, expected in descriptor['files'].items():
            original = source / name
            if fingerprint(original) != {k: expected[k] for k in ['bytes', 'sha256']}:
                raise ValueError('Model integrity differs: ' + name)
            shutil.copyfile(original, folder / name)
        legal = folder / 'legal'; legal.mkdir()
        shutil.copyfile(ROOT / 'LICENSE', legal / 'Baker-AGPL-3.0.txt')
        if engine == 'mfr': shutil.copyfile(mit_notice, legal / 'Pix2Text-MIT.txt')
        else:
            shutil.copyfile(ROOT / 'LICENSE', legal / 'Texo-AGPL-3.0.txt')
            (legal / 'Texo-NOTICE.txt').write_text('Texo / FormulaNet\nCopyright (C) 2025-present Sicheng Mao\nhttps://github.com/alephpi/Texo\nAGPL-3.0. The special LGPL permission for Texo OCR does not apply to Baker.\n')
        shutil.copyfile(ROOT / 'docs/models/README.md', folder / 'PACKAGE.md')
        sources = folder / 'source'; sources.mkdir()
        for name in ['tools/optimize_document_models.py', 'tools/package_formula_models.py',
                     'Sources/Baker/Resources/formula_worker.py', 'Sources/Baker/Resources/texo_worker.py',
                     'Sources/Baker/Resources/formula_model_install.py']:
            shutil.copyfile(ROOT / name, sources / Path(name).name)
        shutil.copyfile(ROOT / 'Sources/Baker/Resources/formula-model-canonical.json', sources / 'mfr-original-manifest.json')
        provenance = {'engine': engine, 'repository': descriptor['repository'], 'revision': descriptor['revision'],
                      'changes': '24 encoder feed-forward MatMul nodes quantised; attention and decoder unchanged' if engine == 'mfr' else 'Published ONNX weights unchanged; no additional quantisation',
                      'licence': 'MIT' if engine == 'mfr' else 'AGPL-3.0',
                      'baker_source_base': 'c76f4cf1ccda2ffded45e798539f6ca889ffafab',
                      'source_state': 'Included scripts are the exact working-tree snapshots used for this package; hashes identify them.'}
        if engine == 'texo':
            with tarfile.open(texo_source) as upstream:
                names = upstream.getnames()
                if not names or not all(n.startswith('Texo-' + TEXO_SOURCE + '/') or n == 'Texo-' + TEXO_SOURCE for n in names):
                    raise ValueError('Unexpected Texo source snapshot')
            shutil.copyfile(texo_source, sources / 'Texo-source.tar.gz')
            provenance.update(upstream_source_revision=TEXO_SOURCE, upstream_source_archive=fingerprint(texo_source),
                              training_source_commit='Not specified by the upstream model card')
        (folder / 'PROVENANCE.json').write_text(json.dumps(provenance, indent=2) + '\n')
        extras = {str(p.relative_to(folder)): fingerprint(p) for p in sorted(folder.rglob('*'))
                  if p.is_file() and str(p.relative_to(folder)) not in descriptor['files']}
        archive = destination / asset
        with archive.open('wb') as raw, gzip.GzipFile(fileobj=raw, mode='wb', filename='', mtime=0) as zipped, tarfile.open(fileobj=zipped, mode='w') as bundle:
            for path in sorted(folder.rglob('*')):
                if not path.is_file(): continue
                info = bundle.gettarinfo(str(path), arcname=str(path.relative_to(folder)))
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ''
                info.mode = 0o644
                with path.open('rb') as stream: bundle.addfile(info, stream)
        descriptor['archive'] = {**fingerprint(archive), 'url': 'https://github.com/PentagonToy/Baker/releases/download/formula-models-v1.0.0/' + asset, 'files': extras}
        output = destination / ('formula-model.json' if engine == 'mfr' else 'texo-model.json')
        output.write_text(json.dumps(descriptor, indent=2) + '\n')
    assets = sorted(p for p in destination.iterdir() if p.is_file())
    (destination / 'SHA256SUMS').write_text(''.join(f"{fingerprint(p)['sha256']}  {p.name}\n" for p in assets))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ['mfr', 'texo', 'texo-source', 'mit-notice', 'destination']:
        parser.add_argument('--' + key, type=Path, required=True)
    args = parser.parse_args()
    package(args.mfr, args.texo, args.texo_source, args.mit_notice, args.destination)
