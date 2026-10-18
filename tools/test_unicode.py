#!/usr/bin/env python3
"""Check Unicode conversion from current Swift sources without building Baker."""
import argparse
from pathlib import Path
import subprocess
import re
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
if output == ROOT or ROOT in output.parents:
    parser.error('Keep generated evidence outside the repository')
output.mkdir(parents=True, exist_ok=True)
# Check scalar identity independently of the Swift lookup implementation.
conversion = (ROOT / 'Sources/BakerCore/UnicodeMath.swift').read_text()
maps = re.findall(r'private static let (super|sub)scripts = Dictionary\(uniqueKeysWithValues: zip\(Array\("([^"]+)"\), Array\("([^"]+)"\)', conversion)
assert len(maps) == 2, 'Expected both script maps'
pairs = 0
for name, keys, values in maps:
    assert len(keys) == len(values), name
    for key, value in zip(keys, values):
        base = unicodedata.normalize('NFKC', value)
        assert base == key or (key == '-' and base == '−'), (name, key, value, base)
        pairs += 1
print(f'Checked {pairs} script scalar identities; production normalisation remains NFC')
parts = ['Sources/BakerCore/LatexWhitespace.swift', 'Sources/BakerCore/UnicodeMath.swift',
         'Tests/BakerUnicodeRegression/main.swift']
script = output / 'unicode-regression.swift'
script.write_text('\n'.join((ROOT / part).read_text() for part in parts))
result = subprocess.run(['swift', str(script), str(ROOT / 'Tests/BakerUnicodeRegression/preview-symbols.json')], capture_output=True, text=True)
(output / 'regression.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr)
raise SystemExit(result.returncode)
