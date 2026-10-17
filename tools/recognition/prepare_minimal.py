"""Extract the pinned MLX GLM implementation without the general model launcher.

Generated code retains the upstream MIT licence and an auditable source inventory.
Only inference with plain KV caches is supported by the small support module.
"""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import shutil
from importlib import metadata


def main(args):
    source=args.site_packages/'mlx_vlm';destination=args.output/'baker_model'
    versions=[dist.version for dist in metadata.distributions(path=[str(args.site_packages)]) if dist.metadata.get('Name')=='mlx-vlm']
    if versions!=['0.7.8']:raise ValueError('Extraction requires the tested mlx-vlm 0.7.8 distribution')
    if args.output.exists():raise ValueError('Minimal runtime already exists')
    (destination/'glm_ocr').mkdir(parents=True);(destination/'__init__.py').write_text('')
    inventory=[]
    for name in ['models/rope_utils.py','models/cache.py','models/glm_ocr/__init__.py','models/glm_ocr/config.py','models/glm_ocr/language.py','models/glm_ocr/vision.py','models/glm_ocr/glm_ocr.py']:
        path=source/name;relative=name.removeprefix('models/');target=destination/relative
        content=path.read_text()
        if relative=='glm_ocr/__init__.py':content=content.replace('from .processing import GlmOcrProcessor\n','')
        target.write_text('# Derived from MLX-VLM 0.7.8, MIT licence; see LICENSE and source-inventory.json.\n'+content)
        inventory.append({'source':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'output':str(target)})
    text=(source/'models/base.py').read_text();lines=text.splitlines();tree=ast.parse(text)
    selected=[]
    for node in tree.body:
        if getattr(node,'name','') in ['LanguageModelOutput','InputEmbeddingsFeatures','BaseModelConfig','create_attention_mask']:
            start=min([node.lineno]+[x.lineno for x in getattr(node,'decorator_list',[])])-1;selected.append('\n'.join(lines[start:node.end_lineno]))
    support='''# Selected MLX-VLM 0.7.8 definitions, MIT; narrowed to plain KV inference.\nimport inspect\nfrom dataclasses import dataclass\nfrom typing import Any,Dict,List,Optional\nimport mlx.core as mx\nfrom .cache import create_causal_mask\n\n'''+ '\n\n'.join(selected)+'''

def kv_sequence_length(keys):
    return keys.shape[-2]


def scaled_dot_product_attention(queries,keys,values,cache,scale,mask,sinks=None):
    if hasattr(cache,'bits'):raise ValueError('Only plain KV caches are supported')
    return mx.fast.scaled_dot_product_attention(queries,keys,values,scale=scale,mask=mask,sinks=sinks)
'''
    (destination/'base.py').write_text(support)
    processing=(source/'models/glm_ocr/processing.py').read_text();qwen=(source/'models/qwen3_vl/processing_qwen3_vl.py').read_text();parts=[]
    for name in ['models/base.py','models/glm_ocr/processing.py','models/qwen3_vl/processing_qwen3_vl.py']:
        path=source/name;inventory.append({'source':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'output':'selected definitions in base.py or processing.py'})
    for content,names in [(qwen,['_resize_video_frames','_to_numpy_image']),(processing,['smart_resize','Glm46VImageProcessor'])]:
        source_lines=content.splitlines()
        for node in ast.parse(content).body:
            if getattr(node,'name','') in names:
                segment='\n'.join(source_lines[node.lineno-1:node.end_lineno])
                segment=segment.replace('class Glm46VImageProcessor(ImageProcessingMixin):','class Glm46VImageProcessor:')
                parts.append(segment)
    (destination/'processing.py').write_text('# Derived from MLX-VLM0.7.8, MIT. Serialisation and optional HF backend are unused.\nimport math\nfrom typing import List,Optional,Tuple\nimport numpy as np\n\n'+'\n\n'.join(parts))
    licences=list(args.site_packages.glob('mlx_vlm-*.dist-info/licenses/LICENSE*'))
    if not licences:raise ValueError('Upstream licence is missing')
    shutil.copy2(licences[0],args.output/'LICENSE')
    (args.output/'source-inventory.json').write_text(json.dumps(inventory,indent=2))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--site-packages',type=Path,required=True);p.add_argument('--output',type=Path,required=True);main(p.parse_args())
