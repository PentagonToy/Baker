"""Evaluate Baker's bundled Tesseract language data on authored text examples."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def main(args):
    codes={'en':'eng','de':'deu','ko':'kor','sv':'swe','da':'dan','fi':'fin'}
    if args.output.exists():raise ValueError('Predictions already exist')
    with args.output.open('w') as stream:
        for row in map(json.loads,args.manifest.read_text().splitlines()):
            if row['kind']!='text':continue
            started=time.monotonic()
            result=subprocess.run([str(args.executable),row['image'],'stdout','--tessdata-dir',str(args.tessdata),'-l',codes[row['language']],'--oem','1','--psm','3'],capture_output=True,text=True,timeout=60,env={**os.environ,'OMP_THREAD_LIMIT':'2','OMP_NUM_THREADS':'2'})
            stream.write(json.dumps({'id':row['id'],'prediction':result.stdout.strip(),'seconds':time.monotonic()-started,'error':result.stderr if result.returncode else None},ensure_ascii=False)+'\n');stream.flush()


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--executable',type=Path,required=True);p.add_argument('--tessdata',type=Path,required=True);main(p.parse_args())
