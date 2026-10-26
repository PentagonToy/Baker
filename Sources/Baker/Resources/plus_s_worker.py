# Copyright (c) 2024 PaddlePaddle Authors. All Rights Reserved.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# Modified by PentagonToy, 2026: focused PaddleX 3.7.2 preprocessing and
# text normalisation; NumPy replaces OpenCV; bounded per-request ORT inference.
"""PP-FormulaNet plus-S FP32 CPU inference without Paddle or training dependencies."""
from pathlib import Path
import json
import re
import time


class TokenLimitError(ValueError):
    pass


def prepare_image(path, max_pixels):
    import numpy as np
    from PIL import Image, ImageOps

    path = Path(path).resolve(strict=True)
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
    # Margin detection expects dark ink; preserve coloured/mixed panels.
    border = np.concatenate((gray[0], gray[-1], gray[:, 0], gray[:, -1]))
    if np.mean(border < 128) >= 0.9 and np.mean(gray < 128) >= 0.6 and int(gray.max()) - float(np.median(border)) >= 32:
        image = ImageOps.invert(image)
        gray = np.asarray(image.convert("L"))
    low, high = int(gray.min()), int(gray.max())
    if low == high:
        raise ValueError("No formula contrast was found in this image.")
    ys, xs = np.nonzero((gray - low) / (high - low) * 255 < 200)
    image = image.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    width, height = image.size
    size = (384, int(384 * height / width)) if width <= height else (int(384 * width / height), 384)
    if size[0] * size[1] > 8_000_000:
        raise ValueError("Crop this formula to a less extreme aspect ratio.")
    image = image.resize(size, Image.Resampling.BILINEAR)
    image.thumbnail((384, 384), Image.Resampling.BICUBIC)
    dx, dy = 384 - image.width, 384 - image.height
    image = ImageOps.expand(image, (dx // 2, dy // 2, dx - dx // 2, dy - dy // 2), fill=0)
    pixels = (np.asarray(image).astype(np.float32) * (1 / 255.0) - np.float32(0.7931)) / np.float32(0.1738)
    # Preserve PaddleX's BGR grey weights even though its incoming array is RGB.
    gray = pixels[:, :, 0] * np.float32(0.114) + pixels[:, :, 1] * np.float32(0.587) + pixels[:, :, 2] * np.float32(0.299)
    return np.ascontiguousarray(gray[None, None])


def normalise(text):
    """PaddleX UniMERNetDecode text normalisation, with its upstream semantics."""
    text_reg = r"(\\(operatorname|mathrm|text|mathbf)\s?\*? {.*?})"
    letter, noletter = r"[a-zA-Z]", r"[\W_^\d]"
    names = []
    for group in re.findall(text_reg, text):
        for name in re.findall(r"(\\[a-zA-Z]+)\s(?=\w)|\\[a-zA-Z]+\s(?=})", group[0]):
            if name not in ["\\operatorname", "\\mathrm", "\\text", "\\mathbf"] and name.strip():
                text = text.replace(name, name + "XXXXXXX").replace(" ", "")
                names.append(text)
    if names:
        text = re.sub(text_reg, lambda match: str(names.pop(0)), text)
    while True:
        previous = text
        text = re.sub(r"(?!\\ )(%s)\s+?(%s)" % (noletter, noletter), r"\1\2", text)
        text = re.sub(r"(?!\\ )(%s)\s+?(%s)" % (noletter, letter), r"\1\2", text)
        text = re.sub(r"(%s)\s+?(%s)" % (letter, noletter), r"\1\2", text)
        if text == previous:
            return text.replace("XXXXXXX", " ")


def decode_tokens(ids, tokenizer, max_tokens):
    from ftfy import fix_text

    values = [int(value) for value in ids]
    if 2 not in values or values.index(2) >= max_tokens:
        raise TokenLimitError("Formula exceeds the decode token limit; capture a smaller equation.")
    values = values[:values.index(2) + 1]
    text = tokenizer.decode(values, skip_special_tokens=True)
    text = re.sub(r'\\text\s*{([^{}]*[\u4e00-\u9fff]+[^{}]*)}', lambda match: match.group(1), text).replace('"', '')
    text = normalise(fix_text(text)).strip()
    if not text:
        raise ValueError("The formula engine returned no LaTeX text.")
    return {"latex": text, "model": "pp-formulanet-plus-s-fp32-ort-v1"}


def load_session(directory, threads):
    import onnxruntime as ort

    ort.disable_telemetry_events()
    options = ort.SessionOptions()
    options.intra_op_num_threads = threads
    options.inter_op_num_threads = 1
    options.enable_cpu_mem_arena = False
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    options.log_severity_level = 3
    for key, value in {"session.intra_op.allow_spinning": "0", "session.inter_op.allow_spinning": "0", "session.load_model_format": "ORT"}.items():
        options.add_session_config_entry(key, value)
    # Let ORT own its weight buffers. Python byte-borrowing options caused native
    # crashes under repeated allocation in the release runtime.
    session = ort.InferenceSession(str(directory / "formula_model.ort"), options, providers=["CPUExecutionProvider"])
    if [(item.name, item.type) for item in session.get_inputs()] != [("x", "tensor(float)")]:
        raise ValueError("Unsupported plus-S model interface.")
    return session


def recognise(image_path, settings):
    import numpy as np
    from tokenizers import Tokenizer

    deadline = time.monotonic() + settings["timeout_seconds"]
    directory = settings["model_dir"]
    config_path = directory / "config.json"
    if config_path.stat().st_size > 1_000_000:
        raise ValueError("plus-S metadata is too large.")
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if config != {"engine": "plus-s", "variant": "fp32-ort-v1", "max_sequence_length": 1024, "eos_token_id": 2, "input_size": [384, 384]}:
        raise ValueError("Unsupported plus-S model configuration.")
    pixels = prepare_image(image_path, settings["max_image_pixels"])
    tokenizer = Tokenizer.from_file(str(directory / "tokenizer.json"))
    session = load_session(directory, settings["threads"])
    if time.monotonic() >= deadline:
        raise TimeoutError("Formula recognition exceeded its time limit.")
    output = session.run(None, {"x": pixels})[0]
    if time.monotonic() >= deadline:
        raise TimeoutError("Formula recognition exceeded its time limit.")
    if output.ndim != 2 or output.shape[0] != 1 or not 1 <= output.shape[1] <= 1024 or output.dtype.kind not in "iu":
        raise ValueError("The plus-S decoder returned invalid tokens.")
    if np.any(output < 0) or np.any(output >= tokenizer.get_vocab_size(with_added_tokens=True)):
        raise ValueError("The plus-S decoder returned unknown tokens.")
    # Exported graph provides token IDs only; do not invent a confidence score.
    return decode_tokens(output[0], tokenizer, settings["max_new_tokens"])
