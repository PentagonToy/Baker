"""Copy a validated document environment into a relocatable, offline runtime."""
import argparse
import hashlib
import importlib.metadata as metadata
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name


def closure():
    pending = ['pix2text', 'pymupdf', 'optimum[onnxruntime]', 'packaging']
    seen, distributions = set(), {}
    while pending:
        req = Requirement(pending.pop())
        key = (canonicalize_name(req.name), tuple(sorted(req.extras)))
        if key in seen: continue
        seen.add(key)
        dist = metadata.distribution(req.name)
        if req.specifier and dist.version not in req.specifier:
            raise ValueError(f'Validated environment does not satisfy {req}; found {dist.version}')
        distributions[key[0]] = dist
        for value in dist.requires or []:
            dep = Requirement(value)
            if dep.marker is None or any(dep.marker.evaluate({'extra': extra}) for extra in {'', *req.extras}):
                pending.append(str(dep))
    return distributions


def prepare(destination, configuration):
    if sys.version_info[:2] != (3, 12) or platform.machine() != 'arm64':
        raise ValueError('Select the validated arm64 Python 3.12 document environment.')
    base = Path(sys.base_prefix)
    if not (base / 'BUILD').exists(): raise ValueError('A relocatable standalone CPython build is required.')
    settings = json.loads(configuration.read_text())
    distributions = closure()
    versions = {name: dist.version for name, dist in sorted(distributions.items())}
    identity = hashlib.sha256((json.dumps(versions, sort_keys=True) + configuration.read_text() + Path(__file__).read_text()).encode()).hexdigest()
    marker = destination / 'manifest.json'
    if marker.exists() and json.loads(marker.read_text()).get('identity') == identity:
        print('Reusing checked document runtime:', destination); return
    if destination.exists(): raise ValueError('Document cache changed. Choose a fresh cache path; existing files are preserved.')
    sources = {str(Path(name).resolve()): info for name, info in settings['files'].items()}
    for name, info in sources.items():
        path = Path(name)
        if not path.is_file() or path.stat().st_size != info['bytes'] or hashlib.file_digest(path.open('rb'), 'sha256').hexdigest() != info['sha256']:
            raise ValueError('Document model integrity mismatch: ' + path.name)
    staging = destination.with_name(destination.name + '.preparing-' + str(os.getpid()))
    if staging.exists(): raise ValueError('A previous document preparation is still present: ' + str(staging))
    staging.mkdir(parents=True)
    try:
        shutil.copytree(base, staging / 'python', symlinks=True,
                        ignore=shutil.ignore_patterns('site-packages', '__pycache__', '*.pyc', 'include', 'man'))
        site = staging / 'python/lib/python3.12/site-packages'; site.mkdir(parents=True)
        for dist in distributions.values():
            print('Copying', dist.metadata['Name'], dist.version, flush=True)
            for file in dist.files or []:
                if '..' in file.parts or '__pycache__' in file.parts or file.suffix == '.pyc' or file.name == 'direct_url.json': continue
                # The shipped runtime performs inference, never C++ extension builds.
                # Keep every executable, Python module and upstream licence notice.
                if file.parts[:2] == ('torch', 'include'): continue
                source = Path(dist.locate_file(file))
                if source.is_file():
                    target = site / file; target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, target)
        models = Path(settings['models']).resolve(); mfr = Path(settings['mfr']).resolve()
        mapped = {}
        for name, info in sources.items():
            source = Path(name)
            if source.is_relative_to(models): relative = Path('models') / source.relative_to(models)
            elif source.is_relative_to(mfr): relative = Path('mfr') / source.relative_to(mfr)
            else: raise ValueError('Model is outside its declared roots: ' + name)
            target = staging / relative; target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, target)
            mapped[str(relative)] = info
        # Tokenisers/processors also require their small JSON configuration files.
        for source in mfr.glob('*.json'):
            target = staging / 'mfr' / source.name; target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, target)
        for source in (models / 'table-rec').glob('*.json'):
            target = staging / 'models/table-rec' / source.name; target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(source, target)
        (staging / 'document-engine.json').write_text(json.dumps({'models':'models', 'mfr':'mfr', 'files':mapped}, indent=2))
        if settings.get('formula_manifest'):
            shutil.copy2(settings['formula_manifest'], staging/'formula-model.json')
        # Every dependency's dist-info, including upstream licence files, is retained.
        env = {'PATH':'/usr/bin:/bin', 'HOME':str(staging), 'HF_HUB_OFFLINE':'1', 'TRANSFORMERS_OFFLINE':'1', 'YOLO_AUTOINSTALL':'false'}
        subprocess.run([str(staging / 'python/bin/python3.12'), '-I', '-B', '-c',
                        'import pix2text,pymupdf,torch,onnxruntime; from optimum.onnxruntime import ORTModelForVision2Seq; print("Document imports ready")'], check=True, env=env)
        minimum = (14, 0)
        import re
        for native in staging.rglob('*'):
            if not native.is_file() or native.is_symlink() or (native.suffix not in ('.so', '.dylib') and native.name != 'python3.12'): continue
            result = subprocess.run(['vtool', '-show-build', str(native)], capture_output=True, text=True)
            for value in re.findall(r'\bminos\s+(\d+\.\d+(?:\.\d+)?)', result.stdout): minimum = max(minimum, tuple(map(int, value.split('.'))))
        marker_data = {'identity':identity, 'minimum_macos':'.'.join(map(str, minimum)), 'packages':versions, 'model_sources':sources}
        (staging / 'manifest.json').write_text(json.dumps(marker_data, indent=2))
        staging.rename(destination)
    except BaseException:
        # Preserve a failed staging tree for diagnosis; never replace a valid cache.
        print('Preparation failed; diagnostic staging retained at', staging, file=sys.stderr); raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--configuration', type=Path, required=True)
    args = parser.parse_args(); prepare(args.destination.resolve(), args.configuration.resolve())
