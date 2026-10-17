"""Conservative native-PDF line joining and footnote placement for the candidate."""
from pathlib import Path
import re


def vocabulary(document):
    text='\n'.join(page.get_text('text') for page in document)
    words=set(word.lower() for word in re.findall(r'[A-Za-z]{3,}',text))
    dictionary=Path('/usr/share/dict/words')
    if dictionary.is_file():words.update(dictionary.read_text().lower().splitlines())
    compounds=set(word.lower() for word in re.findall(r'[A-Za-z]+-[A-Za-z]+',text))
    return words,compounds


def join_lines(lines,words,compounds):
    result='';bibliography=sum(bool(re.match(r'^\[\d+\]\s',line)) for line in lines)>=3
    for line in lines:
        ending=re.search(r'([A-Za-z]+)-$',result);beginning=re.match(r'([a-z][A-Za-z]*)',line)
        if bibliography and result and re.match(r'^\[\d+\]\s',line):result+='\n\n'+line
        elif ending and beginning:
            left,right=ending[1],beginning[1]
            if (left+'-'+right).lower() not in compounds and (left+right).lower() in words:
                result=result[:-1]+line
            else:result+=line
        else:result+=(' ' if result else '')+line
    return result


def native_prose(chars,box,reconstruction,words,compounds):
    rows={}
    for char in chars:
        b=char['box']
        if box[0]<=(b[0]+b[2])/2<=box[2] and box[1]<=(b[1]+b[3])/2<=box[3]:
            rows.setdefault(char['row'],[]).append(char)
    lines=[reconstruction.native_text(row,box) for row in sorted(rows.values(),key=lambda group:min(c['box'][1] for c in group))]
    return join_lines(lines,words,compounds)


def finish_flow(document,footnotes,words,compounds):
    """Keep footnotes after both columns and join an interrupted native word."""
    nodes=document['nodes'];notes=[n for n in nodes if n['id'] in footnotes]
    body=[n for n in nodes if n['id'] not in footnotes];result=[]
    for node in body:
        if result and result[-1]['kind']==node['kind']=='text':
            left=result[-1];ending=re.search(r'([A-Za-z]+)-$',left.get('text',''));beginning=re.match(r'([a-z][A-Za-z]*)',node.get('text',''))
            if ending and beginning and ((ending[1]+beginning[1]).lower() in words or (ending[1]+'-'+beginning[1]).lower() in compounds):
                left['text']=join_lines([left['text'],node['text']],words,compounds)
                left.setdefault('merged_ids',[]).append(node['id']);continue
        result.append(node)
    document['nodes']=result+notes


def front_matter(document):
    """Keep a sidebar's metadata separate from an adjacent abstract column."""
    if document['page']!=1:return
    nodes=document['nodes']
    def label(node):return re.sub(r'\s|:','',node.get('text','')).lower()
    abstract=next((n for n in nodes if n['kind']=='heading' and label(n)=='abstract'),None)
    if not abstract:return
    boundary=next((i for i,n in enumerate(nodes) if n['kind']=='heading' and re.match(r'^\s*1[.]?\s+\w',n.get('text',''))),None)
    if boundary is None:return
    prefix=nodes[:boundary];b=abstract['box']
    def same_column(node):
        a=node['box'];intersection=max(0,min(a[2],b[2])-max(a[0],b[0]))
        return intersection/max(1,min(a[2]-a[0],b[2]-b[0]))>.8 and a[1]>b[1]
    paragraphs=[n for n in prefix if n['kind']=='text' and same_column(n)]
    if not paragraphs:return
    other=[n for n in prefix if n is not abstract and n not in paragraphs]
    if any(n['kind']=='text' and n.get('text','').lower().startswith('keywords:') for n in other):
        other=[n for n in other if not (n['kind']=='heading' and label(n)=='keywords')]
    for node in other:
        if node['kind']=='heading' and label(node)=='articleinfo':node['text']='Article information'
    abstract['text']='Abstract'
    document['nodes']=other+[abstract]+paragraphs+nodes[boundary:]


def attach_equation_labels(document):
    """Match explicit formula-caption regions to nearby unlabelled equations."""
    nodes=document['nodes'];width=max((n['box'][2] for n in nodes),default=1);pairs=[]
    equations=[n for n in nodes if n['kind']=='equation' and not n.get('label')]
    labels=[n for n in nodes if n['kind']=='label' and n.get('raw_class')=='formula_caption' and re.fullmatch(r'\(?\d+(?:\.\d+)*[a-zA-Z]?\)?',n.get('text','').strip())]
    for label in labels:
        b=label['box'];x=(b[0]+b[2])/2;y=(b[1]+b[3])/2
        for equation in equations:
            a=equation['box'];dy=abs(y-(a[1]+a[3])/2);height=max(a[3]-a[1],b[3]-b[1])
            if x<=(a[0]+a[2])/2 or dy>height*.75:continue
            pairs.append((dy/max(1,height)+.5*max(0,x-a[2])/width,label,equation))
    used_labels=set();used_equations=set()
    for cost,label,equation in sorted(pairs,key=lambda p:p[0]):
        if label['id'] in used_labels or equation['id'] in used_equations:continue
        equation['label']=label['text'].strip('() ');used_labels.add(label['id']);used_equations.add(equation['id'])
    document['nodes']=[n for n in nodes if n['id'] not in used_labels]


def deduplicate_text(document):
    """Discard a clipped duplicate only when text and physical regions agree."""
    nodes=document['nodes'];candidates=[n for n in nodes if n['kind'] in ('heading','text')];kept=[];removed=set()
    compact=lambda node:re.sub(r'\W','',node.get('text',''))
    for node in sorted(candidates,key=lambda n:(len(compact(n)),n['kind']=='heading'),reverse=True):
        a=node['box'];text=compact(node);duplicate=False
        if len(text)<12:kept.append(node);continue
        for other in kept:
            b=other['box'];other_text=compact(other)
            if not text or len(text)/max(1,len(other_text))<.8 or text not in other_text:continue
            intersection=max(0,min(a[2],b[2])-max(a[0],b[0]))*max(0,min(a[3],b[3])-max(a[1],b[1]))
            area=min(max(0,a[2]-a[0])*max(0,a[3]-a[1]),max(0,b[2]-b[0])*max(0,b[3]-b[1]))
            if intersection/max(1,area)>.9:duplicate=True;break
        if duplicate:removed.add(id(node))
        else:kept.append(node)
    document['nodes']=[n for n in nodes if id(n) not in removed]
