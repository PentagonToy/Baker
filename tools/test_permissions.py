#!/usr/bin/env python3
"""Check permission state and reopen arguments without changing TCC, Keychain or the running app."""
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
permission = (ROOT/'Sources/Baker/ScreenRecordingPermission.swift').read_text()
source = (ROOT/'Sources/BakerCore/BakerError.swift').read_text()
source += permission[:permission.index('struct ScreenRecordingPermissionView:')]
source += (ROOT/'Sources/Baker/AppReopen.swift').read_text().replace('import BakerCore\n', '')
source += (ROOT/'Tests/BakerPermissionRegression/main.swift').read_text()
script = out/'permissions.swift'; script.write_text(source)
r = subprocess.run(['swift', str(script)], capture_output=True, text=True, timeout=60)
(out/'checks.log').write_text(r.stdout+r.stderr)
print(r.stdout if r.returncode == 0 else (r.stdout+r.stderr)[-4000:])
raise SystemExit(r.returncode)
