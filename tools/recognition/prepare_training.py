"""Keep only independently checked expert outputs; never train on evaluation rows."""
import argparse
import hashlib
import json
from pathlib import Path

from evaluate import score


def main(args):
    rows=list(map(json.loads,args.manifest.read_text().splitlines()))
    teachers={p.stem:{r['id']:r for r in map(json.loads,p.read_text().splitlines())} for p in args.teachers}
    args.output.mkdir(parents=True,exist_ok=False);audit=[]
    for split in ['train','validation']:
        selected=[]
        for row in rows:
            if row['split']!=split or row.get('reference_type'):continue
            candidates=[]
            for name,predictions in teachers.items():
                if row['id'] not in predictions:continue
                prediction=predictions[row['id']]
                if prediction.get('error'):continue
                metric=score(row,prediction['prediction'])
                if metric['exact']:candidates.append((prediction['seconds'],name,prediction['prediction']))
            if split=='train' and not candidates:
                audit.append({'id':row['id'],'accepted':False,'reason':'No expert output matches authored ground truth'});continue
            if candidates:
                _,teacher,target=min(candidates)
                if row['kind']=='formula':
                    # Matching is a gate. Train on the valid authored spelling,
                    # never on the comparator's formatting representation.
                    target='$$\n'+row['target'].strip()+'\n$$'
            else:
                teacher='authored validation target';target=row['target']
                if row['kind']=='formula':target='$$\n'+target+'\n$$'
            prompt={'text':'Text Recognition:','formula':'Formula Recognition:','table':'Table Recognition:'}[row['kind']]
            selected.append({'id':row['id'],'images':[row['image']],'messages':[{'role':'user','content':prompt},{'role':'assistant','content':target}]})
            audit.append({'id':row['id'],'split':split,'kind':row['kind'],'accepted':True,'teacher':teacher,'image_sha256':hashlib.sha256(Path(row['image']).read_bytes()).hexdigest()})
        (args.output/(split+'.jsonl')).write_text(''.join(json.dumps(x,ensure_ascii=False)+'\n' for x in selected))
        print(split,len(selected))
    (args.output/'audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manifest',type=Path,required=True);p.add_argument('--teachers',type=Path,nargs='+',required=True);p.add_argument('--output',type=Path,required=True);main(p.parse_args())
