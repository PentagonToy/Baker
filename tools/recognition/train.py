"""Run local adapter training with bounded allocator cache and no network tracking."""
import os
import sys
import argparse
import hashlib
from importlib import metadata
import json
from pathlib import Path
import platform
import subprocess


if __name__=='__main__':
    parser=argparse.ArgumentParser(add_help=False);parser.add_argument('--record',type=Path)
    wrapper,remaining=parser.parse_known_args()
    os.environ.update(HF_HUB_OFFLINE='1',HF_HUB_DISABLE_TELEMETRY='1',WANDB_MODE='disabled',DO_NOT_TRACK='1')
    if wrapper.record:
        wrapper.record.parent.mkdir(parents=True,exist_ok=True)
        commit=subprocess.run(['git','rev-parse','HEAD'],capture_output=True,text=True)
        record={'interpreter':sys.executable,'python':sys.version,'architecture':platform.machine(),
                'arguments':remaining,'source_commit':commit.stdout.strip() if commit.returncode==0 else None,
                'packages':{name:metadata.version(name) for name in ['mlx','mlx-vlm','transformers','torch']},
                'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in Path(__file__).parent.glob('*.py')}}
        with wrapper.record.open('x') as stream:json.dump(record,stream,indent=2)
    import mlx.core as mx
    mx.set_cache_limit(256*1024**2)
    from mlx_vlm.train import main
    main(remaining)
