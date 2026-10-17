"""Baker document reconstruction. Geometry is raster-local, with origin at top left.

No model imports: detection/recognition and reconstruction remain independently testable.
"""
import html
import difflib
import re
import unicodedata


def overlap(a, b):
    area = max(0, min(a[2], b[2]) - max(a[0], b[0])) * max(0, min(a[3], b[3]) - max(a[1], b[1]))
    return area / max(1, min((a[2]-a[0])*(a[3]-a[1]), (b[2]-b[0])*(b[3]-b[1])))


def quad_box(points):
    return [min(p[0] for p in points), min(p[1] for p in points), max(p[0] for p in points), max(p[1] for p in points)]


def native_characters(page):
    width, height = page['raster_size']
    size = page['size']
    sx, sy = width / (size[2]-size[0]), height / (size[3]-size[1])
    result = []
    for block in page['native']['blocks']:
        for line in block.get('lines', []):
            row = len(result)
            for span in line['spans']:
                for char in span['chars']:
                    b = char['bbox']
                    # This publisher font maps its visible correspondence asterisk to an arrow.
                    text='*' if span['font'].endswith('CORRESAST') and char['c']=='⇑' else char['c']
                    result.append({'text':text, 'box':[b[0]*sx,b[1]*sy,b[2]*sx,b[3]*sy],
                                   'font':span['font'], 'flags':span['flags'], 'size':span['size']*sy, 'baseline':char['origin'][1]*sy, 'row':row})
    return result


def native_text(chars, box, forbidden=(), repairs=()):
    selected = []
    for c in chars:
        b = c['box']; x, y = (b[0]+b[2])/2, (b[1]+b[3])/2
        if box[0] <= x <= box[2] and box[1] <= y <= box[3] and not any(f[0] <= x <= f[2] and f[1] <= y <= f[3] for f in forbidden):
            selected.append(c)
    for repair in repairs:
        b=repair['box']; x,y=(b[0]+b[2])/2,(b[1]+b[3])/2
        if not (box[0]<=x<=box[2] and box[1]<=y<=box[3]):continue
        replaced=[c for c in selected if b[0]<=(c['box'][0]+c['box'][2])/2<=b[2] and b[1]<=(c['box'][1]+c['box'][3])/2<=b[3]]
        if not replaced:continue
        anchor=replaced[0]
        selected=[c for c in selected if c not in replaced]
        selected.append({**anchor,'text':'$'+repair['latex']+'$','box':b})
    rows = {}
    for c in selected: rows.setdefault(c['row'], []).append(c)
    lines = []
    for row in sorted(rows.values(), key=lambda r: min(c['box'][1] for c in r)):
        row.sort(key=lambda c:c['box'][0])
        sizes = {}
        for c in row:
            if not c['text'].isspace(): sizes[round(c['size'],1)] = sizes.get(round(c['size'],1),0)+1
        main_size = max(sizes, key=sizes.get) if sizes else 0
        baseline = sorted(c['baseline'] for c in row if c['size'] >= main_size*.95)[len([c for c in row if c['size'] >= main_size*.95])//2] if main_size else 0
        text = ''; script = ''; mode = None
        for c in row:
            correspondence = c.get('font','').endswith('CORRESAST') and c.get('flags',0)&1
            kind = ('sub' if c['baseline'] > baseline+main_size*.12 else 'sup') if main_size and (c['size'] < main_size*.85 or correspondence) and not c['text'].isspace() else None
            if kind != mode and script:
                text += '$' + ('_' if mode=='sub' else '^') + '{' + script + '}$'; script=''
            mode = kind
            if kind: script += c['text']
            else: text += c['text']
        if script: text += '$' + ('_' if mode=='sub' else '^') + '{' + script + '}$'
        lines.append(text.strip())
    value=unicodedata.normalize('NFKC',' '.join(lines).strip())
    value=''.join(c for c in value if ord(c)>=32 or c in '\n\t')
    value=re.sub(r'ð(?=\d)', '(', value)
    value=re.sub(r'(?<=\d)Þ', ')', value)
    return value


def compatible_native(candidate, ocr):
    if not candidate or any(c in candidate for c in ('\ufffd','ð','Þ','¼','þ','\x02')): return False
    a = re.sub(r'[^\w]', '', candidate).lower(); b = re.sub(r'[^\w]', '', ocr).lower()
    return bool(a and b and .65 <= len(a)/len(b) <= 1.4 and difflib.SequenceMatcher(None,a,b).ratio() >= .65)



def native_numeric_style(text, chars):
    """Keep scalar digits upright when their native PDF font is explicitly normal."""
    digits=[c for c in chars if any(ch.isdigit() for ch in c['text'])]
    if not digits or any(not c.get('font') or c.get('flags',0)&16 or 'bold' in c['font'].lower() or c['font'].lower().endswith('-b') for c in digits):
        return text
    native=re.sub(r'\s+','',''.join(c['text'] for c in sorted(chars,key=lambda c:c['box'][0])))
    def replace(match):
        value=match[1] or match[2]
        return value.strip() if re.sub(r'\s+','',value) in native else match[0]
    return re.sub(r'\\(?:mathbf|boldsymbol)\s*\{\s*([0-9][0-9\s.,]*)\}|\{\s*\\bf\s*([0-9][0-9\s.,]*)\}',replace,text)


def mixed_text(element, chars, diagnostics, vocabulary=()):
    meta = element.get('meta')
    if not isinstance(meta, list): return element.get('text','')
    pieces=[]; forbidden=[]
    for item in meta:
        box=quad_box(item['position']); box=[box[0]+element['box'][0]-30,box[1]+element['box'][1]-30,box[2]+element['box'][0]-30,box[3]+element['box'][1]-30]
        pieces.append((item,box))
        if item['type'] != 'text': forbidden.append(box)
    lines=[]
    for item,box in sorted(pieces,key=lambda p:(p[1][1],p[1][0])):
        cy=(box[1]+box[3])/2
        group=next((line for line in lines if abs(line['y']-cy)<min(line['height'],box[3]-box[1])*.5),None)
        if group is None:
            group={'y':cy,'height':box[3]-box[1],'pieces':[]};lines.append(group)
        if item['type']=='text':
            value=item['text']; native=native_text(chars,box,forbidden)
            if compatible_native(native,value):
                if native!=value: diagnostics['native_corrections']+=1
                marker=re.match(r'^([-•*]\s+)',value)
                if marker and not native.startswith(('-', '•', '*')):native=marker[1]+native
                value=native
        else:
            native=native_text(chars,box)
            selected=[c for c in chars if box[0]<(c['box'][0]+c['box'][2])/2<box[2] and box[1]<(c['box'][1]+c['box'][3])/2<box[3]]
            roman=bool(selected) and all(not c.get('flags',0)&2 and (c['font'].endswith('-R') or 'roman' in c['font'].lower() or c['font'].lower().endswith('regular')) for c in selected)
            if item['type']=='embedding' and roman and native and not any(c in native for c in ('ð','Þ','¼','þ','\ufffd')):
                value=native;diagnostics['native_corrections']+=1
            else:
                formula=native_numeric_style(item['text'],selected) if item['type']=='embedding' else item['text']
                value=('$'+formula.strip()+'$') if item['type']=='embedding' else ('\n\n$$\n'+item['text'].strip()+'\n$$\n\n')
        group['pieces'].append((box,value))
    output=[]
    for line in sorted(lines,key=lambda l:l['y']):
        previous=None;text=''
        for box,value in sorted(line['pieces'],key=lambda p:p[0][0]):
            if text and not text.endswith((' ','\n','(','[')) and not value.startswith(tuple(' ,.;:!?)]\n')): text+=' '
            text+=value;previous=box
        output.append(text.strip())
    if len(output)>1 and all(re.match(r'^[-•*]\s+',line) for line in output):return '\n'.join(output)
    joined=''
    for line in output:
        match=re.search(r'([A-Za-z]+)-$',joined)
        following=re.match(r'([a-z]+)',line)
        if match and following and (match[1]+following[1]).lower() in vocabulary:joined=joined[:-1]+line
        else:joined+=(' ' if joined else '')+line
    return joined.strip()



def front_matter_text(page, chars, element, current):
    """Recover clipped names and scripts from one matching native text block.

    Restricted to the first page's upper text region, with agreement and coverage
    gates. Equations and scanned pages continue through their existing paths.
    """
    if page['page'] != 1 or element['box'][3] > page['raster_size'][1]*.4:
        return current
    sx=page['raster_size'][0]/(page['size'][2]-page['size'][0])
    sy=page['raster_size'][1]/(page['size'][3]-page['size'][1])
    matches=[]
    for block in page['native']['blocks']:
        b=block['bbox']; box=[b[0]*sx,b[1]*sy,b[2]*sx,b[3]*sy]
        if overlap(box,element['box']) < .85: continue
        # Do not expand into adjacent columns or paragraphs.
        if box[2]-box[0] > (element['box'][2]-element['box'][0])*1.2: continue
        value=native_text(chars,box)
        if not re.search(r'\$\^\{[a-z*,†‡]+\}\$',value): continue
        a=re.sub(r'[^\w]','',value).lower(); b=re.sub(r'[^\w]','',current).lower()
        if compatible_native(value,current) and difflib.SequenceMatcher(None,a,b).ratio() >= .9:
            matches.append(value)
    return matches[0] if len(matches)==1 else current


def reading_order(nodes, width):
    """Infer two columns from prose, then partition around spanning objects."""
    prose=[n for n in nodes if n['kind'] in ('text','heading') and n['box'][2]-n['box'][0] < width*.57 and n['box'][2]-n['box'][0]>width*.15]
    left=[n['box'][0] for n in prose if n['box'][0]<width*.4]
    right=[n['box'][0] for n in prose if n['box'][0]>width*.45]
    if len(left)<2 or len(right)<2: return sorted(nodes,key=lambda n:(n['box'][1],n['box'][0],n['id']))
    cut=(sorted(left)[len(left)//2]+sorted(right)[len(right)//2])/2+width*.16
    spanning=[n for n in nodes if n['box'][0]<cut-width*.1 and n['box'][2]>cut+width*.1]
    rest=[n for n in nodes if n not in spanning];out=[]
    def columns(items):return sorted(items,key=lambda n:(0 if (n['box'][0]+n['box'][2])/2<cut else 1,n['box'][1],n['box'][0],n['id']))
    for barrier in sorted(spanning,key=lambda n:n['box'][1]):
        before=[n for n in rest if (n['box'][1]+n['box'][3])/2 < (barrier['box'][1]+barrier['box'][3])/2]
        out.extend(columns(before));out.append(barrier);rest=[n for n in rest if n not in before]
    return out+columns(rest)


def reconstruct(page):
    chars=native_characters(page)
    source_lines={}
    for c in chars:source_lines.setdefault(c['row'],[]).append(c['text'])
    vocabulary=set(re.findall(r'\b[a-z]{3,}\b',' '.join(''.join(r) for r in source_lines.values()).lower()))
    nodes=[];diagnostics={'native_corrections':0,'attached_labels':0,'unmatched_labels':[]}
    for i,element in enumerate(page['elements']):
        box=element['box'];matches=[r for r in page['layout'] if overlap(box,r['box'])>.65]
        raw=max(matches,key=lambda r:overlap(box,r['box']))['class'] if matches else ''
        kind={'TITLE':'heading','FORMULA':'equation','FIGURE':'figure','TABLE':'table'}.get(element['type'],'text')
        if isinstance(element.get('meta'),list) and len(element['meta'])>1 and all(re.match(r'^[-•*]\s+',v.get('text','')) for v in element['meta']):kind='list'
        if raw=='formula_caption':kind='label'
        elif raw in ('figure_caption','table_caption'):kind='caption'
        node={'id':i,'kind':kind,'box':box,'score':element['score'] if kind=='equation' else None,'raw_class':raw,
              'score_method':'pix2text-mfr-token-geometric-mean' if kind=='equation' else None,'calibrated':False}
        if kind=='figure':node['asset']=f"page-{page['page']:03}-figure-{i}.png"
        elif kind=='table':
            node['cells']=element['meta'].get('cells',[]);node['markdown']=element['meta'].get('markdown',[])
            if node['cells'] and node['cells'][0]:
                cells=node['cells'][0]; rows=max(max(c['row_nums']) for c in cells)+1; cols=max(max(c['column_nums']) for c in cells)+1
                grid=[['']*cols for _ in range(rows)]
                node['spans']=[{'row':min(c['row_nums']),'column':min(c['column_nums']),'rowspan':len(c['row_nums']),'colspan':len(c['column_nums'])} for c in cells]
                node['header_rows']=max((max(c['row_nums'])+1 for c in cells if c.get('column header')),default=1)
                for cell in cells:
                    c=cell['bbox'];absolute=[c[0]+box[0],c[1]+box[1],c[2]+box[0],c[3]+box[1]]
                    native=native_text(chars,absolute,repairs=element.get('native_formula_repairs',[]))
                    text=native if native and not any(c in native for c in ('ð','Þ','¼','þ','\ufffd')) else cell.get('cell text','')
                    grid[min(cell['row_nums'])][min(cell['column_nums'])]=text
                node['rows']=grid
                node['markdown']=['| '+' | '.join(row)+' |' for row in grid]
                node['markdown'].insert(1,'| '+' | '.join(['---']*cols)+' |')
                if any(c['rowspan']>1 or c['colspan']>1 for c in node['spans']):node['markdown']=[html_table(node)]
        elif kind=='equation':node['text']=element['text'].strip();node['label']=None
        elif kind=='label':
            native=native_text(chars,box);value=native if re.fullmatch(r'[\s(ð]*\d+(?:\.\d+)*[a-zA-Z]?[)Þ\s]*',native) else element['text']
            match=re.fullmatch(r'[\s(ð]*(\d+(?:\.\d+)*[a-zA-Z]?)[)Þ\s]*',value)
            node['text']=match[1] if match else value.strip()
        else:
            node['text']=mixed_text(element,chars,diagnostics,vocabulary)
            if kind=='text':
                recovered=front_matter_text(page,chars,element,node['text'])
                if recovered!=node['text']: diagnostics['native_corrections']+=1
                node['text']=recovered
            if kind=='heading' and (len(node['text'])>180 or any(ord(c)<32 for c in element.get('text',''))):node['kind']='text'
            if node['kind']=='heading':
                m=re.match(r'^(\d+(?:\.\d+)*)\.?\s',node['text']);node['level']=min(4,m[1].count('.')+2) if m else 1
        nodes.append(node)
    for label in [n for n in nodes if n['kind']=='label']:
        box=label['box'];candidates=[]
        for eq in nodes:
            if eq['kind']!='equation' or eq.get('label') is not None:continue
            b=eq['box'];dy=max(0,max(b[1],box[1])-min(b[3],box[3]));dx=box[0]-b[2]
            same_column=((box[0]+box[2])/2 < page['raster_size'][0]*.5)==((b[0]+b[2])/2 < page['raster_size'][0]*.5)
            if same_column and -max(30,(b[2]-b[0])*.3)<=dx<=page['raster_size'][0]*.48 and dy<max(box[3]-box[1],30):candidates.append((abs((box[1]+box[3]-b[1]-b[3])/2)*3+abs(dx)*.005,eq))
        candidates.sort(key=lambda p:p[0])
        if candidates and (len(candidates)==1 or candidates[1][0]-candidates[0][0]>4) and re.fullmatch(r'\d+(?:\.\d+)*[a-zA-Z]?',label['text']):
            candidates[0][1]['label']=label['text'];label['consumed']=True;diagnostics['attached_labels']+=1
        else:diagnostics['unmatched_labels'].append(label['text'])
    raw_captions=[]
    caption_regions=[r for r in page['layout'] if r['class'] in ('figure_caption','table_caption')]
    sx=page['raster_size'][0]/(page['size'][2]-page['size'][0]);sy=page['raster_size'][1]/(page['size'][3]-page['size'][1])
    for block in page['native']['blocks']:
        value=' '.join(''.join(c['c'] for span in line['spans'] for c in span['chars']) for line in block.get('lines',[]))
        match=re.match(r'^(Table|Fig(?:ure)?\.?)\s+\d+\s*[:.]',value)
        if match:
            b=block['bbox'];caption_regions.append({'class':'table_caption' if match[1]=='Table' else 'figure_caption','box':[b[0]*sx,b[1]*sy,b[2]*sx,b[3]*sy]})
    for raw in sorted(caption_regions,key=lambda r:(r['box'][2]-r['box'][0])*(r['box'][3]-r['box'][1]),reverse=True):
        if raw['class'] not in ('figure_caption','table_caption'):continue
        value=native_text(chars,raw['box'])
        if not value or any(c in value for c in ('ð','Þ','¼','þ','\ufffd')):continue
        if any(overlap(raw['box'],n['box'])>.7 for n in raw_captions):continue
        raw_captions.append({'id':10000+len(raw_captions),'kind':'caption','box':raw['box'],'text':value,'raw_class':raw['class']})
    for cap in raw_captions:
        for node in nodes:
            if node['kind'] in ('caption','text') and overlap(cap['box'],node['box'])>.7:node['consumed']=True
    nodes.extend(raw_captions)
    # Group caption with the closest compatible object, retaining its original text and box.
    for caption in [n for n in nodes if n['kind']=='caption' and not n.get('consumed')]:
        targets=[]
        expected='table' if caption['raw_class']=='table_caption' else 'figure'
        b=caption['box']
        for target in nodes:
            if target['kind']!=expected:continue
            a=target['box'];x=max(0,min(a[2],b[2])-max(a[0],b[0]));gap=max(0,max(a[1],b[1])-min(a[3],b[3]))
            if x>=min(a[2]-a[0],b[2]-b[0])*.6 and gap<page['raster_size'][1]*.045:targets.append((gap,target))
        targets.sort(key=lambda p:p[0])
        if targets and (len(targets)==1 or targets[1][0]-targets[0][0]>8):
            targets[0][1]['caption']=caption['text'];caption['consumed']=True
    return {'page':page['page'],'size':page['raster_size'],'nodes':reading_order([n for n in nodes if not n.get('consumed')],page['raster_size'][0]),'diagnostics':diagnostics}


def markdown(document):
    pieces=[]
    for n in document['nodes']:
        kind=n['kind']
        if kind=='equation':pieces.append('$$\n'+n['text']+((' \\tag{'+n['label']+'}') if n.get('label') else '')+'\n$$')
        elif kind=='heading':pieces.append('#'*n['level']+' '+n['text'])
        elif kind=='figure':pieces.append('![](assets/'+n['asset']+')'+(('\n\n'+n['caption']) if n.get('caption') else ''))
        elif kind=='table':pieces.append('\n'.join(n['markdown'])+(('\n\n'+n['caption']) if n.get('caption') else ''))
        else:pieces.append(n.get('text',''))
    return '\n\n'.join(p for p in pieces if p.strip())+'\n'


def html_table(node):
    anchors={(c['row'],c['column']):c for c in node['spans']}
    covered={(r,col) for c in node['spans'] for r in range(c['row'],c['row']+c['rowspan']) for col in range(c['column'],c['column']+c['colspan']) if (r,col)!=(c['row'],c['column'])}
    out=['<table>']
    for r,row in enumerate(node['rows']):
        out.append('<tr>')
        for col,value in enumerate(row):
            if (r,col) in covered:continue
            cell=anchors.get((r,col),{'rowspan':1,'colspan':1});tag='th' if r<node.get('header_rows',1) else 'td'
            out.append(f'<{tag} rowspan="{cell["rowspan"]}" colspan="{cell["colspan"]}">'+html.escape(value)+f'</{tag}>')
        out.append('</tr>')
    return '\n'.join(out+['</table>'])


def tex_table_rows(node):
    anchors={(c['row'],c['column']):c for c in node.get('spans',[])}
    owners={(r,col):c for c in node.get('spans',[]) for r in range(c['row'],c['row']+c['rowspan']) for col in range(c['column'],c['column']+c['colspan'])}
    result=[]
    for r,row in enumerate(node['rows']):
        cells=[];col=0
        while col<len(row):
            cell=anchors.get((r,col));owner=owners.get((r,col))
            if cell:
                value=inline_tex(row[col])
                if cell['rowspan']>1:value=r'\multirow{'+str(cell['rowspan'])+'}{*}{'+value+'}'
                if cell['colspan']>1:value=r'\multicolumn{'+str(cell['colspan'])+'}{l}{'+value+'}'
                cells.append(value);col+=cell['colspan']
            elif owner and owner['row']<r:
                width=owner['colspan'];cells.append(r'\multicolumn{'+str(width)+'}{l}{}' if width>1 else '');col+=width
            else:cells.append(inline_tex(row[col]));col+=1
        result.append(' & '.join(cells)+r' \\')
    return result


def escape_tex(text):
    mapping={'\\':r'\textbackslash{}','{':r'\{','}':r'\}','$':r'\$','&':r'\&','%':r'\%','#':r'\#','_':r'\_','^':r'\textasciicircum{}','~':r'\textasciitilde{}'}
    symbols={'⇑':'Uparrow','↑':'uparrow','↓':'downarrow','→':'rightarrow','←':'leftarrow','↔':'leftrightarrow','≤':'leq','≥':'geq','≠':'neq','±':'pm','×':'times','∞':'infty'}
    mapping.update({c:r'\ensuremath{'+chr(92)+name+'}' for c,name in symbols.items()})
    return ''.join(mapping.get(c,c) for c in text if ord(c)>=32 or c in '\n\t')


def inline_tex(text):
    out=[]
    for part in re.split(r'(\$\$.*?\$\$|\$[^$]+\$)',text,flags=re.S):
        if part.startswith('$$') and part.endswith('$$'):out.append('\\['+part[2:-2]+'\\]')
        elif part.startswith('$') and part.endswith('$'):out.append(re.sub(r'\\l(?![A-Za-z])',lambda _:r'\text{\l}',part))
        else:out.append(escape_tex(part))
    return ''.join(out)


def latex(document):
    out=[]
    for n in document['nodes']:
        kind=n['kind']
        if kind=='equation':out.append('\\[\n'+re.sub(r'\\l(?![A-Za-z])',lambda _:r'\text{\l}',n['text'])+((' \\tag{'+n['label']+'}') if n.get('label') else '')+'\n\\]')
        elif kind=='list':out.append('\\begin{itemize}\n'+'\n'.join('\\item '+inline_tex(re.sub(r'^[-•*]\s+','',line)) for line in n['text'].splitlines())+'\n\\end{itemize}')
        elif kind=='heading':out.append('\\'+('section*' if n['level']<=2 else 'subsection*')+'{'+inline_tex(n['text'])+'}')
        elif kind=='figure':out.append('\\begin{center}\\includegraphics[width=\\linewidth,height=.8\\textheight,keepaspectratio]{assets/'+n['asset']+'}\\end{center}'+(('\n\n'+inline_tex(n['caption'])) if n.get('caption') else ''))
        elif kind=='table':
            rows=n.get('rows',[])
            if rows:
                rendered=tex_table_rows(n);headers=n.get('header_rows',1)
                header='\n'.join(rendered[:headers]);body='\n'.join(rendered[headers:])
                if len(rows[0])>6 and len(rows)<=60:
                    table='\\begin{center}\\resizebox{\\linewidth}{!}{\\begin{tabular}{'+'l'*len(rows[0])+'}\n\\toprule\n'+header+'\n\\midrule\n'+body+'\n\\bottomrule\n\\end{tabular}}\\end{center}'
                else:
                    table='\\begin{longtable}{'+'l'*len(rows[0])+'}\n\\toprule\n'+header+'\n\\midrule\n\\endfirsthead\n\\toprule\n'+header+'\n\\midrule\n\\endhead\n'+body+'\n\\bottomrule\n\\end{longtable}'
                out.append(table+(('\n\n'+inline_tex(n['caption'])) if n.get('caption') else ''))
            else:out.append(inline_tex('\n'.join(n['markdown'])))
        else:out.append(inline_tex(n.get('text','')))
    return '\n\n'.join(out)+'\n'
