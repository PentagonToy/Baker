"""Check gallery copy formats without touching the general clipboard or running OCR."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
out = parser.parse_args().output.resolve()
if out == ROOT or ROOT in out.parents:
    parser.error('Keep generated evidence outside the repository')
out.mkdir(parents=True, exist_ok=True)
parts = ['Sources/BakerCore/LatexWhitespace.swift', 'Sources/BakerCore/LatexCopyStyle.swift',
         'Sources/BakerCore/UnicodeMath.swift', 'Sources/BakerCore/KeynoteLatex.swift']
source = '\n'.join((ROOT / part).read_text() for part in parts)
result = (ROOT / 'Sources/Baker/FormulaResult.swift').read_text()
source += '\n' + result[result.index('enum OutputFormat:'):result.index('enum CaptureAction')]
source += '\n' + result[result.index('enum FormulaHistoryOutput'):]
source += '\n' + (ROOT / 'Tests/BakerFormulaHistoryRegression/main.swift').read_text()
script = out / 'history.swift'
script.write_text(source)
run = subprocess.run(['swift', str(script)], capture_output=True, text=True, timeout=90)
(out / 'copy.log').write_text(run.stdout + run.stderr)
print(run.stdout + run.stderr)
raise SystemExit(run.returncode)
