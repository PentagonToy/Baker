#!/usr/bin/env python3
"""Check generated Finder records without building or mounting an installer."""
import argparse
from pathlib import Path
import plistlib
import struct
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
out = parser.parse_args().output.resolve()
if out == root or root in out.parents:
    parser.error('Keep generated evidence outside the repository')
out.mkdir(parents=True, exist_ok=True)
alias = out / 'fixture-alias'
alias.write_bytes(b'fixture background alias')
subprocess.run(['swift', str(root / 'tools/dmg_layout.swift'), 'layout', str(out), str(alias)], check=True)
data = (out / '.DS_Store').read_bytes()
assert data[4:8] == b'Bud1'
# The layout intentionally emits a single B-tree leaf at buddy offset 8192.
position = 8196

def number():
    global position
    value = struct.unpack_from('>I', data, position)[0]
    position += 4
    return value

assert number() == 0
count = number()
records = {}
for _ in range(count):
    length = number() * 2
    name = data[position:position + length].decode('utf-16-be')
    position += length
    code = data[position:position + 4].decode('ascii')
    kind = data[position + 4:position + 8].decode('ascii')
    position += 8
    size = number() if kind == 'blob' else 4
    records[name, code] = data[position:position + size]
    position += size
assert count == 6
assert struct.unpack('>IIII', records['Baker.app', 'Iloc'])[:2] == (180, 195)
assert struct.unpack('>IIII', records['Applications', 'Iloc'])[:2] == (520, 195)
icons = plistlib.loads(records['.', 'icvp'])
assert icons['iconSize'] == 112 and icons['backgroundImageAlias'] == alias.read_bytes()
assert icons['arrangeBy'] == 'none'
window = plistlib.loads(records['.', 'bwsp'])
assert not window['ShowToolbar'] and not window['ShowSidebar']
assert not any('remile' in name for name, _ in records)
print('Installer layout: 8 checks passed')
