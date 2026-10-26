#!/usr/bin/env python3
"""Check guide progress without capturing screens or changing user preferences."""
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
preferences = (root / 'Sources/Baker/Preferences.swift').read_text()
preferences = preferences[:preferences.index('/// An inexpensive')]
source = preferences.replace('import BakerCore\n', '')
source += '\nimport Combine\nenum OCRLanguages { static let defaults = ["ko-KR", "en-US", "de-DE"] }\n'
full_preferences = (root / 'Sources/Baker/Preferences.swift').read_text()
source += full_preferences[full_preferences.index('/// An inexpensive'):full_preferences.index('    var captureDirectory:')] + '}\n'
source += 'struct FormulaResult { enum Phase { case recognising, ready, failed }; let phase: Phase }\n'
guide = (root / 'Sources/Baker/QuickStart.swift').read_text()
source += guide[guide.index('/// Presentation progress'):guide.index('struct QuickStartActions')]
source += (root / 'Tests/BakerQuickStartRegression/main.swift').read_text()
script = output / 'checks.swift'
script.write_text(source)
result = subprocess.run(['swift', str(script)], capture_output=True, text=True, timeout=120)
(output / 'checks.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr)
raise SystemExit(result.returncode)
