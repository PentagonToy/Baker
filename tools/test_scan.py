#!/usr/bin/env python3
"""Exercise recoverable scan drafts and atomic PDF export using authored images; no screen capture."""
import argparse
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--ocr', action='store_true', help='Also run one local Vision OCR export on authored text')
args = p.parse_args()
out = args.output.resolve()
if out == root or root in out.parents:
    p.error('Keep generated evidence outside the repository')
out.mkdir(parents=True, exist_ok=True)
parts = [root/'Sources/BakerCore'/name for name in ['BakerError.swift', 'OCRLanguages.swift', 'ScanOptions.swift', 'ScanDocument.swift']]
source = '\n'.join(f.read_text() for f in parts)
source += (root/'Tests/BakerScanRegression/main.swift').read_text()
script = out/'scan.swift'
script.write_text(source)
r = subprocess.run(['swift', str(script), str(out), *(['--ocr'] if args.ocr else [])], capture_output=True, text=True, timeout=120)
(out/'scan.log').write_text(r.stdout+r.stderr)
print(r.stdout if r.returncode == 0 else (r.stdout+r.stderr)[-6000:])
raise SystemExit(r.returncode)
