#!/usr/bin/env python3
"""Exercise recording exports without building or installing the app."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
if output == ROOT or ROOT in output.parents:
    parser.error('Keep generated evidence outside the repository')
output.mkdir(parents=True, exist_ok=True)
parts = ['Sources/BakerCore/BakerError.swift', 'Sources/BakerCore/RecordingMedia.swift',
         'Tests/BakerRecordingRegression/main.swift']
script = output / 'recording.swift'
script.write_text('\n'.join((ROOT / part).read_text().replace('import BakerCore\n', '') for part in parts))
with (output / 'regression.log').open('w') as log:
    result = subprocess.run(['swift', str(script), str(output / 'media')], stdout=log, stderr=subprocess.STDOUT)
print((output / 'regression.log').read_text())
if result.returncode:
    raise SystemExit(result.returncode)
# Exercise production preference migration and desktop-coordinate placement directly.
menu = (ROOT / 'Sources/Baker/MenuLayout.swift').read_text()
setup = (ROOT / 'Sources/Baker/RecordingSetup.swift').read_text()
source = '\n'.join((ROOT / name).read_text().replace('import BakerCore\n', '') for name in ['Sources/BakerCore/BakerError.swift', 'Sources/BakerCore/OCRLanguages.swift', 'Sources/Baker/Preferences.swift']) + '\nimport AppKit\n' + menu[menu.index('struct BakerMenuGroup'):menu.index('@MainActor private final class MenuLayoutDraft')]
source += setup[setup.index('enum RecordingPlacement'):setup.index('final class RecordingPanel')]
source += (ROOT / 'Tests/BakerRecordingUIRegression/main.swift').read_text()
script = output / 'recording-ui-model.swift'
script.write_text(source)
result = subprocess.run(['swift', str(script)], capture_output=True, text=True)
(output / 'ui-model.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr)
raise SystemExit(result.returncode)
