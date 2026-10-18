#!/usr/bin/env python3
"""Exercise local tracing, transparency, Undo and one-file archive conversions without an app build."""
import argparse
from pathlib import Path
import subprocess
import sys
from prepare_image_tools import stage

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
out = a.output.resolve()
if out == ROOT or ROOT in out.parents:
    p.error('Keep evidence outside the checkout')
out.mkdir(parents=True, exist_ok=True)
tools = out/'ImageTools'
if not tools.exists():
    stage(tools)
parts = [ROOT/'Sources/BakerCore'/name for name in ['BakerError.swift', 'CaptureRetention.swift', 'CaptureArchive.swift', 'CaptureSVG.swift', 'PaperBackground.swift', 'ImageBackgroundRemoval.swift', 'ImageVectoriser.swift', 'LocalProcess.swift', 'OCRLanguages.swift', 'ImageClipboard.swift', 'MathClipboard.swift', 'FormulaArchive.swift', 'RecordingArchive.swift']]
parts += [ROOT/'Sources/Baker'/name for name in ['Preferences.swift', 'Typography.swift', 'CapturePalette.swift', 'ClipboardCoordinator.swift', 'CaptureStore.swift']]
source = '\n'.join(f.read_text().replace('import BakerCore\n', '').replace('Bundle.module', 'Bundle.main') for f in parts)
editor = (ROOT/'Sources/Baker/CaptureEditor.swift').read_text()
source += editor[:editor.index('struct CaptureEditorView:')].replace('import BakerCore\n', '')
output_source = (ROOT/'Sources/Baker/Workbench+Output.swift').read_text()
copy_function = output_source[output_source.index('    func copyImageFile'):output_source.index('    var output:')]
source += '@MainActor final class SVGCopyProbe { let clipboardFlow: ClipboardCoordinator; var shuttingDown = false; var status = ""; init(_ flow: ClipboardCoordinator) { clipboardFlow = flow }; func report(_ error: Error, fallback: BakerError.Code) { status = error.localizedDescription };\n' + copy_function + '\n}\n'
source += (ROOT/'Tests/BakerImageToolsRegression/main.swift').read_text()
script = out/'image-tools.swift'
script.write_text(source)
r = subprocess.run(['swift', str(script), str(out), str(tools), sys.executable, str(ROOT/'Sources/Baker/Resources/image_tools_worker.py')], capture_output=True, text=True, timeout=180)
(out/'checks.log').write_text(r.stdout+r.stderr)
print(r.stdout if r.returncode == 0 else (r.stdout+r.stderr)[-6000:])
raise SystemExit(r.returncode)
