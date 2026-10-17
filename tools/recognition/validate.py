"""Run PDF regression fixtures sequentially against a separate candidate bundle."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def main(args):
    args.output.mkdir(parents=True,exist_ok=False);summary=[]
    for case in json.loads(args.cases.read_text()):
        name=case['name']
        if not re.fullmatch(r'[a-z0-9-]+',name):raise ValueError('Use a simple fixture name')
        output=args.output/name;memory=args.output/(name+'-memory.json');log=args.output/(name+'.log')
        subprocess.run([sys.executable,str(Path(__file__).with_name('measure.py')),'--output',str(memory),'--log',str(log),
            str(args.engine/'python/bin/python3.12'),'-I','-B',str(args.engine/'worker/preview.py'),
            '--source',case['source'],'--output',str(output)],check=True)
        pages=list(map(json.loads,(output/'document.jsonl').read_text().splitlines()));nodes=[n for p in pages for n in p['nodes']]
        if len(pages)!=case['pages']:raise ValueError(name+': page coverage changed')
        equations=[n for n in nodes if n['kind']=='equation']
        if 'labels' in case and [n.get('label') for n in equations]!=case['labels']:raise ValueError(name+': equation labels changed')
        author_blocks=[n['text'] for n in pages[0]['nodes'] if n.get('score_method')=='native-author-blocks']
        authors=' '.join(author_blocks)
        for author in case.get('authors',[]):
            if authors.count(author)!=1:raise ValueError(name+': duplicated or missing author '+author)
        if case.get('authors') and [authors.index(author) for author in case['authors']]!=sorted(authors.index(author) for author in case['authors']):raise ValueError(name+': author order changed')
        usage=json.loads(memory.read_text())
        if usage['status'] or usage['surviving_children']:raise ValueError(name+': process cleanup failed')
        if args.tex_engine:
            with (output/'compile.log').open('w') as stream:
                for repeat in range(2):
                    subprocess.run([str(args.tex_engine),'-no-shell-escape','-interaction=nonstopmode','-halt-on-error','document.tex'],cwd=output,check=True,stdout=stream,stderr=stream,env={**os.environ,'openin_any':'p','openout_any':'p'})
        row={'name':name,'pages':len(pages),'seconds':usage['seconds'],'peak_tree_footprint':usage['peak_tree_footprint'],
             'equations':len(equations),'figures':sum(n['kind']=='figure' for n in nodes),
             'tables':sum(n['kind']=='table' for n in nodes),'latex_compiled':bool(args.tex_engine)}
        summary.append(row);(args.output/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(row),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['engine','cases','output']:parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--tex-engine',type=Path);main(parser.parse_args())
