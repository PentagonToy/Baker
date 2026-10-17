"""Single-image GLM OCR inference without Transformers, PyTorch or a model server."""
import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import sys
import time

import mlx.core as mx
import mlx.nn as nn
from mlx.utils import tree_unflatten
import numpy as np
from tokenizers import Tokenizer


class Adapter(nn.Module):
    def __init__(self,linear,a,b,scale):
        super().__init__();self.linear=linear;self.a=a;self.b=b;self.scale=scale
    def __call__(self,x):return self.linear(x)+(self.scale*((x@self.a)@self.b)).astype(x.dtype)


@dataclass
class Prediction:
    text:str
    finish_reason:str


class Engine:
    def __init__(self,model_path,code_path,adapter_path=None):
        sys.path.insert(0,str(code_path))
        from baker_model.glm_ocr import Model,ModelConfig
        from baker_model.processing import Glm46VImageProcessor
        from baker_model.cache import KVCache
        self.KVCache=KVCache
        config=json.loads((model_path/'config.json').read_text());self.config=config
        self.model=Model(ModelConfig.from_dict(config));quant=config['quantization']
        nn.quantize(self.model,group_size=quant['group_size'],bits=quant['bits'],class_predicate=lambda name,module:quant.get(name,False))
        weights={}
        for path in sorted(model_path.glob('*.safetensors')):weights.update(mx.load(str(path)))
        self.model.load_weights(list(weights.items()),strict=True);del weights
        if adapter_path:
            metadata=json.loads((adapter_path/'adapter_config.json').read_text());parameters=mx.load(str(adapter_path/'adapters.safetensors'));modules=dict(self.model.named_modules());updates=[]
            base_quant={name:value for name,value in quant.items() if isinstance(value,dict)}
            if metadata['base_quantization']!=base_quant:raise ValueError('Adapter quantisation does not match this base model')
            for name in metadata['lora_parameters']['keys']:
                updates.append((name,Adapter(modules[name],parameters[name+'.lora_a'],parameters[name+'.lora_b'],metadata['lora_parameters']['scale'])))
            self.model.update_modules(tree_unflatten(updates))
        self.model.eval();mx.eval(self.model.parameters());mx.set_cache_limit(256*1024**2)
        self.tokenizer=Tokenizer.from_file(str(model_path/'tokenizer.json'))
        image_config=json.loads((model_path/'processor_config.json').read_text())['image_processor'];image_config['use_transformers_backend']=False
        self.processor=Glm46VImageProcessor(**image_config)

    def inputs(self,image,task):
        pixels=self.processor(images=[image]);grid=pixels['image_grid_thw'];count=int(np.prod(grid[0])//4)
        prompt='[gMASK]<sop><|user|>\n<|begin_of_image|>'+('<|image|>'*count)+'<|end_of_image|>'+task+'/nothink<|assistant|>\n<think></think>\n'
        ids=self.tokenizer.encode(prompt,add_special_tokens=False).ids
        return {'input_ids':mx.array([ids]),'pixel_values':mx.array(pixels['pixel_values']),'image_grid_thw':mx.array(grid)}

    def recognise(self,image,task,max_tokens=1024):
        inputs=self.inputs(image,task);ids=inputs['input_ids'];mask=mx.ones(ids.shape,dtype=mx.int32)
        cache=[self.KVCache() for layer in self.model.layers]
        embeddings=self.model.get_input_embeddings(**inputs,mask=mask).inputs_embeds
        for offset in range(0,ids.shape[1],512):
            logits=self.model.language_model(ids[:,offset:offset+512],inputs_embeds=embeddings[:,offset:offset+512],cache=cache).logits
            mx.eval(logits)
        generated=[];stop=set(self.config['eos_token_id']);reason='length'
        for i in range(max_tokens):
            token=int(mx.argmax(logits[0,-1]).item())
            if token in stop:reason='stop';break
            generated.append(token)
            logits=self.model.language_model(mx.array([[token]]),cache=cache).logits
        text=self.tokenizer.decode(generated,skip_special_tokens=True)
        del cache,embeddings,logits;mx.clear_cache()
        return Prediction(text,reason)


def main(args):
    from PIL import Image
    start=time.monotonic();engine=Engine(args.model,args.code,args.adapter);prep=time.monotonic()-start
    if args.output.exists():raise ValueError('Predictions already exist')
    rows=list(map(json.loads,args.manifest.read_text().splitlines()))
    if args.split:rows=[r for r in rows if r['split'] in args.split]
    if args.limit:rows=rows[:args.limit]
    with args.output.open('w') as stream:
        for i,row in enumerate(rows):
            begin=time.monotonic();result=engine.recognise(Image.open(row['image']).convert('RGB'),{'text':'Text Recognition:','formula':'Formula Recognition:','table':'Table Recognition:'}[row['kind']],1600 if row['kind']=='table' else 512)
            record={'id':row['id'],'prediction':result.text,'seconds':time.monotonic()-begin,'preparation_seconds':prep,'finish_reason':result.finish_reason}
            stream.write(json.dumps(record,ensure_ascii=False)+'\n');stream.flush();print(i+1,row['id'],round(record['seconds'],3),flush=True)
    imported=[name for name in ['torch','transformers','mlx_vlm'] if name in sys.modules]
    if imported:raise RuntimeError('Unexpected general runtime imports: '+','.join(imported))


if __name__=='__main__':
    p=argparse.ArgumentParser()
    for name in ['model','code','manifest','output']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--adapter',type=Path);p.add_argument('--split',nargs='+');p.add_argument('--limit',type=int);main(p.parse_args())
