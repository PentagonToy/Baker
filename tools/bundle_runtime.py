"""Build Baker's relocatable OCR runtime from an explicitly selected build environment."""
import argparse
import importlib.metadata as metadata
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
from packaging.requirements import Requirement


def dependencies(binary):
    lines = subprocess.check_output(['otool', '-L', str(binary)], text=True).splitlines()[1:]
    return [line.strip().split(' (', 1)[0] for line in lines]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--tesseract', type=Path, required=True)
    args = parser.parse_args()
    target = args.destination.resolve()
    if target.exists():
        raise ValueError('Use a fresh runtime destination.')
    base = Path(sys.base_prefix)
    if sys.version_info[:2] != (3, 12) or not (base / 'BUILD').exists():
        raise ValueError('Use the selected arm64 standalone CPython 3.12 build environment.')
    shutil.copytree(base, target / 'python', symlinks=True, ignore=shutil.ignore_patterns('__pycache__', '*.pyc', 'site-packages', 'include', 'man'))
    site = target / 'python/lib/python3.12/site-packages'
    site.mkdir(parents=True)
    pending = ['numpy==2.5.4', 'Pillow==12.3.0', 'onnxruntime==1.31.0', 'tokenizers==0.23.3']
    copied = {}
    while pending:
        requirement = Requirement(pending.pop())
        if requirement.marker and not requirement.marker.evaluate({'extra': ''}):
            continue
        distribution = metadata.distribution(requirement.name)
        name = distribution.metadata['Name']
        if name in copied:
            continue
        if requirement.specifier and distribution.version not in requirement.specifier:
            raise ValueError(f'Incompatible runtime dependency: {requirement}')
        copied[name] = distribution.version
        for file in distribution.files or []:
            if '..' in file.parts or '__pycache__' in file.parts or file.suffix == '.pyc' or file.name == 'direct_url.json':
                continue
            source = Path(distribution.locate_file(file))
            destination = site / file
            if source.is_file():
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
        pending.extend(distribution.requires or [])
    tess = target / 'tesseract'; (tess / 'bin').mkdir(parents=True); (tess / 'lib').mkdir()
    originals = {args.tesseract.resolve(): tess / 'bin/tesseract'}
    queue = list(originals)
    licences = target / 'licences'; licences.mkdir()
    while queue:
        original = queue.pop()
        destination = originals[original]
        shutil.copy2(original, destination)
        subprocess.run(['codesign', '--remove-signature', str(destination)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for dependency in dependencies(original):
            if dependency.startswith(('/System/', '/usr/lib/')):
                continue
            if dependency.startswith('@rpath/'):
                leaf = dependency.removeprefix('@rpath/')
                candidates = [original.parent / leaf, Path('/opt/homebrew/lib') / leaf]
                resolved = next((p.resolve() for p in candidates if p.is_file()), Path(dependency))
            elif dependency.startswith('@loader_path/'):
                resolved = (original.parent / dependency.removeprefix('@loader_path/')).resolve()
            else:
                resolved = Path(dependency).resolve()
            if resolved == original:
                continue
            if not str(resolved).startswith('/opt/homebrew/') or not resolved.is_file():
                raise ValueError(f'Unresolved non-system library: {dependency}')
            if resolved not in originals:
                shared = tess / 'lib' / resolved.name
                if shared in originals.values():
                    raise ValueError(f'Duplicate library basename: {resolved.name}')
                originals[resolved] = shared; queue.append(resolved)
            relative = os.path.relpath(originals[resolved], destination.parent)
            subprocess.run(['install_name_tool', '-change', dependency, '@loader_path/' + relative, str(destination)], check=True)
        # Preserve upstream licence files from each Homebrew keg.
        if '/Cellar/' in str(original):
            parts = original.parts; pos = parts.index('Cellar'); keg = Path(*parts[:pos + 3])
            for path in keg.rglob('*'):
                if path.is_file() and path.name.lower().startswith(('license', 'licence', 'copying', 'copyright')):
                    output = licences / ('-'.join(parts[pos + 1:pos + 3])) / path.relative_to(keg)
                    output.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(path, output)
    minimum = (14, 0)
    for native in target.rglob('*'):
        if not native.is_file() or native.is_symlink():
            continue
        if native.suffix not in ('.so', '.dylib') and native.name not in ('python3.12', 'tesseract'):
            continue
        result = subprocess.run(['vtool', '-show-build', str(native)], capture_output=True, text=True)
        for value in re.findall(r'\bminos\s+(\d+\.\d+(?:\.\d+)?)', result.stdout):
            version = tuple(map(int, value.split('.')))
            minimum = max(minimum, version)
    (target / 'manifest.json').write_text(json.dumps({'minimum_macos': '.'.join(map(str, minimum)), 'python': sys.version, 'packages': copied, 'tesseract_libraries': [str(p.relative_to(tess)) for p in originals.values()]}, indent=2) + '\n')
    # Test from its final copied interpreter, with no user site or environment path.
    python = target / 'python/bin/python3.12'
    subprocess.run([str(python), '-I', '-B', '-c', 'import numpy,PIL,onnxruntime,tokenizers; print("Bundled formula imports ready")'], check=True, env={'PATH': '/usr/bin:/bin', 'HOME': '/var/empty'})
    for native in originals.values():
        subprocess.run(['codesign', '--force', '--sign', '-', str(native)], check=True)
    subprocess.run([str(tess / 'bin/tesseract'), '--version'], check=True, env={'PATH': '/usr/bin:/bin'})


if __name__ == '__main__':
    main()
