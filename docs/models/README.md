# Formula model downloads

Baker downloads formula models separately from the app. Choose one in Settings → Formula. Recognition runs on this Mac after installation; switching models does not upload captures.

| Package | Model files | Changes | Licence |
| --- | --- | --- | --- |
| Pix2Text MFR 1.5 · MLP INT8 v1 | About 77 MB | Quantises 24 encoder feed-forward MatMul nodes per channel; attention and decoder remain FP32 | MIT |
| Texo transfer · ONNX v1 | About 100 MB | Upstream encoder, initial decoder and cached decoder, unchanged; no further quantisation | AGPL-3.0 |
| PP-FormulaNet plus-S · FP32 ORT v1 | About 236 MB | Paddle-to-ONNX export, two scalar-shape repairs and extended CPU graph optimisation; no quantisation | Apache-2.0 |

These sizes exclude notices, source material and archive compression. Model scores are not verified accuracy. All three models can misread signs, derivatives and array layouts. The [recognition notes](../help/recognition.md) describe the small development comparison and its limits.

## Contents and provenance

Each archive contains the model files, upstream model card, licence texts, a provenance record and relevant Baker source. The Texo archive also includes a pinned upstream source snapshot. `SHA256SUMS` covers the release assets; the app pins the archive and file hashes independently before installing into Application Support. Archives contain no account information, captures, local configuration or executable runtime.

Pix2Text comes from [`breezedeus/pix2text-mfr-1.5`](https://huggingface.co/breezedeus/pix2text-mfr-1.5), revision `1cef9f0bdcd6a4c63df7de1311fb0894593340cc`. Baker's `baker-model.json` records the original encoder hash, changed nodes and ONNX tool versions. The included optimisation script checks the pinned inputs before conversion. The original model card and MIT notice remain intact.

Texo comes from [`alephpi/FormulaNet`](https://huggingface.co/alephpi/FormulaNet), revision `b2668efe5112082846fde4d446b9bfaab3989533`. The upstream card links to [Texo](https://github.com/alephpi/Texo); the included source snapshot is identified separately in `PROVENANCE.json`. That snapshot supplies upstream inference and training code, but the model card does not identify its exact training-source commit. Baker does not claim to reproduce the training run or publish a newly trained model.

PP-FormulaNet plus-S comes from [`PaddlePaddle/PP-FormulaNet_plus-S`](https://huggingface.co/PaddlePaddle/PP-FormulaNet_plus-S/tree/3d46f557e3a1752f4bf81202395af3b5ecfadfd2), revision `3d46f557e3a1752f4bf81202395af3b5ecfadfd2`. Its card declares Apache-2.0. The archive retains that card, the PaddleX 3.7.2 processor source and Apache licence, modification notices, pinned input hashes and a conversion recipe. No captures, training data or account information are included.

`tools/optimise_plus_s.py` exports with Paddle2ONNX 2.1.0 (opset 18), reshapes the two single-element `If.3` branch outputs to their declared scalar shape and serialises FP32 weights with ONNX Runtime 1.23.2 `ORT_ENABLE_EXTENDED`. The distribution excludes hardware-specific layout optimisation; the runtime may optimise for its own CPU. The worker bounds input size, uses two non-spinning threads and exits after each request. ORT owns its weight buffers; experimental Python byte-borrowing options were rejected after native crashes. There is no additional training or quantisation. The smaller mixed-INT8 experiment introduced content errors and is not distributed.

The focused worker adapts PaddleX crop, resize, pad and text normalisation, replaces OpenCV with NumPy and serialises the upstream tokenizer. Transparent inputs are composited on white, predominantly dark captures are inverted, and extreme aspect ratios are rejected. Text repair uses the separately licensed `ftfy` runtime dependency. The 158-input development comparison preserved every native FP32 prediction; this establishes compatibility on those inputs, not error-free OCR. `CONVERSION.json`, `VALIDATION.json` and `PROVENANCE.json` identify the packaged files and test conditions. plus-S exports token IDs without probabilities, so Baker does not display a model score for it.

## Redistribution

Retain the original copyright, licence notices and model cards. Pix2Text's MIT terms permit redistribution and modification with those notices. The Texo package retains AGPL-3.0 terms and includes the corresponding published model files, upstream source snapshot and Baker integration source. Preserve access to that source when redistributing the package, and publish applicable modifications under the required terms. The LGPL exception granted to another named application does not apply to Baker. The plus-S model and adapted PaddleX code retain Apache-2.0, including attribution and modification notices; Baker integration source retains AGPL-3.0-only. Dependencies and base models retain their own notices; packaging does not replace their licences with Baker's.

## Maintenance

Use `tools/package_formula_models.py` with verified local model folders and the pinned Texo source archive. It produces immutable, versioned assets and app descriptors without uploading them. Publish a new model release when files change; do not overwrite an existing asset under the same version. `tools/package_plus_s.py` packages verified conversion outputs with the pinned upstream card and processor source, notices and a passing validation summary. `formula-models-v1.1.0` adds plus-S; the Pix2Text and Texo assets remain pinned to `formula-models-v1.0.0`. Model release tags use `formula-models-v…` and are separate from app versions.
