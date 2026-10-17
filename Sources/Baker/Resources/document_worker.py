"""Offline document job. Models live outside the app; one page raster is owned at a time."""
import argparse
import gc
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sys
import time


def write_progress(output, page, total, phase):
    pending = output / 'progress.pending'
    pending.write_text(json.dumps({'page': page, 'total': total, 'phase': phase}))
    pending.replace(output / 'progress.json')


def load_reconstruction():
    path=Path(__file__).with_name('document_reconstruction.py')
    spec=importlib.util.spec_from_file_location('baker_document_reconstruction',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


class DeferredTableOCR:
    """Keep full table recognition automatic, but load its weights only on first use."""
    def __init__(self,factory):self.factory=factory;self.engine=None

    def recognize(self,*args,**kwargs):
        if self.engine is None:
            self.engine=self.factory()
            self.factory=None
        return self.engine.recognize(*args,**kwargs)


def prepare_engine(settings, cache):
    # Some inference dependencies spawn Python helpers without inheriting -B.
    # Keep those helpers from adding bytecode inside the signed application.
    os.environ['PYTHONDONTWRITEBYTECODE']='1'
    for name,value in {'HF_HUB_OFFLINE':'1','TRANSFORMERS_OFFLINE':'1','HF_HUB_DISABLE_TELEMETRY':'1','DO_NOT_TRACK':'1',
                       'WANDB_MODE':'disabled','YOLO_AUTOINSTALL':'false','ULTRALYTICS_AUTOINSTALL':'false',
                       'YOLO_CONFIG_DIR':str(cache/'yolo'),'HF_HOME':str(cache/'huggingface'),
                       'CNOCR_HOME':str(Path(settings['models'])/'cnocr'),'CNSTD_HOME':str(Path(settings['models'])/'cnstd')}.items():os.environ[name]=value
    # Fail before model construction; no implicit download or remote-code loader is permitted.
    for filename,expected in settings['files'].items():
        path=Path(filename)
        if not path.is_file() or path.stat().st_size!=expected['bytes']:raise ValueError('Document model is missing or incomplete: '+path.name)
        digest=hashlib.sha256()
        with path.open('rb') as stream:
            for data in iter(lambda:stream.read(1024*1024),b''):digest.update(data)
        if digest.hexdigest()!=expected['sha256']:raise ValueError('Document model integrity check failed: '+path.name)
    import torch
    import onnxruntime
    torch.set_num_threads(2);onnxruntime.disable_telemetry_events()
    from ultralytics import settings as yolo_settings
    yolo_settings.update({'sync':False})
    from pix2text import Pix2Text
    session=onnxruntime.SessionOptions();session.intra_op_num_threads=2;session.inter_op_num_threads=1
    # Do not retain large temporary MFR allocations across differently sized regions.
    session.enable_cpu_mem_arena=False;session.enable_mem_pattern=False
    models=Path(settings['models'])
    config={'layout':{'model_fp':str(models/'doclayout_yolo_docstructbench_imgsz1024.pt')},
            'text_formula':{'languages':['en'],'mfd':{'model_path':str(models/'pix2text-mfd-1.5.onnx')},
                            'formula':{'model_dir':settings['mfr'],'more_model_configs':{'provider':'CPUExecutionProvider','session_options':session}}},
            'table':{'model_dir':str(models/'table-rec')}}
    engine=Pix2Text.from_config(config,enable_table=False,device='cpu')
    from pix2text.pix_to_text import prepare_table_ocr_engine
    text_formula=engine.text_formula_ocr
    engine.table_ocr=DeferredTableOCR(lambda:prepare_table_ocr_engine(dict(config['table']),device='cpu',text_formula_ocr=text_formula))
    return engine


def repair_table_math(element, image, chars, engine):
    """Re-recognise suspicious embedded-font runs; do not substitute a hard-coded glyph map."""
    repairs=[]
    for cells in element['meta'].get('cells',[]):
        for cell in cells:
            if not cell.get('column header'):continue
            b=cell['bbox'];x,y=element['box'][:2];b=[b[0]+x,b[1]+y,b[2]+x,b[3]+y]
            selected=[c for c in chars if b[0]<(c['box'][0]+c['box'][2])/2<b[2] and b[1]<(c['box'][1]+c['box'][3])/2<b[3]]
            suspect=[c for c in selected if c['text'].isascii() and any(marker in c['font'].lower() for marker in ('symbol','math','advps'))]
            if not suspect:continue
            start=min(c['box'][0] for c in suspect)
            run=[c for c in selected if c['box'][0]>=start-1 and c['text'] not in '()']
            crop=[max(0,min(c['box'][0] for c in run)-3),max(0,min(c['box'][1] for c in run)-5),
                  min(image.width,max(c['box'][2] for c in run)+3),min(image.height,max(c['box'][3] for c in run)+5)]
            try:result=engine.text_formula_ocr.recognize_formula(image.crop(crop),return_text=False)
            except (ValueError,RuntimeError):continue
            repairs.append({'box':crop,'latex':result['text'],'score':float(result['score'])})
    element['native_formula_repairs']=repairs


class PageLayoutPrediction:
    """Reuse only this page's identical layout request; forward anything else."""
    def __init__(self, predictor, image, prediction):
        self.predictor=predictor;self.image=image;self.prediction=prediction

    def predict(self, source, *args, **kwargs):
        compatible=not args and set(kwargs)<= {'imgsz','conf','verbose'} and kwargs.get('imgsz',1024)==1024 and kwargs.get('conf',.2)==.2
        if compatible and source==self.image:return [self.prediction]
        return self.predictor.predict(source,*args,**kwargs)

    def __getattr__(self,name):return getattr(self.predictor,name)


def release_page_buffers(engine):
    """Discard completed prediction inputs while retaining loaded model weights."""
    models=[engine.layout_parser.predictor,getattr(engine.text_formula_ocr.mfd,'model',None)]
    for model in models:
        runner=getattr(model,'predictor',None)
        if runner is not None:
            for name in ('results','batch','plotted_img','dataset'):
                if hasattr(runner,name):setattr(runner,name,None)


def release_unused_memory():
    gc.collect()
    if sys.platform=='darwin':
        import ctypes
        relief=ctypes.CDLL(None).malloc_zone_pressure_relief
        relief.argtypes=[ctypes.c_void_p,ctypes.c_size_t];relief.restype=ctypes.c_size_t
        relief(None,0)


def analyse_page(page, number, engine, reconstruction):
    from PIL import Image
    import pymupdf
    if page.rect.width*page.rect.height*(300/72)**2>24_000_000:raise ValueError("Page raster exceeds 24 megapixels")
    pix=page.get_pixmap(dpi=300,alpha=False)
    if pix.width*pix.height>24_000_000:raise ValueError('Page raster exceeds 24 megapixels')
    raster_size=[pix.width,pix.height]
    image=Image.frombytes('RGB',raster_size,pix.samples)
    del pix  # Pillow owns its pixels; do not retain a second full-page raster.
    prediction=engine.layout_parser.predictor.predict(image,imgsz=1024,conf=.2,verbose=False)[0]
    layout=[{'box':b,'class':prediction.names[int(c)],'score':float(s)} for b,c,s in zip(prediction.boxes.xyxy.tolist(),prediction.boxes.cls.tolist(),prediction.boxes.conf.tolist())]
    predictor=engine.layout_parser.predictor
    engine.layout_parser.predictor=PageLayoutPrediction(predictor,image,prediction)
    try:result=engine.recognize_page(image,page_number=number-1,page_id=str(number),mfr_batch_size=1)
    finally:engine.layout_parser.predictor=predictor
    del prediction
    release_page_buffers(engine)
    elements=[{'box':e.box,'type':e.type.name,'text':e.text,'meta':e.meta,'score':float(e.score)} for e in result.elements]
    del result
    # Embedded image payloads are not needed for character geometry or output figures.
    native=page.get_text('rawdict',flags=pymupdf.TEXTFLAGS_RAWDICT & ~pymupdf.TEXT_PRESERVE_IMAGES)
    native['blocks']=[b for b in native['blocks'] if b['type']==0]
    raw={'page':number,'size':list(page.rect),'raster_size':raster_size,'layout':layout,'elements':elements,'native':native}
    chars=reconstruction.native_characters(raw)
    if len(chars)>250_000:raise ValueError('Page exceeds the character limit')
    for e in elements:
        if e['type']=='TABLE':repair_table_math(e,image,chars,engine)
    return reconstruction.reconstruct(raw),image


def convert(source, output, config):
    import pymupdf
    if source.stat().st_size>256*1024*1024:raise ValueError('PDF exceeds 256 MB')
    settings=json.loads(config.read_text())
    def model_path(value):
        path=Path(value)
        return str(path if path.is_absolute() else (config.parent/path).resolve())
    settings['models']=model_path(settings['models']);settings['mfr']=model_path(settings['mfr'])
    settings['files']={model_path(name):info for name,info in settings['files'].items()}
    if output.exists():raise ValueError('Document output already exists')
    output.mkdir(mode=0o700,parents=True);(output/'assets').mkdir()
    reconstruction=load_reconstruction();started=time.monotonic();diagnostics=[]
    with pymupdf.open(source) as document, (output/'document.md').open('w') as md, (output/'document.tex').open('w') as tex:
        if document.is_encrypted or not document.permissions & pymupdf.PDF_PERM_COPY:raise ValueError('PDF is locked or does not allow copying')
        if not 0<len(document)<=2000:raise ValueError('PDF page count exceeds the document limit')
        write_progress(output, 0, len(document), 'preparing')
        engine=prepare_engine(settings,output/'cache')
        tex.write('\\documentclass{article}\n\\usepackage{fontspec,amsmath,amssymb,graphicx,longtable,booktabs,multirow}\n\\usepackage[margin=25mm]{geometry}\n\\begin{document}\n')
        for index,page in enumerate(document):
            if time.monotonic()-started>7200:raise TimeoutError('Document job exceeded two hours')
            write_progress(output, index+1, len(document), 'recognising')
            result,image=analyse_page(page,index+1,engine,reconstruction)
            for node in result['nodes']:
                if node['kind']=='figure':
                    b=node['box']; image.crop([max(0,b[0]-32),max(0,b[1]-8),min(image.width,b[2]+32),min(image.height,b[3]+8)]).save(output/'assets'/node['asset'])
            md.write(reconstruction.markdown(result)+'\n');tex.write(reconstruction.latex(result)+'\n')
            with (output/'document.jsonl').open('a') as record:record.write(json.dumps(result,ensure_ascii=False,default=lambda x:x.tolist() if hasattr(x,'tolist') else x.item())+'\n')
            diagnostics.append({'page':index+1,'block_count':len(result['nodes']),'character_count':sum(len(n.get('text','')) for n in result['nodes']),**result['diagnostics']})
            write_progress(output, index+1, len(document), 'completed')
            del result,image
            release_unused_memory()
            if sum(p.stat().st_size for p in output.rglob('*') if p.is_file())>512*1024*1024:raise ValueError('Document output exceeds 512 MB')
        write_progress(output, len(document), len(document), 'finalising')
        tex.write('\\end{document}\n')
    (output/'report.json').write_text(json.dumps({'pages':diagnostics,'seconds':time.monotonic()-started,'engine':'baker-structured-pix2text-1','warnings':['Recognition remains approximate; review mathematical symbols against the original.']},indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--config',type=Path,required=True)
    args=parser.parse_args()
    try:
        settings = json.loads(args.config.read_text())
        if settings.get('engine') == 'baker-small-ocr-1':
            root = args.config.resolve().parent
            sys.path.insert(0, str(root / 'worker'))
            from pdf_candidate import main
            from types import SimpleNamespace
            main(SimpleNamespace(source=args.source, output=args.output, layout=root/'layout.onnx',
                                 model=root/'model', adapter=root/'adapter', code=root/'code',
                                 reconstruction=root/'worker/document_reconstruction.py'))
        else:
            convert(args.source,args.output,args.config)
    except Exception as error:
        print(type(error).__name__+': '+str(error),file=sys.stderr);sys.exit(1)
