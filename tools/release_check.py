"""Audit a prepared app without building, installing, tagging or publishing it."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def audit(app, external_engine=None):
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
    engine = external_engine or resources / 'DocumentEngine'
    descriptor = None
    if not (resources / 'DocumentEngine').is_dir():
        descriptor = json.loads((resources / 'pdf-engine.json').read_text())
        if not descriptor.get('available'): blockers.append('Optional PDF engine asset is not published; keep this build local')
        if descriptor.get('schema') != 1 or len(descriptor.get('archive_sha256', '')) != 64: blockers.append('Invalid optional PDF descriptor')
    checked = 0
    formula_root = resources / 'Runtime/mfr'
    if formula_root.is_dir():
        formula = json.loads((resources / 'formula-model.json').read_text())
        for name, entry in formula['files'].items():
            path = formula_root / name
            if not path.is_file() or hashlib.file_digest(path.open('rb'), 'sha256').hexdigest() != entry['sha256']:
                blockers.append('Capture formula model integrity failed: ' + name)
            checked += 1
    if engine.is_dir():
        expected = json.loads((ROOT / 'tools/recognition/model-provenance.json').read_text())
        actual = json.loads((engine / 'PROVENANCE.json').read_text())
        if actual != expected: blockers.append('Repackage the engine with current checkpoint provenance')
        notices = json.loads((ROOT / 'tools/recognition/notices/sources.json').read_text())
        for name, entry in notices.items():
            path = engine / 'notices' / name
            if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
                blockers.append('Missing or changed upstream model card: ' + name)
        manifest = json.loads((engine / 'manifest.json').read_text())
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
            'signing_description': signing.stderr.strip(), 'model_files_checked': checked, 'external_pdf_engine': str(external_engine) if external_engine else None,
            'blockers': blockers, 'manual_checks': ['Clean-machine installation and first OCR run', 'Packaged DMG and corresponding source', 'Signing/notarisation status described accurately'],
            'ready_to_publish': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--pdf-engine', type=Path, help='Audit a separately unpacked PDF engine as well as the base app')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists(): raise ValueError('Preserve existing reports; choose a fresh output')
    report = audit(args.app.resolve(), args.pdf_engine.resolve() if args.pdf_engine else None)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
