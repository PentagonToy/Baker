"""Experimental local PDF hybrid; keeps Baker's existing document exporters."""
import argparse
import gc
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import subprocess
import tempfile
import time
import unicodedata

sys.path.insert(0,str(Path(__file__).resolve().parent))


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


def reliable_native(chars):
    if not chars:return False
    text=''.join(c['text'] for c in chars)
    if not text.strip():return False
    if any(c in text for c in ('ð','Þ','¼','þ','\ufffd')):return False
    if any(unicodedata.category(c) in ('Co','Cc','Cn') and c not in '\n\t' for c in text):return False
    if any(any(marker in c['font'].lower() for marker in ('symbol','math','advps','cmsy','cmmi','cmex')) for c in chars):return False
    if any(unicodedata.category(c)=='Sm' and c not in '=+-' for c in text):return False
    return True


def without_redundant_figure_containers(layout):
    result=[]
    def area(b):return max(0,b[2]-b[0])*max(0,b[3]-b[1])
    def intersection(a,b):return max(0,min(a[2],b[2])-max(a[0],b[0]))*max(0,min(a[3],b[3])-max(a[1],b[1]))
    for parent in layout:
        if parent['class']!='figure':result.append(parent);continue
        a=parent['box'];children=[child for child in layout if child is not parent and child['class']=='figure' and child['score']>.5 and area(child['box'])<area(a)*.8 and intersection(a,child['box'])/max(1,area(child['box']))>.95]
        separate=all(intersection(c['box'],d['box'])/max(1,min(area(c['box']),area(d['box'])))<.1 for i,c in enumerate(children) for d in children[:i])
        if not (len(children)>=2 and separate and sum(area(c['box']) for c in children)>area(a)*.8):result.append(parent)
    return result


def restore_native_scripts(value,candidates):
    parts=re.split(r'(\$[^$]*\$)',value)
    for i,part in enumerate(parts):
        if part.startswith('$'):continue
        for plain,rich in sorted(candidates.items(),key=lambda item:len(item[0]),reverse=True):
            part=re.sub(r'(?<!\w)'+re.escape(plain)+r'(?!\w)',lambda match:rich,part)
        parts[i]=part
    return ''.join(parts)


def publication_notice(text):
    return bool(re.search(r'\bAll rights reserved\b|^\s*Copyright\b|©\s*\d{4}',text,re.I))


def vision_notice(crop,audit_directory=None):
    """Read publication boilerplate as text instead of generating math commands."""
    from PIL import ImageOps
    with tempfile.TemporaryDirectory(prefix='baker-notice-') as folder:
        root=Path(folder);image=root/'image.png'
        ImageOps.expand(crop,border=24,fill=crop.getpixel((0,0))).save(image)
        manifest=root/'input.jsonl';output=root/'output.jsonl'
        manifest.write_text(json.dumps({'id':'notice','kind':'text','language':'en','image':str(image)})+'\n')
        subprocess.run(['/usr/bin/osascript','-l','JavaScript',str(Path(__file__).with_name('vision.js')),str(manifest),str(output)],check=True,capture_output=True,text=True,timeout=30)
        row=json.loads(output.read_text())
        if row.get('error') or not row.get('prediction','').strip():
            if audit_directory:crop.save(audit_directory/'notice-failure.png')
            raise ValueError('Native notice OCR failed: '+str(row.get('error') or 'Empty result'))
        return row['prediction'].strip()


def sparse_native_rows(chars,box,image,reconstruction,recognise,words,compounds):
    """Repair sparse bibliography damage; inline mathematical prose stays visual."""
    from pdf_text import join_lines
    groups={}
    for char in chars:groups.setdefault(char['row'],[]).append(char)
    rows=sorted(groups.values(),key=lambda row:min(c['box'][1] for c in row))
    bad=[row for row in rows if not reliable_native(row)]
    if len(rows)<10 or not bad or len(bad)/len(rows)>.1:return None
    if sum(bool(re.match(r'^\s*\[\d+\]\s',reconstruction.native_text(row,box))) for row in rows)<3:return None
    if any(any(marker in char['font'].lower() for marker in ('symbol','math','advps','cmsy','cmmi','cmex')) for char in chars):return None
    lines=[]
    for row in rows:
        if reliable_native(row):lines.append(reconstruction.native_text(row,box));continue
        b=[min(c['box'][0] for c in row),min(c['box'][1] for c in row),max(c['box'][2] for c in row),max(c['box'][3] for c in row)]
        crop=image.crop([max(0,int(b[0])-6),max(0,int(b[1])-6),min(image.width,int(b[2])+6),min(image.height,int(b[3])+6)])
        result=recognise(crop,'Text Recognition:',512)
        if result.finish_reason=='length':raise ValueError('Damaged-line OCR was truncated')
        if not result.text.strip():raise ValueError('Damaged-line OCR was empty')
        lines.append(result.text.strip())
    return join_lines(lines,words,compounds),len(bad)


def recover_author_band(document,raw,reconstruction):
    """Use native block membership to remove duplicated, overlapping author detections."""
    if document['page']!=1:return
    nodes=document['nodes']
    abstract=next((n for n in nodes if n['kind']=='heading' and re.sub(r'\s|:','',n.get('text','')).lower()=='abstract'),None)
    if not abstract:return
    title=next((n for n in nodes if n['kind']=='heading' and len(n.get('text',''))>25 and n['box'][3]<abstract['box'][1]),None)
    if not title:return
    top,bottom=title['box'][3],abstract['box'][1];parts=[]
    for index,block in enumerate(raw['native']['blocks']):
        if any(abs(line.get('dir',(1,0))[1])>.1 for line in block.get('lines',[])):continue
        local=reconstruction.native_characters({**raw,'native':{'blocks':[block]}})
        visible=[c for c in local if c['text'].strip()]
        if not visible:continue
        if not all(top<(c['box'][1]+c['box'][3])/2<bottom for c in visible):continue
        if not reliable_native(visible):return
        box=[min(c['box'][0] for c in visible),min(c['box'][1] for c in visible),max(c['box'][2] for c in visible),max(c['box'][3] for c in visible)]
        text=reconstruction.native_text(local,box)
        if text:parts.append({'text':text,'box':box,'source_block':index})
    if sum(len(p['text']) for p in parts)<20:return
    groups=[]
    for part in sorted(parts,key=lambda p:p['box'][0]):
        a=part['box'];matches=[]
        for group in groups:
            b=group['box'];overlap=max(0,min(a[2],b[2])-max(a[0],b[0]))/max(1,min(a[2]-a[0],b[2]-b[0]))
            if overlap>.8:matches.append(group)
        group=matches[0] if matches else {'parts':[],'box':a.copy()}
        if not matches:groups.append(group)
        group['parts'].append(part);b=group['box'];group['box']=[min(a[0],b[0]),min(a[1],b[1]),max(a[2],b[2]),max(a[3],b[3])]
    def inside(node):
        return node is not title and node['kind'] in ('heading','text') and top<(node['box'][1]+node['box'][3])/2<bottom
    retained=[n for n in nodes if not inside(n)];position=retained.index(title)+1;fresh=[]
    next_id=max((n['id'] for n in nodes if isinstance(n['id'],int)),default=0)+1
    for i,group in enumerate(sorted(groups,key=lambda g:g['box'][0])):
        pieces=sorted(group['parts'],key=lambda p:(p['box'][1],p['box'][0]))
        fresh.append({'id':next_id+i,'kind':'text','text':' '.join(p['text'] for p in pieces),'box':group['box'],
                      'score':None,'score_method':'native-author-blocks','calibrated':False,'raw_class':'plain text','source_blocks':[p['source_block'] for p in pieces]})
    document['nodes']=retained[:position]+fresh+retained[position:]


def write_progress(output, page, total, phase):
    pending = output / 'progress.pending'
    pending.write_text(json.dumps({'page': page, 'total': total, 'phase': phase}))
    pending.replace(output / 'progress.json')


def main(args):
    os.environ.update(HF_HUB_OFFLINE='1',HF_HUB_DISABLE_TELEMETRY='1',WANDB_MODE='disabled',DO_NOT_TRACK='1')
    import pymupdf
    from PIL import Image
    from layout import Layout
    from evaluate import Grid
    from pdf_text import vocabulary,native_prose,finish_flow,front_matter,attach_equation_labels,deduplicate_text
    if args.output.exists():raise ValueError('Candidate output already exists')
    args.output.mkdir(parents=True);(args.output/'assets').mkdir()
    reconstruction=module('baker_reconstruction',args.reconstruction)
    started=time.monotonic();layout=Layout(args.layout);model_load_seconds=0;mx=None
    if args.code:
        engine=None
        def recognise(crop,task,limit):
            nonlocal engine,model_load_seconds,mx
            if engine is None:
                import mlx.core as mx
                mx.set_cache_limit(256*1024**2)
                from minimal import Engine
                begin=time.monotonic();engine=Engine(args.model,args.code,args.adapter);model_load_seconds=time.monotonic()-begin
            return engine.recognise(crop,task,limit)
    else:
        model=processor=None
        def recognise(crop,task,limit):
            nonlocal model,processor,model_load_seconds,mx
            if mx is None:
                import mlx.core as mx
                mx.set_cache_limit(256*1024**2)
            from mlx_vlm import load,generate
            from mlx_vlm.prompt_utils import apply_chat_template
            if model is None:
                begin=time.monotonic();model,processor=load(str(args.model),adapter_path=str(args.adapter) if args.adapter else None);model_load_seconds=time.monotonic()-begin
            prompt=apply_chat_template(processor,model.config,task,num_images=1)
            return generate(model,processor,prompt,image=crop,max_tokens=limit,temperature=0.0,verbose=False)
    preparation=time.monotonic()-started;timings=[];diagnostics=[]
    with pymupdf.open(args.source) as document,(args.output/'document.md').open('w') as md,(args.output/'document.tex').open('w') as tex,(args.output/'document.jsonl').open('w') as records:
        if document.is_encrypted:raise ValueError('Encrypted PDF')
        if len(document) > 2000: raise ValueError('Convert at most 2000 pages at a time')
        write_progress(args.output, 0, len(document), 'preparing')
        words,compounds=vocabulary(document)
        tex.write('\\documentclass{article}\n\\usepackage[a4paper,margin=25mm]{geometry}\n\\usepackage{fontspec,amsmath,amssymb,mathtools,graphicx,longtable,booktabs,multirow}\n\\begin{document}\n')
        for index,page in enumerate(document):
            write_progress(args.output, index + 1, len(document), 'recognising')
            if page.rect.width * page.rect.height * (300 / 72)**2 > 24_000_000:
                raise ValueError('Page raster exceeds 24 megapixels')
            begin=time.monotonic();pix=page.get_pixmap(dpi=300,alpha=False);image=Image.frombytes('RGB',[pix.width,pix.height],pix.samples);del pix
            native=page.get_text('rawdict',flags=pymupdf.TEXTFLAGS_RAWDICT & ~pymupdf.TEXT_PRESERVE_IMAGES)
            raw={'page':index+1,'size':list(page.rect),'raster_size':list(image.size),'native':native,'layout':without_redundant_figure_containers(layout.predict(image)),'elements':[]}
            chars=reconstruction.native_characters(raw);table_outputs={};native_blocks=0;recognised_blocks=0;native_notices=0;sparse_lines=0;footnotes=set()
            for detection in raw['layout']:
                kind=detection['class'];box=detection['box'];meta={};text=''
                if kind=='abandon':
                    contact=reconstruction.native_text(chars,box)
                    if not re.search(r'Corresponding author|E-?mail address',contact,re.I):continue
                    kind='plain text'
                if kind=='figure':etype='FIGURE'
                else:
                    selected=[c for c in chars if box[0]<=(c['box'][0]+c['box'][2])/2<=box[2] and box[1]<=(c['box'][1]+c['box'][3])/2<=box[3]]
                    use_native=kind not in ('table','isolate_formula') and reliable_native(selected)
                    if use_native:text=native_prose(chars,box,reconstruction,words,compounds);native_blocks+=1
                    else:
                        task='table' if kind=='table' else 'formula' if kind=='isolate_formula' else 'text'
                        crop=image.crop([max(0,int(box[0])-4),max(0,int(box[1])-4),min(image.width,int(box[2])+4),min(image.height,int(box[3])+4)])
                        if task=='text' and publication_notice(reconstruction.native_text(selected,box)):
                            text=vision_notice(crop,args.output);native_notices+=1;meta['ocr_engine']='macos-vision-publication-notice'
                        else:
                            repaired=sparse_native_rows(selected,box,image,reconstruction,recognise,words,compounds) if task=='text' else None
                            if repaired:
                                text,count=repaired;sparse_lines+=count;meta['ocr_engine']='native-plus-damaged-lines';meta['recognised_lines']=count
                            else:
                                result=recognise(crop,{'table':'Table Recognition:','formula':'Formula Recognition:','text':'Text Recognition:'}[task],4096 if task in ('table','text') else 1024)
                                if result.finish_reason=='length':raise ValueError('Candidate output was truncated')
                                text=result.text.strip()
                        if task=='formula':text=re.sub(r'^\$\$|\$\$$|^\\\[|\\\]$','',text).strip()
                        recognised_blocks+=1
                    etype={'title':'TITLE','isolate_formula':'FORMULA','table':'TABLE'}.get(kind,'TEXT')
                    if kind=='table':table_outputs[len(raw['elements'])]=text
                    if etype=='TEXT' and (publication_notice(text) or re.search(r'Corresponding author|E-?mail address',text,re.I)):
                        footnotes.add(len(raw['elements']))
                raw['elements'].append({'box':box,'type':etype,'text':text,'meta':meta,'score':detection['score']})
            result=reconstruction.reconstruct(raw)
            for node in result['nodes']:
                if node['kind']=='equation':node.update(score=None,score_method='baker-glm-prototype-no-calibrated-confidence')
                if node['kind']=='table':
                    parser=Grid();parser.feed(table_outputs.get(node['id'],''))
                    if not parser.cells:raise ValueError('Candidate table is not a parsed HTML grid')
                    groups={};box=node['box'];scripts={}
                    for char in chars:
                        if box[0]<(char['box'][0]+char['box'][2])/2<box[2] and box[1]<(char['box'][1]+char['box'][3])/2<box[3]:groups.setdefault(char['row'],[]).append(char)
                    for group in groups.values():
                        rich=reconstruction.native_text(group,box)
                        plain=re.sub(r'\$\s*[_^]\{([^{}]+)\}\s*\$',r'\1',rich)
                        if plain!=rich and re.fullmatch(r'[A-Za-z0-9]+',plain):scripts[plain]=rich
                    parser.cells={key:restore_native_scripts(value,scripts) for key,value in parser.cells.items()}
                    rows=max(y for y,x in parser.cells)+1;cols=max(x for y,x in parser.cells)+1
                    node.update(rows=[[parser.cells.get((y,x),'') for x in range(cols)] for y in range(rows)],spans=parser.spans,header_rows=1)
                    node['markdown']=[reconstruction.html_table(node)]
                if node['kind']=='figure':
                    b=node['box'];image.crop([max(0,b[0]-32),max(0,b[1]-8),min(image.width,b[2]+32),min(image.height,b[3]+8)]).save(args.output/'assets'/node['asset'])
            finish_flow(result,footnotes,words,compounds)
            recover_author_band(result,raw,reconstruction)
            attach_equation_labels(result)
            front_matter(result)
            deduplicate_text(result)
            records.write(json.dumps(result,ensure_ascii=False)+'\n');md.write(reconstruction.markdown(result)+'\n');tex.write(reconstruction.latex(result)+'\n')
            characters = sum(len(n.get('text', '')) for n in result['nodes'])
            if characters > 250000: raise ValueError('Page output exceeds 250,000 characters')
            diagnostics.append({'page': index + 1, 'block_count': len(result['nodes']), 'character_count': characters, **result['diagnostics']})
            write_progress(args.output, index + 1, len(document), 'completed')
            if sum(p.stat().st_size for p in args.output.rglob('*') if p.is_file()) > 512 * 1024**2:
                raise ValueError('Document output exceeds 512 MB')
            timings.append({'page':index+1,'seconds':time.monotonic()-begin,'native_blocks':native_blocks,'recognised_blocks':recognised_blocks,'native_notices':native_notices,'sparse_lines':sparse_lines,'nodes':len(result['nodes'])})
            print(f"Page {index+1}/{len(document)} completed ({timings[-1]['seconds']:.1f} s)",flush=True);del raw,result,image;gc.collect()
            if mx is not None:mx.clear_cache()
        write_progress(args.output, len(document), len(document), 'finalising')
        tex.write('\\end{document}\n')
    (args.output/'report.json').write_text(json.dumps({'seconds':time.monotonic()-started,'preparation_seconds':preparation,'model_load_seconds':model_load_seconds,'pages':diagnostics,'timings':timings,'engine':'baker-small-ocr-1','warnings':['Recognition remains approximate; review mathematical symbols against the original.']},indent=2))


if __name__=='__main__':
    p=argparse.ArgumentParser()
    for name in ['source','output','layout','model','reconstruction']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--adapter',type=Path);p.add_argument('--code',type=Path,help='Use the extracted inference runtime');main(p.parse_args())
