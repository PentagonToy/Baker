#!/usr/bin/env python3
"""Exercise the app's offline WebKit renderer without building or installing Baker."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True, help='Evidence directory outside the repository')
args = parser.parse_args()
output = args.output.resolve()
if output == ROOT or ROOT in output.parents:
    parser.error('Keep generated evidence outside the repository')
output.mkdir(parents=True, exist_ok=True)
resources = ROOT / 'Sources/Baker/Resources/FormulaPreview'
manifest = json.loads((resources / 'vendor.json').read_text())
for name, digest in manifest['files'].items():
    assert hashlib.sha256((resources / name).read_bytes()).hexdigest() == digest, name
parts = ['Sources/BakerCore/BakerError.swift', 'Sources/BakerCore/LatexWhitespace.swift',
         'Sources/Baker/FormulaPreviewRenderer.swift', 'Tests/BakerPreviewRegression/main.swift']
# Flatten the local source imports for the Swift interpreter; no production logic is replaced.
source = '\n'.join((ROOT / p).read_text().replace('import BakerCore\n', '') for p in parts)
script = output / 'preview-regression.swift'
script.write_text(source)
with (output / 'regression.log').open('w') as log:
    result = subprocess.run(['swift', str(script), str(resources), str(output / 'images')], stdout=log, stderr=subprocess.STDOUT)
print((output / 'regression.log').read_text())
raise SystemExit(result.returncode)
