"""Exercise engine selection and atomic provisioning with isolated settings and tiny files."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True)
out = p.parse_args().output.resolve()
if out == ROOT or ROOT in out.parents:
    p.error('Keep generated evidence outside the repository')
out.mkdir(parents=True, exist_ok=True)
parts = ['Sources/BakerCore/BakerError.swift', 'Sources/BakerCore/ModelIntegrity.swift', 'Sources/BakerCore/LocalProcess.swift', 'Sources/BakerCore/OCRLanguages.swift',
         'Sources/Baker/Preferences.swift', 'Sources/Baker/FormulaEngine.swift']
source = '\n'.join((ROOT / name).read_text().replace('import BakerCore\n', '').replace('Bundle.module', 'Bundle.main') for name in parts)
setup = (ROOT / 'Sources/Baker/FormulaSetup.swift').read_text().split('struct FormulaSetupView:')[0]
source += '\n' + setup.replace('import BakerCore\n', '').replace('Bundle.module', 'Bundle.main')
source += '\n' + (ROOT / 'Tests/BakerFormulaEngineRegression/main.swift').read_text()
script = out / 'engines.swift'
script.write_text(source)
result = subprocess.run(['swift', str(script), str(out)], capture_output=True, text=True, timeout=90)
(out / 'regression.log').write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr[-3000:])
raise SystemExit(result.returncode)
