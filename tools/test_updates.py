#!/usr/bin/env python3
"""Validate update selection and lifecycle with injected metadata, time and preferences."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
out = p.parse_args().output.resolve()
if out == ROOT or ROOT in out.parents:
    p.error('Keep evidence outside the checkout')
out.mkdir(parents=True, exist_ok=True)
files = ['Sources/BakerCore/BakerError.swift', 'Sources/BakerCore/OCRLanguages.swift', 'Sources/BakerCore/AppRelease.swift', 'Sources/Baker/Preferences.swift']
source = '\n'.join((ROOT / f).read_text().replace('import BakerCore\n', '') for f in files)
source += (ROOT / 'Sources/Baker/AppUpdates.swift').read_text().split('struct AppUpdatesSettings:')[0].replace('import BakerCore\n', '')
source += (ROOT / 'Tests/BakerUpdateRegression/main.swift').read_text()
script = out / 'updates.swift'
script.write_text(source)
r = subprocess.run(['swift', str(script)], capture_output=True, text=True, timeout=60)
(out / 'checks.log').write_text(r.stdout + r.stderr)
print(r.stdout if r.returncode == 0 else (r.stdout + r.stderr)[-5000:])
raise SystemExit(r.returncode)
