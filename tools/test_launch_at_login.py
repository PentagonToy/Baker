"""Check login-startup behaviour with fake system services; never changes Login Items."""
import argparse
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
output = parser.parse_args().output.resolve()
if output == root or root in output.parents:
    parser.error('Store generated checks outside the repository')
output.mkdir(parents=True, exist_ok=True)
source = '\n'.join((root / name).read_text() for name in ['Sources/BakerCore/BakerError.swift', 'Sources/BakerCore/OCRLanguages.swift', 'Sources/Baker/Preferences.swift', 'Sources/Baker/Typography.swift', 'Sources/Baker/LaunchAtLogin.swift', 'Tests/BakerLoginRegression/main.swift'])
script = output / 'login-regression.swift'
script.write_text(source.replace('import BakerCore\n', ''))
with (output / 'regression.log').open('w') as log:
    result = subprocess.run(['swift', str(script)], stdout=log, stderr=subprocess.STDOUT)
print((output / 'regression.log').read_text())
raise SystemExit(result.returncode)
