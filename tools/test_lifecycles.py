#!/usr/bin/env python3
"""Interpret window ownership and PDF process fixtures without building or installing Baker."""
import argparse
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
out = a.output.resolve()
if out == root or root in out.parents:
    p.error('Keep evidence outside the repository')
out.mkdir(parents=True, exist_ok=True)
settings = (root/'Sources/Baker/BakerSettings.swift').read_text()
state = settings[settings.index('enum SettingsPage:'):settings.index('struct BakerSettings:')]
window = '\n'.join((root/name).read_text() for name in ['Sources/BakerCore/BakerError.swift', 'Sources/Baker/WorkspaceWindows.swift'])
window += '\nimport SwiftUI\n' + state
window += (root/'Tests/BakerWindowLifecycleRegression/main.swift').read_text()
pdf = '\n'.join(f.read_text().replace('Bundle.module', 'Bundle.main') for f in sorted((root/'Sources/BakerCore').glob('*.swift')))
pdf += (root/'Tests/BakerPDFLifecycleRegression/main.swift').read_text()
for name, source, args in [('windows', window, []), ('pdf', pdf, [str(out), sys.executable, str(root/'Tests/BakerPDFLifecycleRegression/worker.py')])]:
    script = out/(name+'.swift')
    script.write_text(source)
    r = subprocess.run(['swift', str(script), *args], capture_output=True, text=True, timeout=120)
    (out/(name+'.log')).write_text(r.stdout+r.stderr)
    print(r.stdout if r.returncode == 0 else (r.stdout+r.stderr)[-5000:])
    if r.returncode:
        raise SystemExit(r.returncode)
