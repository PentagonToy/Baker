"""Prepare a separate, relocatable candidate runtime; never replace the app."""
import argparse
import hashlib
from importlib import metadata
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys


def copy_file(source,target):
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,target)


def main(args):
    if sys.version_info[:2]!=(3,12) or platform.machine()!='arm64':
        raise ValueError('Use the tested arm64 Python 3.12 inference environment')
    if not (args.standalone/'BUILD').is_file():
        raise ValueError('A relocatable standalone CPython base is required')
    distributions=list(metadata.distributions())
    packages={d.metadata['Name']:d.version for d in distributions}
    if any(name.lower().replace('_','-') in {'torch','transformers','mlx-vlm'} for name in packages):
        raise ValueError('Package from the minimal inference environment, not the training environment')
    if args.destination.exists():raise ValueError('Use a fresh output; existing candidates are preserved')
    staging=args.destination.with_name(args.destination.name+'.preparing-'+str(os.getpid()))
    staging.mkdir(parents=True)
    shutil.copytree(args.standalone,staging/'python',symlinks=True,
                    ignore=shutil.ignore_patterns('site-packages','__pycache__','*.pyc','include','man'))
    site=staging/'python/lib/python3.12/site-packages';site.mkdir(parents=True)
    for dist in distributions:
        for relative in dist.files or []:
            if '..' in relative.parts or '__pycache__' in relative.parts or relative.suffix=='.pyc' or relative.name=='direct_url.json':continue
            source=Path(dist.locate_file(relative))
            if source.is_file():copy_file(source,site/relative)
    shutil.copytree(args.model,staging/'model',ignore=shutil.ignore_patterns('.cache'))
    for name in ['adapters.safetensors','adapter_config.json']:
        copy_file(args.adapter/name,staging/'adapter'/name)
    shutil.copytree(args.code,staging/'code',ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
    copy_file(args.layout,staging/'layout.onnx')
    for name in ['pdf_candidate.py','minimal.py','layout.py','pdf_text.py','evaluate.py','vision.js','preview.py']:
        copy_file(Path(__file__).parent/name,staging/'worker'/name)
    copy_file(args.reconstruction,staging/'worker/document_reconstruction.py')
    copy_file(args.provenance,staging/'PROVENANCE.json')
    launcher=staging/'Preview.command'
    launcher.write_text('#!/bin/zsh\nset -eu\nbaker_preview_root="${0:A:h}"\nexec "$baker_preview_root/python/bin/python3.12" -I -B "$baker_preview_root/worker/preview.py"\n')
    launcher.chmod(0o755)
    environment={'PATH':'/usr/bin:/bin','HOME':'/var/empty','HF_HUB_OFFLINE':'1','DO_NOT_TRACK':'1'}
    subprocess.run([str(staging/'python/bin/python3.12'),'-I','-B','-c',
                    'import importlib.util; import mlx.core,numpy,PIL,tokenizers,onnxruntime,cv2,pymupdf; assert all(importlib.util.find_spec(x) is None for x in ["torch","transformers","mlx_vlm"]); print("Isolated candidate imports passed")'],check=True,env=environment)
    inventory={}
    for path in staging.rglob('*'):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:sha=hashlib.file_digest(stream,'sha256').hexdigest()
            inventory[str(path.relative_to(staging))]={'bytes':path.stat().st_size,'sha256':sha}
    (staging/'manifest.json').write_text(json.dumps({'experimental':True,'python':sys.version,'architecture':platform.machine(),
        'packages':packages,'payload_bytes':sum(v['bytes'] for v in inventory.values()),'files':inventory},indent=2))
    staging.rename(args.destination)
    print(json.dumps({'destination':str(args.destination),'payload_bytes':sum(v['bytes'] for v in inventory.values()),'files':len(inventory)},indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['destination','standalone','model','adapter','layout','code','reconstruction','provenance']:
        parser.add_argument('--'+name,type=Path,required=True)
    main(parser.parse_args())
