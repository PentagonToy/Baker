"""Run the existing formula worker without changing its model or decode policy."""
import argparse
import importlib.util
import json
from pathlib import Path
import time


def main(args):
    spec=importlib.util.spec_from_file_location('baker_formula_worker',args.worker)
    worker=importlib.util.module_from_spec(spec);spec.loader.exec_module(worker)
    settings=worker.read_settings(args.config)
    if args.output.exists():raise ValueError('Predictions already exist')
    with args.output.open('w') as stream:
        for row in map(json.loads,args.manifest.read_text().splitlines()):
            if row['kind']!='formula':continue
            started=time.monotonic()
            try:result=worker.recognise(row['image'],settings);record={'prediction':result['latex'],'confidence':result.get('confidence')}
            except Exception as error:record={'prediction':'','error':repr(error)}
            record.update(id=row['id'],seconds=time.monotonic()-started)
            stream.write(json.dumps(record,ensure_ascii=False)+'\n');stream.flush();print(row['id'],round(record['seconds'],2),flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--worker',type=Path,required=True);p.add_argument('--config',type=Path,required=True);main(p.parse_args())
