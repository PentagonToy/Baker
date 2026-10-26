#!/usr/bin/env python3
"""Check pixel edits, palette and saved-area geometry without building or capturing the screen."""
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
source = '\n'.join((ROOT / 'Sources/BakerCore' / name).read_text() for name in ['BakerError.swift', 'CaptureRetention.swift', 'CaptureArchive.swift', 'CaptureSVG.swift', 'PaperBackground.swift', 'ImageBackgroundRemoval.swift', 'ImageVectoriser.swift', 'LocalProcess.swift'])
source += (ROOT / 'Sources/BakerCore/OCRLanguages.swift').read_text()
source += (ROOT / 'Sources/Baker/Preferences.swift').read_text().replace('import BakerCore\n', '')
source += (ROOT / 'Sources/Baker/Typography.swift').read_text()
source += (ROOT / 'Sources/Baker/CapturePalette.swift').read_text()
editor = (ROOT / 'Sources/Baker/CaptureEditor.swift').read_text()
source += editor[:editor.index('struct CaptureEditorView:')].replace('import BakerCore\n', '')
service = (ROOT / 'Sources/Baker/CaptureService.swift').read_text()
source += service[service.index('struct CaptureRegion'):service.index('@MainActor\nfinal class CaptureService')]
source += (ROOT / 'Sources/Baker/RepeatCaptureArea.swift').read_text().replace('import BakerCore\n', '')
shortcuts = (ROOT / 'Sources/Baker/CaptureShortcuts.swift').read_text()
source += '\nenum CaptureShortcuts {\n' + shortcuts[shortcuts.index('    static let actions ='):shortcuts.index('    @Published private(set)')] + '\n}\n'
source += (ROOT / 'Tests/BakerEditorRegression/main.swift').read_text()
script = output / 'editor-regression.swift'
script.write_text(source)
result = subprocess.run(['swift', str(script)], capture_output=True, text=True)
(output / 'regression.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr)
raise SystemExit(result.returncode)
