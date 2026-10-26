"""Exercise plugin ZIP and process boundaries with synthetic inputs, without network access."""
import argparse
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', required=True, type=Path)
out = p.parse_args().output.resolve()
if out == ROOT or ROOT in out.parents:
    p.error('Keep generated evidence outside the repository')
out.mkdir(parents=True, exist_ok=True)
for name in ["package", "state"]:
    shutil.rmtree(out / name, ignore_errors=True)
for name in ["export.md", "unsafe.md"]:
    (out / name).unlink(missing_ok=True)
script = out / 'plugin.swift'
script.write_text('\n'.join(f.read_text().replace('Bundle.module', 'Bundle.main') for f in sorted((ROOT / 'Sources/BakerCore').glob('*.swift'))) + '\n' + (ROOT / 'Tests/BakerPluginRegression/main.swift').read_text())
r = subprocess.run(['swift', str(script), str(out), sys.executable, str(ROOT / 'Tests/BakerPluginRegression/worker.py')], capture_output=True, text=True, timeout=120)
(out / 'protocol.log').write_text(r.stdout + r.stderr)
print(r.stdout if r.returncode == 0 else (r.stdout + r.stderr)[-6000:])
if r.returncode:
    raise SystemExit(r.returncode)
checks = 0
for name, contents, safe, mode in [('normal', 'plugin.json', True, None), ('parent', '../escape', False, None), ('absolute', '/escape', False, None), ('windows', 'a\\b', False, None), ('alias', 'a/./b', False, None), ('link', 'link', False, stat.S_IFLNK | 0o777)]:
    archive = out / (name + '.zip')
    with zipfile.ZipFile(archive, 'w') as z:
        item = zipfile.ZipInfo(contents)
        if mode:
            item.create_system = 3
            item.external_attr = mode << 16
        z.writestr(item, '{}')
    target = out / ('unpacked-' + name)
    shutil.rmtree(target, ignore_errors=True)
    target.mkdir()
    run = subprocess.run([sys.executable, str(ROOT / 'Sources/Baker/Resources/plugin_unpack.py'), str(archive), str(target)], capture_output=True)
    assert (run.returncode == 0) == safe, name
    checks += 1
print(f'Plugin ZIP: {checks} checks passed')

route = out / 'routing.swift'
route.write_text('\n'.join(f.read_text().replace('Bundle.module', 'Bundle.main') for f in sorted((ROOT / 'Sources/BakerCore').glob('*.swift'))) + '\n' + (ROOT / 'Tests/BakerPluginRegression/routing.swift').read_text() + '\n' + (ROOT / 'Sources/Baker/Workbench+Recognition.swift').read_text().replace('import BakerCore', ''))
r = subprocess.run(['swift', str(route)], capture_output=True, text=True, timeout=120)
(out / 'routing.log').write_text(r.stdout + r.stderr)
print(r.stdout if r.returncode == 0 else (r.stdout + r.stderr)[-6000:])
raise SystemExit(r.returncode)
