"""Baker-owned local-only MFR ONNX inference; models are provisioned separately."""
import contextlib
import json
import os
from pathlib import Path
import sys
import threading
import time


class FormulaConfigurationError(ValueError):
    pass


class FormulaTokenLimitError(ValueError):
    pass


def error_payload(error):
    code = "formula_token_limit" if isinstance(error, FormulaTokenLimitError) else "recognition_timeout" if isinstance(error, TimeoutError) else "model_not_ready" if isinstance(error, FormulaConfigurationError) else "recognition_failed"
    return {"error": str(error), "error_code": code}


def read_json(path):
    if path.stat().st_size > 1_000_000:
        raise ValueError(f"Metadata is too large: {path.name}.")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path.name} must contain a JSON object.")
    return value


def read_settings(path):
    config = read_json(Path(path).resolve(strict=True))
    allowed = {"model_dir", "threads", "max_new_tokens", "timeout_seconds", "max_image_pixels"}
    if set(config) - allowed:
        raise ValueError("Unknown formula configuration fields: " + ", ".join(sorted(set(config) - allowed)))
    location = config.get("model_dir")
    if not isinstance(location, str) or not Path(location).is_absolute():
        raise ValueError("Set model_dir to an absolute, prepared local model directory.")
    directory = Path(location).resolve(strict=True)
    if not directory.is_dir():
        raise ValueError("model_dir must be a prepared local model directory.")
    for name in ("encoder_model.onnx", "decoder_model.onnx", "tokenizer.json", "preprocessor_config.json", "config.json"):
        if not (directory / name).is_file():
            raise ValueError(f"The local model is incomplete: missing {name}.")
    settings = {"model_dir": directory}
    bounds = {"threads": (2, 1, 2), "max_new_tokens": (256, 1, 512), "timeout_seconds": (45, 1, 120), "max_image_pixels": (12_000_000, 1, 32_000_000)}
    for name, (default, lower, upper) in bounds.items():
        value = config.get(name, default)
        if type(value) is not int or not lower <= value <= upper:
            raise ValueError(f"{name} must be an integer from {lower} to {upper}.")
        settings[name] = value
    return settings


def prepare_image(path, max_pixels, processor):
    import numpy as np
    from PIL import Image

    expected = {"size": {"height": 384, "width": 384}, "do_resize": True, "do_center_crop": False, "resample": 3, "do_rescale": True, "do_normalize": True, "image_mean": [0.5, 0.5, 0.5], "image_std": [0.5, 0.5, 0.5]}
    if any(processor.get(key) != value for key, value in expected.items()):
        raise ValueError("Unsupported model preprocessing metadata; prepare the pinned MFR 1.5 model.")
    if abs(processor.get("rescale_factor", 0) - 1 / 255) > 1e-12:
        raise ValueError("Unsupported model pixel scale.")
    source = Path(path).resolve(strict=True)
    if source.stat().st_size > 32_000_000:
        raise ValueError("Formula image exceeds the 32 MB file limit.")
    with Image.open(source) as original:
        if original.width * original.height > max_pixels or min(original.size) < 1:
            raise ValueError(f"Formula image exceeds the {max_pixels:,} pixel limit.")
        if getattr(original, "n_frames", 1) != 1:
            raise ValueError("Choose a still image containing one formula.")
        if original.mode in ("RGBA", "LA") or "transparency" in original.info:
            rgba = original.convert("RGBA")
            image = Image.new("RGB", rgba.size, "white")
            image.paste(rgba, mask=rgba.getchannel("A"))
        else:
            image = original.convert("RGB")
        pixels = np.asarray(image.resize((384, 384), Image.Resampling.BICUBIC), dtype=np.float32) / np.float32(255)
        pixels = (pixels - np.float32(0.5)) / np.float32(0.5)
        return np.ascontiguousarray(pixels.transpose(2, 0, 1)[None])


def decode_tokens(decoder, hidden, tokenizer, model, max_tokens, deadline, fallback_max_tokens=None):
    import numpy as np

    if (model.get("decoder_start_token_id"), model.get("eos_token_id"), model.get("pad_token_id")) != (1, 2, 0):
        raise ValueError("Unsupported formula model special tokens.")
    generated = [1]
    log_probabilities = []
    minimum_probability = 1.0
    ambiguous_count = 0
    # Continue only an exhausted default budget, with the same decoder/hidden states.
    # Never reload models or reset the original deadline for a long equation.
    budget = max_tokens if fallback_max_tokens is None else fallback_max_tokens
    if not 1 <= max_tokens <= budget <= 512:
        raise ValueError("Formula decode budgets must remain within 512 tokens.")
    for _ in range(budget):
        if time.monotonic() >= deadline:
            raise TimeoutError("Formula recognition exceeded its time limit.")
        logits = decoder.run(["logits"], {"input_ids": np.asarray([generated], dtype=np.int64), "encoder_hidden_states": hidden})[0]
        if logits.shape != (1, len(generated), 1868) or not np.isfinite(logits[0, -1]).all():
            raise ValueError("The formula decoder returned invalid logits.")
        token = int(logits[0, -1].argmax())
        if token == 2:
            latex = tokenizer.decode(generated[1:], skip_special_tokens=True).strip()
            if not latex:
                raise ValueError("The formula engine returned no LaTeX text.")
            confidence = float(np.exp(np.mean(log_probabilities)))
            return {"latex": latex, "confidence": confidence, "confidence_method": "geometric_mean_token_probability_v1", "model": "pix2text-mfr-1.5-pinned", "diagnostics": {"tokenCount": len(log_probabilities), "minimumTokenProbability": minimum_probability, "ambiguousTokenCount": ambiguous_count}}
        # Stable log-softmax of emitted content tokens; excludes start/end tokens.
        scores = logits[0, -1].astype(np.float64)
        shifted = scores - scores.max()
        log_probabilities.append(float(shifted[token] - np.log(np.exp(shifted).sum())))
        probability = float(np.exp(log_probabilities[-1]))
        minimum_probability = min(minimum_probability, probability)
        ambiguous_count += int(probability < 0.8)  # diagnostic threshold, not an accuracy category
        generated.append(token)
    raise FormulaTokenLimitError("Formula exceeds the decode token limit; capture a smaller equation.")



def model_identity(directory):
    artifact = directory / "baker-model.json"
    if not artifact.is_file():
        return "pix2text-mfr-1.5-pinned"
    metadata = read_json(artifact)
    if metadata.get("variant") != "mlp-int8-v1":
        raise ValueError("Unsupported optimized formula model variant.")
    return "pix2text-mfr-1.5-mlp-int8-v1"


def recognise(image_path, settings):
    directory = settings["model_dir"]
    deadline = time.monotonic() + settings["timeout_seconds"]
    processor, model = read_json(directory / "preprocessor_config.json"), read_json(directory / "config.json")
    identity = model_identity(directory)
    # Check dimensions before loading either model session.
    pixels = prepare_image(image_path, settings["max_image_pixels"], processor)
    import onnxruntime as ort
    ort.disable_telemetry_events()
    from tokenizers import Tokenizer

    options = ort.SessionOptions()
    options.intra_op_num_threads = settings["threads"]
    options.inter_op_num_threads = 1
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    options.enable_cpu_mem_arena = False
    options.log_severity_level = 3
    encoder = ort.InferenceSession(str(directory / "encoder_model.onnx"), sess_options=options, providers=["CPUExecutionProvider"])
    if [(item.name, item.type) for item in encoder.get_inputs()] != [("pixel_values", "tensor(float)")]:
        raise ValueError("Unsupported formula encoder interface.")
    tokenizer = Tokenizer.from_file(str(directory / "tokenizer.json"))
    hidden = encoder.run(["last_hidden_state"], {"pixel_values": pixels})[0]
    if hidden.shape != (1, 578, 384):
        raise ValueError("Unsupported formula encoder output.")
    # Hidden states own their NumPy buffer; encoder weights are no longer needed.
    del encoder, pixels
    import gc
    gc.collect()
    decoder = ort.InferenceSession(str(directory / "decoder_model.onnx"), sess_options=options, providers=["CPUExecutionProvider"])
    if [(item.name, item.type) for item in decoder.get_inputs()] != [("input_ids", "tensor(int64)"), ("encoder_hidden_states", "tensor(float)")]:
        raise ValueError("Unsupported formula decoder interface.")
    result = decode_tokens(decoder, hidden, tokenizer, model, settings["max_new_tokens"], deadline, fallback_max_tokens=512 if settings["max_new_tokens"] == 256 else None)
    result["model"] = identity
    return result


def main():
    os.environ["TOKENIZERS_PARALLELISM"] = "false"
    os.environ["OMP_NUM_THREADS"] = "2"
    os.environ["OPENBLAS_NUM_THREADS"] = "2"
    os.environ["VECLIB_MAXIMUM_THREADS"] = "2"
    output, output_lock, finished = sys.stdout, threading.Lock(), threading.Event()
    watchdog = None

    def emit(payload):
        with output_lock:
            if finished.is_set():
                return False
            print(json.dumps(payload, ensure_ascii=False), file=output, flush=True)
            finished.set()
            return True

    def timed_out():
        # A process deadline also bounds time spent inside native model calls.
        if emit(error_payload(TimeoutError("Formula recognition exceeded its time limit."))):
            os._exit(1)

    try:
        if len(sys.argv) != 3:
            raise ValueError("Usage: formula_worker.py IMAGE CONFIG.json")
        try:
            settings = read_settings(sys.argv[2])
        except (OSError, ValueError) as error:
            raise FormulaConfigurationError(str(error)) from error
        watchdog = threading.Timer(settings["timeout_seconds"], timed_out)
        watchdog.daemon = True
        watchdog.start()
        with contextlib.redirect_stdout(sys.stderr):
            result = recognise(sys.argv[1], settings)
        emit(result)
        return 0
    except Exception as error:
        emit(error_payload(error))
        return 1
    finally:
        if watchdog is not None:
            watchdog.cancel()


if __name__ == "__main__":
    raise SystemExit(main())
