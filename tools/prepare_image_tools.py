#!/usr/bin/env python3
"""Verify pinned local image tools and stage them; no downloads or package installation."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'others/image-tools'


def stage(destination, relocate=False):
    destination = Path(destination).resolve()
    if destination == ROOT or ROOT in destination.parents:
        raise ValueError('Stage image tools outside the checkout')
    manifest = json.loads((SOURCE/'manifest.json').read_text())
    for item in manifest['files']:
        source = SOURCE/item['path']
        if hashlib.file_digest(source.open('rb'), 'sha256').hexdigest() != item['sha256']:
            raise ValueError('Image-tool integrity failed: '+item['path'])
    if destination.exists():
        raise ValueError('Use a fresh image-tool staging directory')
    destination.mkdir(parents=True)
    try:
        wheel = SOURCE/'vendor/vtracer-0.6.15-cp312-cp312-macosx_11_0_arm64.whl'
        with zipfile.ZipFile(wheel) as archive:
            for name in archive.namelist():
                if name.startswith('vtracer/') and not name.endswith('/'):
                    relative = Path(name)
                    if '..' in relative.parts or relative.is_absolute():
                        raise ValueError('Unsafe image-tool path')
                    target = destination/'python'/relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(name))
                if name.endswith('.dist-info/licenses/LICENSE'):
                    target = destination/'licences/VTRACER-LICENSE'
                    target.parent.mkdir(exist_ok=True)
                    target.write_bytes(archive.read(name))
        with zipfile.ZipFile(SOURCE/'vendor/potrace-1.16-arm64.zip') as archive:
            for name in ['bin/potrace', 'lib/libpotrace.0.dylib', 'licences/POTRACE-COPYING', 'licences/potrace-homebrew.rb']:
                target = destination/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(name))
        (destination/'bin/potrace').chmod(0o755)
        shutil.copytree(SOURCE/'sources', destination/'sources')
        shutil.copy2(SOURCE/'manifest.json', destination/'provenance.json')
        if relocate:
            binary = destination/'bin/potrace'
            library = destination/'lib/libpotrace.0.dylib'
            subprocess.run(['install_name_tool', '-change', '/opt/homebrew/Cellar/potrace/1.16/lib/libpotrace.0.dylib',
                            '@loader_path/../lib/libpotrace.0.dylib', str(binary)], check=True)
            subprocess.run(['install_name_tool', '-id', '@rpath/libpotrace.0.dylib', str(library)], check=True)
        return destination
    except BaseException:
        shutil.rmtree(destination)
        raise


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--destination', type=Path, required=True)
    p.add_argument('--relocate', action='store_true', help='Relocate native libraries during an authorised app build')
    args = p.parse_args()
    print(stage(args.destination, args.relocate))
