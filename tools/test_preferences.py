#!/usr/bin/env python3
"""Check preference compatibility and typed failures without building or installing Baker."""
import argparse
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
output = parser.parse_args().output.resolve()
if output == ROOT or ROOT in output.parents:
    parser.error('Keep generated evidence outside the repository')
output.mkdir(parents=True, exist_ok=True)
parts = ['Sources/BakerCore/BakerError.swift', 'Sources/BakerCore/LocalProcess.swift', 'Sources/BakerCore/ModelIntegrity.swift', 'Sources/BakerCore/OCRLanguages.swift',
         'Sources/BakerCore/MathClipboard.swift', 'Sources/BakerCore/LatexWhitespace.swift',
         'Sources/BakerCore/LatexCopyStyle.swift', 'Sources/Baker/Preferences.swift', 'Sources/Baker/PreferenceBindings.swift', 'Sources/Baker/SettingsPreset.swift']
source = '\n'.join((ROOT / p).read_text().replace('import BakerCore\n', '').replace('Bundle.module', 'Bundle.main') for p in parts)
formula = (ROOT / 'Sources/Baker/FormulaResult.swift').read_text()
source += '\n' + next(line for line in formula.splitlines() if line.startswith('enum OutputFormat:')) + '\n'
settings = (ROOT / 'Sources/Baker/BakerSettings.swift').read_text()
source += settings[settings.index('enum SettingsPage:'):settings.index('@MainActor final class SettingsState')]
workbench = (ROOT / 'Sources/Baker/Workbench.swift').read_text()
reporting = workbench[workbench.index('    @Published var problem:'):workbench.index('    @Published var exportURL:')].replace('@Published ', '')
source += '\nfinal class ErrorHarness {\nvar shuttingDown = false\n' + reporting + '\n}\n'
pdf = (ROOT / 'Sources/Baker/PDFEngineSetup.swift').read_text()
unpack = pdf[pdf.index('    nonisolated private static func unpack('):pdf.index('    func cancel()')].replace('nonisolated private static', 'static')
source += '\nenum InstallerHarness {\n' + unpack + '\n}\n'
source += (ROOT / 'Tests/BakerPreferencesRegression/main.swift').read_text()
script = output / 'preferences-errors.swift'
script.write_text(source)
result = subprocess.run(['swift', str(script), str(output)], capture_output=True, text=True)
(output / 'regression.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr)
if result.returncode:
    raise SystemExit(result.returncode)
registry = (ROOT / 'Sources/Baker/Preferences.swift').read_text()
names = re.findall(r'PreferenceKey\("([^"]+)"', registry)
assert len(names) == len(set(names)), 'Preference names must be unique'
for path in (ROOT / 'Sources').rglob('*.swift'):
    if path.name == 'Preferences.swift':
        continue
    text = path.read_text()
    assert not re.search(r'@AppStorage\("', text), path
    assert not re.search(r'(?:string|data|bool|integer|object)\(forKey: "', text), path
# Compile-time enforcement: BakerError has no default unclassified code.
error = (ROOT / 'Sources/BakerCore/BakerError.swift').read_text()
assert 'code: Code,' in error and 'code: Code =' not in error
print('Verified', len(names), 'unique persisted keys and no scattered preference literals')
