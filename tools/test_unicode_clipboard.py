#!/usr/bin/env python3
"""Verify Unicode clipboard representations without changing the system clipboard."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--results', type=Path, required=True, help='results.json from audit_unicode.py')
parser.add_argument('--app-bundle', type=Path, required=True, help='Existing Baker.app supplying font resources')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
if output == ROOT or ROOT in output.parents:
    parser.error('Keep generated evidence outside the repository')
if not (args.app_bundle / 'Contents/Resources/Fonts').is_dir():
    parser.error('The app bundle must already contain Baker font resources')
output.mkdir(parents=True, exist_ok=True)
parts = ['Sources/BakerCore/MathClipboard.swift', 'Tests/BakerUnicodeClipboardRegression/main.swift']
script = output / 'clipboard.swift'
script.write_text('\n'.join((ROOT / part).read_text().replace('import BakerCore\n', '') for part in parts))
result = subprocess.run(['swift', str(script), str(args.results.resolve()), str(args.app_bundle.resolve())], capture_output=True, text=True)
(output / 'regression.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr)
raise SystemExit(result.returncode)
