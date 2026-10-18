#!/usr/bin/env python3
"""Check durable recording history using existing authored MP4/GIF fixtures, without screen access."""
import argparse
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--fixtures', type=Path, required=True)
a = p.parse_args()
out = a.output.resolve()
if out == root or root in out.parents:
    p.error('Keep evidence outside the repository')
out.mkdir(parents=True, exist_ok=True)
parts = [root/'Sources/BakerCore'/n for n in ['BakerError.swift', 'RecordingArchive.swift']]
parts += [root/'Tests/BakerRecordingHistoryRegression/main.swift']
script = out/'history.swift'
script.write_text('\n'.join(f.read_text() for f in parts))
r = subprocess.run(['swift', str(script), str(out), str(a.fixtures.resolve())], text=True, capture_output=True, timeout=90)
(out/'regression.log').write_text(r.stdout+r.stderr)
print(r.stdout if r.returncode == 0 else r.stderr[-4000:])
raise SystemExit(r.returncode)
