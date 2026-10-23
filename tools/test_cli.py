#!/usr/bin/env python3
"""Exercise CLI discovery and local conversion without reading credentials or starting Baker."""
import argparse
from pathlib import Path
import subprocess
r = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
o = p.parse_args().output.resolve()
if o == r or r in o.parents:
    p.error('Keep evidence outside the repository')
o.mkdir(parents=True, exist_ok=True)
names = ['Sources/BakerCore/BakerError.swift', 'Sources/BakerCore/LocalProcess.swift', 'Sources/BakerCore/LatexWhitespace.swift', 'Sources/BakerCore/UnicodeMath.swift', 'Sources/Baker/RuntimeDiagnostics.swift', 'Sources/Baker/BakerCLI.swift']
s = '\n'.join((r/n).read_text().replace('import BakerCore\n', '') for n in names)
s += '\nenum FormulaAdapter { struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } } }\n'
s += (r/'Tests/BakerCLIRegression/main.swift').read_text()
f = o/'checks.swift'
f.write_text(s)
a = subprocess.run(['swift', str(f)], capture_output=True, text=True, timeout=120)
(o/'checks.log').write_text(a.stdout+a.stderr)
print(a.stdout if not a.returncode else a.stdout+a.stderr)
raise SystemExit(a.returncode)
