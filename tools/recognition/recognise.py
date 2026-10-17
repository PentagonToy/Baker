"""Run one local MLX candidate, retaining raw predictions and per-example timing."""
import argparse
import gc
import json
import os
from pathlib import Path
import time


def main(args):
    os.environ.update(HF_HUB_OFFLINE='1',HF_HUB_DISABLE_TELEMETRY='1',DO_NOT_TRACK='1',WANDB_MODE='disabled')
    import mlx.core as mx
    from mlx_vlm import load, generate
    from mlx_vlm.prompt_utils import apply_chat_template
    mx.random.seed(17)
    started=time.monotonic(); model,processor=load(str(args.model),adapter_path=str(args.adapter) if args.adapter else None)
    preparation=time.monotonic()-started
    rows=[json.loads(line) for line in args.manifest.read_text().splitlines()]
    if args.split:rows=[row for row in rows if row['split'] in args.split]
    if args.limit:rows=rows[:args.limit]
    args.output.parent.mkdir(parents=True,exist_ok=True)
    if args.output.exists():raise ValueError('Refusing to overwrite existing predictions')
    with args.output.open('w') as stream:
        for i,row in enumerate(rows):
            task={'text':'OCR:' if args.family=='paddle' else 'Text Recognition:','formula':'Formula Recognition:','table':'Table Recognition:'}[row['kind']]
            prompt=apply_chat_template(processor,model.config,task,num_images=1)
            start=time.monotonic()
            result=generate(model,processor,prompt,image=row['image'],max_tokens=1600 if row['kind']=='table' else 512,temperature=0.0,verbose=False)
            record=dict(id=row['id'],prediction=result.text,seconds=time.monotonic()-start,preparation_seconds=preparation,peak_memory_gb=mx.get_peak_memory()/1e9,model=str(args.model),adapter=str(args.adapter) if args.adapter else None)
            stream.write(json.dumps(record,ensure_ascii=False)+'\n');stream.flush()
            print(i+1,row['id'],round(record['seconds'],2),flush=True)
            gc.collect();mx.clear_cache()


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--model',type=Path,required=True);p.add_argument('--manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--family',choices=['glm','paddle'],default='glm');p.add_argument('--split',nargs='+');p.add_argument('--adapter',type=Path);p.add_argument('--limit',type=int)
    main(p.parse_args())
