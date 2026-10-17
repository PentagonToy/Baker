"""Audit a prepared app without building, installing, tagging or publishing it."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def audit(app):
    blockers = []
    version = (ROOT / 'VERSION').read_text().strip()
    resources = app / 'Contents/Resources'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleShortVersionString') != version: blockers.append('App version differs from VERSION')
    if info.get('CFBundleIdentifier') != 'local.baker.app': blockers.append('Unexpected app identifier')
    signature = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True, text=True)
    if signature.returncode: blockers.append('App signature verification failed')
    signing = subprocess.run(['codesign', '-dv', str(app)], capture_output=True, text=True)
    licence = ROOT / 'LICENSE'
    if not licence.is_file(): blockers.append('Select and include a licence for Baker source before binary distribution')
    elif not (resources / 'Legal/LICENSE').is_file() or (resources / 'Legal/LICENSE').read_bytes() != licence.read_bytes():
        blockers.append('Repackage the app with the selected Baker source licence')
    if not (resources / 'Legal/THIRD-PARTY.md').is_file(): blockers.append('Include third-party notices in the app')
    engine = resources / 'DocumentEngine'
    expected = json.loads((ROOT / 'tools/recognition/model-provenance.json').read_text())
    actual = json.loads((engine / 'PROVENANCE.json').read_text())
    if actual != expected: blockers.append('Repackage the engine with current checkpoint provenance')
    notices = json.loads((ROOT / 'tools/recognition/notices/sources.json').read_text())
    for name, entry in notices.items():
        path = engine / 'notices' / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
            blockers.append('Missing or changed upstream model card: ' + name)
    manifest = json.loads((engine / 'manifest.json').read_text())
    checked = 0
    for name, entry in manifest['files'].items():
        if Path(name).suffix not in ('.safetensors', '.onnx'): continue
        path = engine / name
        if not path.resolve().is_relative_to(engine.resolve()): raise ValueError('Model path leaves the engine')
        if not path.is_file() or hashlib.file_digest(path.open('rb'), 'sha256').hexdigest() != entry['sha256']:
            blockers.append('Model integrity check failed: ' + name)
        checked += 1
    return {'version': version, 'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip()),
            'app': str(app), 'binary_sha256': hashlib.sha256((app / 'Contents/MacOS/Baker').read_bytes()).hexdigest(),
            'minimum_macos': info.get('LSMinimumSystemVersion'), 'signature_verified': signature.returncode == 0,
            'signing_description': signing.stderr.strip(), 'model_files_checked': checked,
            'blockers': blockers, 'manual_checks': ['Clean-machine installation and first OCR run', 'Packaged DMG and corresponding source', 'Signing/notarisation status described accurately'],
            'ready_to_publish': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists(): raise ValueError('Preserve existing reports; choose a fresh output')
    report = audit(args.app.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
