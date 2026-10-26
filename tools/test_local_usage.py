"""Check local-only counters in an isolated preference domain."""
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
source = (ROOT / 'Sources/Baker/LocalUsage.swift').read_text().split('@MainActor private final class UsageSettingsState')[0]
source += '\nstruct UsageKey { let name: String }\nenum PreferenceKeys { static let recognitionUsage = UsageKey(name: "recognitionUsage") }\n'
source += (ROOT / 'Tests/BakerLocalUsageRegression/main.swift').read_text()
script = out / 'usage.swift'
script.write_text(source)
run = subprocess.run(['swift', str(script)], capture_output=True, text=True, timeout=90)
(out / 'checks.log').write_text(run.stdout + run.stderr)
print(run.stdout + run.stderr)
raise SystemExit(run.returncode)
