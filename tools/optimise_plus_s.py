"""Convert the pinned Paddle plus-S graph to FP32 CPU ORT; no training or quantisation."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import re

REVISION = '3d46f557e3a1752f4bf81202395af3b5ecfadfd2'


def fingerprint(path):
    with path.open('rb') as stream:
        return {'bytes': path.stat().st_size, 'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}


def convert(source, destination):
    import onnx
    from onnx import helper, TensorProto
    import onnxruntime as ort
    from tokenizers import Tokenizer, AddedToken

    exporter = subprocess.run(['paddle2onnx', '--version'], capture_output=True, text=True, check=True)
    version = re.search(r'paddle2onnx-([0-9.]+)', exporter.stdout + exporter.stderr)
    if not version or version.group(1) != '2.1.0' or onnx.__version__ != '1.17.0' or ort.__version__ != '1.23.2':
        raise ValueError('Use Paddle2ONNX 2.1.0, ONNX 1.17.0 and ONNX Runtime 1.23.2 for this conversion recipe')
    pins = json.loads((Path(__file__).parent / 'plus-s-upstream.json').read_text())
    for name, expected in pins['files'].items():
        if fingerprint(source / name) != expected:
            raise ValueError('Pinned plus-S input differs: ' + name)
    if destination.exists():
        raise ValueError('Choose a fresh conversion directory')
    destination.mkdir(parents=True)
    exported = destination / 'export.onnx'
    subprocess.run(['paddle2onnx', '--model_dir', str(source), '--model_filename', 'inference.json', '--params_filename', 'inference.pdiparams', '--save_file', str(exported), '--opset_version', '17', '--optimize_tool', 'None'], check=True)
    model = onnx.load(str(exported))
    changes = []

    def repair(graph):
        for node in graph.node:
            for attr in node.attribute:
                if attr.type == onnx.AttributeProto.GRAPH:
                    repair(attr.g)
            if node.name != 'If.3':
                continue
            for attr in node.attribute:
                if attr.type != onnx.AttributeProto.GRAPH:
                    continue
                branch = attr.g
                if len(branch.output) != 1 or branch.output[0].type.tensor_type.elem_type != TensorProto.FLOAT or len(branch.output[0].type.tensor_type.shape.dim):
                    raise ValueError('Unexpected exported scalar branch')
                output = branch.output[0]
                name = output.name
                branch.initializer.append(helper.make_tensor(name + '_scalar_shape', TensorProto.INT64, [0], []))
                branch.node.append(helper.make_node('Reshape', [name, name + '_scalar_shape'], [name + '_scalar_output'], name='BakerScalar_' + attr.name))
                output.name = name + '_scalar_output'
                changes.append({'node': node.name, 'branch': attr.name, 'change': 'Reshape a single-element loop carry to its declared scalar shape; values unchanged'})

    repair(model.graph)
    if len(changes) != 2:
        raise ValueError('Expected exactly two pinned scalar shape repairs')
    onnx.checker.check_model(model)
    repaired = destination / 'repaired.onnx'
    onnx.save(model, str(repaired))
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    options.enable_cpu_mem_arena = False
    # Exclude layout/hardware-specific NCHWc optimisations from distribution.
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_EXTENDED
    options.add_session_config_entry('session.save_model_format', 'ORT')
    options.optimized_model_filepath = str(destination / 'formula_model.ort')
    session = ort.InferenceSession(str(repaired), options, providers=['CPUExecutionProvider'])
    del session
    character = json.loads((source / 'config.json').read_text())['PostProcess']['character_dict']
    tokenizer = Tokenizer.from_str(json.dumps(character['fast_tokenizer_file']))
    tokens = [AddedToken(**v) for k, v in sorted(character['tokenizer_config_file']['added_tokens_decoder'].items(), key=lambda pair: int(pair[0]))]
    tokenizer.add_special_tokens([token for token in tokens if token.special])
    tokenizer.save(str(destination / 'tokenizer.json'))
    config = {'engine': 'plus-s', 'variant': 'fp32-ort-v1', 'max_sequence_length': 1024, 'eos_token_id': 2, 'input_size': [384, 384]}
    (destination / 'config.json').write_text(json.dumps(config, indent=2) + '\n')
    provenance = {'repository': pins['repository'], 'revision': REVISION, 'inputs': pins['files'], 'repairs': changes, 'opsets': [{'domain': entry.domain, 'version': entry.version} for entry in model.opset_import], 'optimisation': 'ORT_ENABLE_EXTENDED, CPUExecutionProvider; FP32; no layout optimisations, quantisation or training', 'paddle2onnx': version.group(1), 'onnx': onnx.__version__, 'onnxruntime': ort.__version__, 'outputs': {name: fingerprint(destination / name) for name in ['formula_model.ort', 'tokenizer.json', 'config.json']}}
    (destination / 'conversion.json').write_text(json.dumps(provenance, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    convert(args.source.resolve(), args.destination.resolve())
