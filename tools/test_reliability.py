"""Exercise process limits, formula responses and thumbnail coalescing without an app build."""
import argparse
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
output = parser.parse_args().output.resolve()
if output == root or root in output.parents:
    parser.error('Keep generated evidence outside the repository')
output.mkdir(parents=True, exist_ok=True)
parts = ['Sources/BakerCore/BakerError.swift', 'Sources/BakerCore/LocalProcess.swift', 'Sources/BakerCore/LatexWhitespace.swift']
source = '\n'.join((root / p).read_text() for p in parts)
# Use the real diagnostics declaration, without the unrelated archive implementation.
archive = (root / 'Sources/BakerCore/FormulaArchive.swift').read_text()
source += '\n' + archive[archive.index('public struct FormulaDiagnostics:'):archive.index('public struct SavedFormula:')]
for name in ['Sources/Baker/FormulaResponse.swift', 'Sources/Baker/ThumbnailRequests.swift', 'Tests/BakerReliabilityRegression/main.swift']:
    source += '\n' + (root / name).read_text().replace('import BakerCore\n', '')
script = output / 'reliability.swift'
script.write_text(source)
with (output / 'regression.log').open('w') as log:
    result = subprocess.run(['swift', str(script)], stdout=log, stderr=subprocess.STDOUT)
print((output / 'regression.log').read_text())
raise SystemExit(result.returncode)
