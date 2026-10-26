"""Prepare Baker's validated MFR MLP-only INT8 variant from pinned local weights."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys

VARIANT = 'mlp-int8-v1'


def fingerprint(path):
    return {'bytes': path.stat().st_size, 'sha256': hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()}


def prepare(configuration, manifest, destination):
    import onnx
    import onnxruntime
    from onnxruntime.quantization import QuantType, quantize_dynamic
    if (onnx.__version__, onnxruntime.__version__) != ('1.23.2', '1.31.0'):
        raise ValueError('Use the validated ONNX 1.23.2 / ONNX Runtime 1.31.0 build environment.')
    source = json.loads(configuration.read_text())
    def resolve(value):
        p = Path(value)
        return p.resolve() if p.is_absolute() else (configuration.parent / p).resolve()
    model_root = resolve(source['mfr'])
    canonical = json.loads(manifest.read_text())
    for name, expected in canonical['files'].items():
        if fingerprint(model_root / name) != expected:
            raise ValueError('Pinned source model mismatch: ' + name)
    identity = hashlib.sha256(configuration.read_bytes() + manifest.read_bytes() + Path(__file__).read_bytes()).hexdigest()
    marker = destination / 'optimization.json'
    if destination.exists():
        if marker.is_file() and json.loads(marker.read_text()).get('identity') == identity:
            for name, expected in json.loads((destination/'formula-model.json').read_text())['files'].items():
                if fingerprint(destination/'mfr'/name) != expected: raise ValueError('Optimized model cache changed: ' + name)
            return
        raise ValueError('Use a fresh optimization destination; existing files are preserved.')
    staging = destination.with_name(destination.name + '.preparing')
    if staging.exists(): raise ValueError('Inspect the interrupted optimization directory: ' + str(staging))
    staging.mkdir(parents=True)
    try:
        mfr = staging/'mfr'; mfr.mkdir()
        for name in canonical['files']:
            if name != 'encoder_model.onnx': shutil.copy2(model_root/name, mfr/name)
        graph = onnx.load(str(model_root/'encoder_model.onnx'))
        nodes = [n.name for n in graph.graph.node if n.op_type == 'MatMul' and '/attention/' not in n.name]
        if len(nodes) != 24: raise ValueError('Unexpected encoder architecture; revalidate quantization before building.')
        quantize_dynamic(str(model_root/'encoder_model.onnx'), str(mfr/'encoder_model.onnx'),
                         nodes_to_quantize=nodes, op_types_to_quantize=['MatMul'], per_channel=True, weight_type=QuantType.QInt8)
        recipe = {'variant':VARIANT, 'source_repository':canonical['repository'], 'source_revision':canonical['revision'],
                  'source_encoder':canonical['files']['encoder_model.onnx'], 'onnx':onnx.__version__,
                  'onnxruntime':onnxruntime.__version__, 'quantized_nodes':nodes,
                  'attention':'original FP32', 'decoder':'original FP32'}
        (mfr/'baker-model.json').write_text(json.dumps(recipe,indent=2)+'\n')
        files = {name:fingerprint(mfr/name) for name in [*canonical['files'], 'baker-model.json']}
        model_manifest = {**canonical, 'variant':VARIANT, 'bundledOnly':True, 'files':files}
        (staging/'formula-model.json').write_text(json.dumps(model_manifest,indent=2)+'\n')
        mapped = {}
        for name, expected in source['files'].items():
            p = resolve(name)
            if not p.is_relative_to(model_root): mapped[str(p)] = expected
        for name, expected in files.items(): mapped[str(destination/'mfr'/name)] = expected
        source.update(models=str(resolve(source['models'])), mfr=str(destination/'mfr'), files=mapped,
                      formula_manifest=str(destination/'formula-model.json'))
        (staging/'document-engine.json').write_text(json.dumps(source,indent=2)+'\n')
        (staging/'optimization.json').write_text(json.dumps({'identity':identity, **recipe},indent=2)+'\n')
        staging.rename(destination)
    except BaseException:
        if staging.exists(): shutil.rmtree(staging)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--configuration',type=Path,required=True)
    parser.add_argument('--manifest',type=Path,required=True)
    parser.add_argument('--destination',type=Path,required=True)
    args = parser.parse_args()
    prepare(args.configuration.resolve(),args.manifest.resolve(),args.destination.resolve())
