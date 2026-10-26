"""Use Paddle's installed OTSL decoder, retaining the original recogniser output."""
import argparse
import json
import os
from pathlib import Path


def main(args):
    os.environ['PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK']='True'
    from paddlex.inference.pipelines.paddleocr_vl.uilts import convert_otsl_to_html
    rows={r['id']:r for r in map(json.loads,args.manifest.read_text().splitlines())}
    if args.output.exists():raise ValueError('Normalised output already exists')
    with args.output.open('w') as stream:
        for row in map(json.loads,args.source.read_text().splitlines()):
            row['raw_prediction']=row['prediction']
            if rows[row['id']]['kind']=='table':row['prediction']=convert_otsl_to_html(row['prediction'])
            stream.write(json.dumps(row,ensure_ascii=False)+'\n')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True);main(p.parse_args())
