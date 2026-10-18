#!/usr/bin/env python3
"""Check image retention, missing-file reconciliation and recoverable removal using authored fixtures."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
output = parser.parse_args().output.resolve()
if output == ROOT or ROOT in output.parents:
    parser.error('Keep evidence outside the repository')
output.mkdir(parents=True, exist_ok=True)
parts = sorted((ROOT / 'Sources/BakerCore').glob('*.swift'))
parts += [ROOT / 'Sources/Baker' / name for name in ['CaptureStore.swift','ThumbnailRequests.swift','CaptureLibrary.swift','ClipboardCoordinator.swift','FormulaResponse.swift','RecognitionCoordinator.swift','DocumentCoordinator.swift','FileExportCoordinator.swift','Motion.swift']]
source = '\n'.join(p.read_text().replace('import BakerCore\n','').replace('Bundle.module','Bundle.main') for p in parts)
source += (ROOT / 'Tests/BakerHistoryRetentionRegression/main.swift').read_text()
script = output / 'history-retention.swift'
script.write_text(source)
result = subprocess.run(['swift', str(script), str(output)], capture_output=True, text=True, timeout=120)
(output / 'regression.log').write_text(result.stdout + result.stderr)
print(result.stdout if result.returncode == 0 else result.stdout + result.stderr[-4000:])
raise SystemExit(result.returncode)
