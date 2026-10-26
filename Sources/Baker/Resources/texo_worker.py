"""Bounded CPU inference for the pinned Texo transfer model; no training dependencies."""
import gc
import time


class TokenLimitError(ValueError):
    pass


def prepare_image(path, max_pixels):
    import numpy as np
    from PIL import Image, ImageOps

    if path.stat().st_size > 32_000_000:
        raise ValueError("Formula image exceeds the 32 MB file limit.")
    with Image.open(path) as original:
        if original.width * original.height > max_pixels or min(original.size) < 1:
            raise ValueError("Formula image exceeds the pixel limit.")
        if getattr(original, "n_frames", 1) != 1:
            raise ValueError("Choose a still image containing one formula.")
        rgba = original.convert("RGBA")
        image = Image.new("RGB", rgba.size, "white")
        image.paste(rgba, mask=rgba.getchannel("A"))
    gray = np.asarray(image.convert("L"))
    # Texo expects dark ink. A dark capture otherwise makes margin detection
    # select the background rather than the equation. Leave mixed panels alone.
    border = np.concatenate((gray[0], gray[-1], gray[:, 0], gray[:, -1]))
    if np.mean(border < 128) >= 0.9 and np.mean(gray < 128) >= 0.6 and int(gray.max()) - float(np.median(border)) >= 32:
        image = ImageOps.invert(image)
        gray = np.asarray(image.convert("L"))
    low, high = int(gray.min()), int(gray.max())
    if low == high:
        raise ValueError("No formula contrast was found in this image.")
    ys, xs = np.nonzero((gray.astype(np.float32) - low) / (high - low) * 255 < 200)
    image = image.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    width, height = image.size
    size = (384, int(384 * height / width)) if width <= height else (int(384 * width / height), 384)
    if size[0] * size[1] > 8_000_000:
        raise ValueError("Crop this formula to a less extreme aspect ratio.")
    image = image.resize(size, Image.Resampling.BILINEAR)
    image.thumbnail((384, 384), Image.Resampling.BICUBIC)
    dx, dy = 384 - image.width, 384 - image.height
    image = ImageOps.expand(image, (dx // 2, dy // 2, dx - dx // 2, dy - dy // 2), fill=0)
    # OpenCV's fixed-point RGB-to-grey coefficients, without shipping OpenCV.
    rgb = np.asarray(image).astype(np.uint32)
    gray = ((rgb[:, :, 0] * 9798 + rgb[:, :, 1] * 19235 + rgb[:, :, 2] * 3735 + 16384) >> 15).astype(np.uint8)
    pixels = np.repeat(gray[:, :, None], 3, axis=2).astype(np.float32)
    pixels = (pixels - np.float32(0.7931 * 255)) * np.float32(1 / (0.1738 * 255))
    return np.ascontiguousarray(pixels.transpose(2, 0, 1)[None])


def recognise(image_path, settings):
    from pathlib import Path
    import numpy as np
    import onnxruntime as ort
    from tokenizers import Tokenizer

    deadline = time.monotonic() + settings["timeout_seconds"]
    pixels = prepare_image(Path(image_path).resolve(strict=True), settings["max_image_pixels"])
    directory = settings["model_dir"]
    import json
    metadata = directory / "config.json"
    if metadata.stat().st_size > 1_000_000:
        raise ValueError("Texo metadata is too large.")
    config = json.loads(metadata.read_text(encoding="utf-8"))
    decoder_config = config.get("decoder", {})
    if [decoder_config.get(k) for k in ["vocab_size", "bos_token_id", "eos_token_id", "pad_token_id", "decoder_layers", "d_model"]] != [687, 0, 2, 1, 2, 384]:
        raise ValueError("Unsupported Texo model configuration.")
    ort.disable_telemetry_events()
    options = ort.SessionOptions()
    options.intra_op_num_threads = settings["threads"]
    options.inter_op_num_threads = 1
    options.enable_cpu_mem_arena = False
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    options.add_session_config_entry("session.intra_op.allow_spinning", "0")
    options.add_session_config_entry("session.inter_op.allow_spinning", "0")
    options.log_severity_level = 3

    def session(name):
        if time.monotonic() >= deadline:
            raise TimeoutError("Formula recognition exceeded its time limit.")
        return ort.InferenceSession(str(directory / name), sess_options=options, providers=["CPUExecutionProvider"])

    encoder = session("encoder_model.onnx")
    hidden = encoder.run(["last_hidden_state"], {"pixel_values": pixels})[0]
    if hidden.shape != (1, 144, 2048) or not np.isfinite(hidden).all():
        raise ValueError("Unsupported Texo encoder output.")
    del encoder, pixels
    gc.collect()
    tokenizer = Tokenizer.from_file(str(directory / "tokenizer.json"))
    decoder = session("decoder_model.onnx")
    names = [item.name for item in decoder.get_outputs()]
    outputs = decoder.run(None, {"input_ids": np.array([[0]], dtype=np.int64), "encoder_hidden_states": hidden})
    cache = {name.replace("present.", "past_key_values.", 1): value for name, value in zip(names[1:], outputs[1:])}
    expected = {f"past_key_values.{layer}.{kind}.{part}" for layer in range(2) for kind in ["decoder", "encoder"] for part in ["key", "value"]}
    if set(cache) != expected:
        raise ValueError("Unsupported Texo decoder cache interface.")
    logits = outputs[0]
    del decoder, hidden, outputs
    gc.collect()
    cached_decoder = None
    generated, log_probabilities = [], []
    minimum_probability, ambiguous_count = 1.0, 0
    for step in range(settings["max_new_tokens"] + 1):
        if time.monotonic() >= deadline:
            raise TimeoutError("Formula recognition exceeded its time limit.")
        if logits.shape != (1, 1, 687) or not np.isfinite(logits).all():
            raise ValueError("The Texo decoder returned invalid logits.")
        token = int(logits[0, -1].argmax())
        if token == 2:
            latex = tokenizer.decode(generated, skip_special_tokens=True).strip()
            if not latex:
                raise ValueError("The formula engine returned no LaTeX text.")
            return {"latex": latex, "model": "texo-transfer-b2668efe-cpu-v1", "confidence": float(np.exp(np.mean(log_probabilities))),
                    "confidence_method": "geometric_mean_token_probability_v1", "diagnostics": {"tokenCount": len(generated), "minimumTokenProbability": minimum_probability, "ambiguousTokenCount": ambiguous_count}}
        if step == settings["max_new_tokens"]:
            break
        generated.append(token)
        shifted = logits[0, -1].astype(np.float64) - float(logits.max())
        probability_log = float(shifted[token] - np.log(np.exp(shifted).sum()))
        log_probabilities.append(probability_log)
        probability = float(np.exp(probability_log))
        minimum_probability = min(minimum_probability, probability)
        ambiguous_count += int(probability < 0.8)
        if cached_decoder is None:
            cached_decoder = session("decoder_with_past_model.onnx")
        names = [item.name for item in cached_decoder.get_outputs()]
        outputs = cached_decoder.run(None, {"input_ids": np.array([[token]], dtype=np.int64), **cache})
        for name, value in zip(names[1:], outputs[1:]):
            cache[name.replace("present.", "past_key_values.", 1)] = value
        logits = outputs[0]
    raise TokenLimitError("Formula exceeds the decode token limit; capture a smaller equation.")
