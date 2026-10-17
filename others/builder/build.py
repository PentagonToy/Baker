"""Build, check and replace the local Baker app, preserving the previous version."""
import argparse
from contextlib import contextmanager
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
BUILDER = Path(__file__).resolve().parent


def run(arguments, **kwargs):
    print('+', ' '.join(map(str, arguments)), flush=True)
    return subprocess.run(list(map(str, arguments)), check=True, **kwargs)


def settings(path):
    config = json.loads(path.read_text())
    workspace = next((p for p in ROOT.parents if (p / 'Agents/Environment').is_dir()), None)
    if workspace is None: raise ValueError('The Workspace/Agents environment could not be located.')
    chip = subprocess.check_output(['system_profiler', 'SPHardwareDataType'], text=True)
    if 'Apple M1 Pro' in chip: host = 'm1pro'
    elif 'Apple M5' in chip: host = 'm5'
    else: raise ValueError('This builder requires a configured Apple M1 Pro or M5 environment.')
    config.setdefault('document_python', str(workspace / f'Agents/Environment/{host}/bin/python'))
    config.setdefault('build_root', str(workspace / 'Agents/Repository/baker/builder'))
    config.setdefault('install_path', '/Applications/Baker.app')
    config.setdefault('formula_runtime', str(Path(config['install_path']) / 'Contents/Resources/Runtime'))
    return config


def preflight(config):
    if platform.system() != 'Darwin' or platform.machine() != 'arm64': raise ValueError('Use an Apple Silicon Mac.')
    for tool in ['swift', 'codesign', 'ditto', 'osascript', 'iconutil', 'vtool']:
        if shutil.which(tool) is None: raise ValueError('Missing build tool: ' + tool)
    engine_settings = ['small_ocr_payload', 'formula_models'] if config.get('small_ocr_payload') else ['document_configuration']
    for name in ['document_python', 'formula_runtime', 'smoke_pdf'] + engine_settings:
        if not config.get(name) or not Path(config[name]).exists(): raise ValueError('Prepare the builder setting: ' + name)
    for case in config.get('table_checks', []):
        for name in ['pdf','reference']:
            if not case.get(name) or not Path(case[name]).is_file(): raise ValueError('Prepare table check: ' + name)
    runtime = Path(config['formula_runtime'])
    if not (runtime / 'manifest.json').is_file() or not (runtime / 'python/bin/python3.12').is_file():
        raise ValueError('Select the complete formula Runtime, not a virtual environment.')
    build = Path(config['build_root']).resolve()
    if build == ROOT or build.is_relative_to(ROOT): raise ValueError('Build results must be outside the source checkout.')
    install = Path(config['install_path']).expanduser()
    if install.name != 'Baker.app' or install.is_symlink(): raise ValueError('Install to a real Baker.app directory, not a symlink.')
    if install.exists():
        with (install / 'Contents/Info.plist').open('rb') as stream: identifier = plistlib.load(stream).get('CFBundleIdentifier')
        if identifier != 'local.baker.app': raise ValueError('The installation target is not the Baker app.')
    if shutil.disk_usage(install.parent if install.parent.exists() else Path.home()).free < 4 * 1024**3:
        raise ValueError('Keep at least 4 GiB free on the application volume.')
    parent = build
    while not parent.exists(): parent = parent.parent
    if shutil.disk_usage(parent).free < 12 * 1024**3: raise ValueError('Keep at least 12 GiB free for staging and backups.')
    imports = 'import pix2text,pymupdf,optimum.onnxruntime' if not config.get('small_ocr_payload') else 'import json,hashlib,shutil'
    run([config['document_python'], '-I', '-B', '-c', 'import sys,platform; assert sys.version_info[:2]==(3,12) and platform.machine()=="arm64"; ' + imports])


@contextmanager
def lock(root):
    root.mkdir(parents=True, exist_ok=True)
    path = root / 'build.lock'
    try: descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError: raise ValueError('Another build or an interrupted build owns ' + str(path) + '. Check its PID before removing it.')
    os.write(descriptor, str(os.getpid()).encode()); os.close(descriptor)
    try: yield
    finally: path.unlink()


def replace_app(app, install, job):
    staged = install.with_name('.Baker-staged-' + str(os.getpid()) + '.app')
    previous = install.with_name('.Baker-previous-' + str(os.getpid()) + '.app')
    if staged.exists() or previous.exists(): raise ValueError('An installation staging path already exists; nothing was replaced.')
    install.parent.mkdir(parents=True, exist_ok=True)
    run(['ditto', app, staged])
    try: run(['codesign', '--verify', '--deep', '--strict', staged])
    except BaseException:
        if staged.exists(): shutil.rmtree(staged)
        raise
    # Preserve the old bundle before asking Baker to finish and quit normally.
    if install.exists(): run(['ditto', install, job / 'previous-Baker.app'])
    run(['osascript', '-e', 'if application id "local.baker.app" is running then tell application id "local.baker.app" to quit'])
    for _ in range(100):
        if subprocess.run(['pgrep', '-x', 'Baker'], stdout=subprocess.DEVNULL).returncode != 0: break
        time.sleep(.1)
    else: raise ValueError('Baker is still running. The checked build and previous app are preserved; close Baker and retry.')
    try:
        if install.exists(): install.rename(previous)
        staged.rename(install)
        run(['codesign', '--verify', '--deep', '--strict', install])
    except BaseException:
        if install.exists(): install.rename(install.with_name('.Baker-rejected-' + str(os.getpid()) + '.app'))
        if previous.exists(): previous.rename(install)
        raise
    if previous.exists(): shutil.rmtree(previous)  # A verified backup remains in the job folder.
    return job / 'previous-Baker.app'


def check_table_reference(actual, reference):
    def tables(path):
        return [(node['rows'],node.get('caption')) for line in path.read_text().splitlines()
                for node in json.loads(line)['nodes'] if node['kind']=='table']
    expected=tables(reference)
    if not expected or tables(actual)!=expected:
        raise ValueError('Table cells or captions differ from the accepted example: ' + str(actual))


def build(config, build_only):
    root = Path(config['build_root']).resolve()
    with lock(root):
        job = root / (datetime.now().strftime('%Y-%m-%d_%H-%M-%S') + '-' + str(os.getpid()))
        job.mkdir()
        if config.get('small_ocr_payload'):
            document = job / 'small-document-engine'
            run([config['document_python'], BUILDER / 'pack_small_engine.py', '--source', config['small_ocr_payload'],
                 '--formula', config['formula_models'], '--destination', document])
        else:
            environment = subprocess.check_output([config['document_python'], '-I', '-B', '-c',
                'import importlib.metadata as m,json; print(json.dumps(sorted((d.metadata["Name"],d.version) for d in m.distributions())))'])
            optimizer = ROOT / 'tools/optimize_document_models.py'
            optimize_key = hashlib.sha256(optimizer.read_bytes() + Path(config['document_configuration']).read_bytes()).hexdigest()[:16]
            optimized = root / ('optimized-models-' + optimize_key)
            run([config['document_python'], optimizer, '--configuration', config['document_configuration'],
                 '--manifest', ROOT / 'Sources/Baker/Resources/formula-model.json', '--destination', optimized])
            document_configuration = optimized / 'document-engine.json'
            key = hashlib.sha256((BUILDER / 'pack_document_engine.py').read_bytes() + document_configuration.read_bytes() + environment).hexdigest()[:16]
            document = root / ('document-engine-' + key)
            run([config['document_python'], BUILDER / 'pack_document_engine.py', '--destination', document, '--configuration', document_configuration])
        separate = bool(config.get('small_ocr_payload')) and not config.get('include_pdf_engine', False)
        distribution = Path(config['pdf_distribution']).expanduser() if config.get('pdf_distribution') else job / 'pdf-distribution'
        if separate:
            if config.get('pdf_distribution'):
                if not (distribution / 'pdf-engine.json').is_file(): raise ValueError('Select a tested PDF distribution with its pinned descriptor.')
            else:
                run([config['document_python'], BUILDER / 'package_pdf_engine.py', '--source', document, '--destination', distribution,
                     '--signing-identity', config.get('signing_identity', '-')])
            descriptor = json.loads((distribution / 'pdf-engine.json').read_text())
            if not build_only and not descriptor.get('available'):
                raise ValueError('The optional PDF download is not published. Use --build-only to test, or include_pdf_engine=true to install a complete offline app. The installed app was not replaced.')
        env = dict(os.environ, BAKER_BUILD_DIRECTORY=str(root / 'native'), BAKER_BUILD_SYSTEM='native', BAKER_BUILD_CONFIGURATION='release',
                   BAKER_RUNTIME_DIRECTORY=config['formula_runtime'], BAKER_FORMULA_MODELS_DIRECTORY=str(document))
        env.pop('BAKER_DOCUMENT_ENGINE_DIRECTORY', None)
        if separate: env['BAKER_PDF_ENGINE_MANIFEST'] = str(distribution / 'pdf-engine.json')
        else: env['BAKER_DOCUMENT_ENGINE_DIRECTORY'] = str(document)
        if config.get('signing_identity'): env['BAKER_SIGN_IDENTITY'] = config['signing_identity']
        run([ROOT / 'tools/prepare_app.sh'], cwd=ROOT, env=env)
        app = root / 'native/Baker.app'
        run(['codesign', '--verify', '--deep', '--strict', app])
        with (app/'Contents/Info.plist').open('rb') as stream:
            packaged_version = plistlib.load(stream).get('CFBundleShortVersionString')
        if packaged_version != (ROOT/'VERSION').read_text().strip(): raise ValueError('Packaged app version does not match VERSION.')
        engine = app / 'Contents/Resources/DocumentEngine'
        if separate:
            archive = next(distribution.glob('*.tar.gz'))
            run([app / 'Contents/Resources/Runtime/python/bin/python3.12', '-I', '-B', app / 'Contents/Resources/pdf_engine_install.py',
                 '--archive', archive, '--descriptor', distribution / 'pdf-engine.json', '--stage', job / 'installed-pdf'])
            engine = job / 'installed-pdf/PDFEngine'
        run([engine / 'python/bin/python3.12', '-I', '-B', app / 'Contents/Resources/document_worker.py',
             '--source', config['smoke_pdf'], '--output', job / 'pdf-check', '--config', engine / 'document-engine.json'])
        for index, case in enumerate(config.get('table_checks', [])):
            table_output=job / ('table-check-' + str(index+1))
            run([engine / 'python/bin/python3.12', '-I', '-B', app / 'Contents/Resources/document_worker.py',
                 '--source', case['pdf'], '--output', table_output, '--config', engine / 'document-engine.json'])
            check_table_reference(table_output / 'document.jsonl', Path(case['reference']))
        run(['codesign', '--verify', '--deep', '--strict', app])  # Inference must not mutate the signed bundle.
        if config.get('smoke_markdown_reference'):
            if (job / 'pdf-check/document.md').read_bytes() != Path(config['smoke_markdown_reference']).read_bytes():
                raise ValueError('PDF output differs from the accepted example. Existing app was not replaced; inspect ' + str(job))
        report = {'version':(ROOT/'VERSION').read_text().strip(), 'app':str(app), 'git_head':subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip(),
                  'binary_sha256':hashlib.file_digest((app / 'Contents/MacOS/Baker').open('rb'),'sha256').hexdigest(),
                  'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT/'Sources').rglob('*')) if p.is_file()},
                  'document_engine':str(engine), 'pdf_distribution':str(distribution) if separate else None, 'smoke_test':'passed', 'installed':False}
        (job / 'build-report.json').write_text(json.dumps(report, indent=2))
        if not build_only:
            install = Path(config['install_path']).expanduser()
            backup = replace_app(app, install, job)
            report.update(installed=True, install_path=str(install), backup=str(backup))
            (job / 'build-report.json').write_text(json.dumps(report, indent=2))
            run(['open', install])
        print('\nBaker is ready. Build report:', job / 'build-report.json', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=BUILDER / 'builder.local.json')
    parser.add_argument('--check', action='store_true', help='Check preparation without building or replacing the app')
    parser.add_argument('--build-only', action='store_true', help='Build and check without replacing or opening the app')
    args = parser.parse_args()
    try:
        config = settings(args.config); preflight(config)
        if args.check: print('Builder preparation checks passed.')
        else: build(config, args.build_only)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print('\nBuild stopped safely:', error, file=sys.stderr); sys.exit(1)
