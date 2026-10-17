"""Create a local mixed-precision candidate; preserve the upstream checkpoint."""
import argparse
import os
from pathlib import Path


def main(args):
    os.environ.update(HF_HUB_OFFLINE='1',HF_HUB_DISABLE_TELEMETRY='1')
    from mlx_vlm.convert import convert
    def precision(path,module):
        if not hasattr(module,'to_quantized') or not hasattr(module,'weight') or module.weight.ndim!=2:return False
        if module.weight.shape[-1]%64:return False
        bits=args.vision_bits if 'vision' in path else args.language_bits
        return {'bits':bits,'group_size':64,'mode':'affine'}
    if args.output.exists():raise ValueError('Candidate directory already exists')
    convert(hf_path=str(args.source),mlx_path=str(args.output),quantize=True,q_bits=args.language_bits,q_group_size=64,quant_predicate=precision,trust_remote_code=False)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--language-bits',type=int,choices=[4,8],default=4);p.add_argument('--vision-bits',type=int,choices=[4,8],default=8);main(p.parse_args())
