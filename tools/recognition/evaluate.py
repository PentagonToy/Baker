"""Score exact authored targets without treating model agreement as ground truth."""
import argparse
from collections import defaultdict
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import statistics
import unicodedata


def normalise(text,kind):
    text=unicodedata.normalize('NFC',text).strip()
    if kind=='formula':
        text=re.sub(r'^\\\[|\\\]$|^\\\(|\\\)$','',text).strip()
        text=re.sub(r'^\$+|\$+$','',text)
        tokens=[];depth=0;text_depths=[];pending_text=False
        for token in re.findall(r'\\[A-Za-z]+|\\.|\s+|.',text,flags=re.S):
            textual=bool(text_depths)
            if token.isspace():
                if textual and (not tokens or tokens[-1][0]!=' '):tokens.append((' ',True))
                continue
            if not textual and token in (r'\left',r'\right',r'\,',r'\;',r'\!',r'\:', '\\ '):continue
            if not textual and token in (r'\dfrac',r'\cfrac'):token=r'\frac'
            if token in (r'\text',r'\textrm',r'\textnormal',r'\textit',r'\textbf',r'\textsf',r'\mbox',r'\operatorname'):pending_text=True
            if token=='{':
                depth+=1
                if pending_text:text_depths.append(depth);pending_text=False
            elif token=='}':
                if text_depths and text_depths[-1]==depth:text_depths.pop()
                depth-=1
            tokens.append((token,textual))
        compact=[];i=0
        while i<len(tokens):
            token,textual=tokens[i];compact.append(token)
            if not textual and token in ('_','^') and i+3<len(tokens) and tokens[i+1][0]=='{' and re.fullmatch(r'[A-Za-z0-9]',tokens[i+2][0]) and tokens[i+3][0]=='}':
                compact.append(tokens[i+2][0]);i+=4
            else:i+=1
        result='';previous=''
        for token in compact:
            if re.fullmatch(r'\\[A-Za-z]+',previous) and re.match(r'[A-Za-z]',token):result+=' '
            result+=token;previous=token
        return result
    return ' '.join(text.split())


def distance(a,b):
    row=list(range(len(b)+1))
    for i,x in enumerate(a,1):
        nxt=[i]
        for j,y in enumerate(b,1):nxt.append(min(nxt[-1]+1,row[j]+1,row[j-1]+(x!=y)))
        row=nxt
    return row[-1]


class Grid(HTMLParser):
    def __init__(self):super().__init__();self.cells={};self.row=-1;self.active=None;self.spans=[]
    def handle_starttag(self,tag,attrs):
        if tag=='tr':self.row+=1;self.col=0
        elif tag in ('td','th'):
            while (self.row,self.col) in self.cells:self.col+=1
            attrs=dict(attrs);self.active=[self.row,self.col,int(attrs.get('rowspan',1)),int(attrs.get('colspan',1)),'']
    def handle_data(self,data):
        if self.active:self.active[-1]+=data
    def handle_endtag(self,tag):
        if tag in ('td','th') and self.active:
            row,col,rs,cs,text=self.active
            self.spans.append({'row':row,'column':col,'rowspan':rs,'colspan':cs})
            for y in range(row,row+rs):
                for x in range(col,col+cs):self.cells[y,x]=normalise(text,'text')
            self.col=col+cs;self.active=None


def score(row,prediction):
    target=normalise(row['target'],row['kind']);text=normalise(prediction,row['kind'])
    result={'exact':target==text,'edits':distance(target,text),'characters':len(target)}
    if row['kind']=='table':
        expected=Grid();expected.feed(row['target']);actual=Grid();actual.feed(prediction)
        result.update(cells=len(expected.cells),correct_cells=sum(actual.cells.get(k)==v for k,v in expected.cells.items()),extra_cells=len(actual.cells.keys()-expected.cells.keys()))
        spans=lambda grid:sorted((s['row'],s['column'],s['rowspan'],s['colspan']) for s in grid.spans)
        result.update(exact_grid=expected.cells==actual.cells,exact_spans=spans(expected)==spans(actual))
        result['exact']=result['exact_grid'] and result['exact_spans']
        result['edits']=sum(distance(value,actual.cells.get(key,'')) for key,value in expected.cells.items())+sum(len(actual.cells[key]) for key in actual.cells.keys()-expected.cells.keys())
        result['characters']=sum(len(value) for value in expected.cells.values())
    return result


def evaluate(manifest,predictions,splits=None):
    source=list(map(json.loads,manifest.read_text().splitlines()))
    rows={r['id']:r for r in source};groups=defaultdict(list);details=[];seen=set()
    if len(rows)!=len(source):raise ValueError('Duplicate corpus IDs')
    for p in map(json.loads,predictions.read_text().splitlines()):
        if p['id'] in seen:raise ValueError('Duplicate prediction ID: '+p['id'])
        seen.add(p['id']);row=rows[p['id']]
        if splits and row['split'] not in splits:continue
        split='regression' if row.get('reference_type') else row['split']
        result={**p,**score(row,p.get('prediction','')), 'kind':row['kind'],'split':split,'language':row['language']};details.append(result)
        if p.get('finish_reason')=='length' or p.get('error'):result['exact']=False
        groups[(split,row['kind'],row['language'])].append(result)
    summary=[]
    for (split,kind,language),results in sorted(groups.items()):
        d=dict(split=split,kind=kind,language=language,cases=len(results),exact=sum(r['exact'] for r in results),character_error_rate=sum(r['edits'] for r in results)/max(1,sum(r['characters'] for r in results)),median_seconds=statistics.median(r['seconds'] for r in results))
        if kind=='table':d.update(correct_cells=sum(r['correct_cells'] for r in results),cells=sum(r['cells'] for r in results),extra_cells=sum(r['extra_cells'] for r in results))
        summary.append(d)
    expected={r['id'] for r in source if not splits or r['split'] in splits};scored={r['id'] for r in details}
    return {'predictions':str(predictions),'coverage':{'expected':len(expected),'scored':len(scored),'missing_ids':sorted(expected-scored)},'groups':summary,'examples':details}


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manifest',type=Path,required=True);p.add_argument('--predictions',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--split',nargs='+');args=p.parse_args()
    report=evaluate(args.manifest,args.predictions,args.split);args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps({'coverage':report['coverage'],'groups':report['groups']},ensure_ascii=False,indent=2))
