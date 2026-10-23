# Formula model downloads

Baker downloads formula models separately from the app. Choose one in Settings → Formula. Recognition runs on this Mac after installation; switching models does not upload captures.

| Package | Model files | Changes | Licence |
| --- | --- | --- | --- |
| Pix2Text MFR 1.5 · MLP INT8 v1 | About 77 MB | Quantises 24 encoder feed-forward MatMul nodes per channel; attention and decoder remain FP32 | MIT |
| Texo transfer · ONNX v1 | About 100 MB | Upstream encoder, initial decoder and cached decoder, unchanged; no further quantisation | AGPL-3.0 |

These sizes exclude notices, source material and archive compression. Model scores are not verified accuracy. Both models can misread signs, derivatives and array layouts. The [recognition notes](../help/recognition.md) describe the small development comparison and its limits.

## Contents and provenance

Each archive contains the model files, upstream model card, licence texts, a provenance record and relevant Baker source. The Texo archive also includes a pinned upstream source snapshot. `SHA256SUMS` covers the release assets; the app pins the archive and file hashes independently before installing into Application Support. Archives contain no account information, captures, local configuration or executable runtime.

Pix2Text comes from [`breezedeus/pix2text-mfr-1.5`](https://huggingface.co/breezedeus/pix2text-mfr-1.5), revision `1cef9f0bdcd6a4c63df7de1311fb0894593340cc`. Baker's `baker-model.json` records the original encoder hash, changed nodes and ONNX tool versions. The included optimisation script checks the pinned inputs before conversion. The original model card and MIT notice remain intact.

Texo comes from [`alephpi/FormulaNet`](https://huggingface.co/alephpi/FormulaNet), revision `b2668efe5112082846fde4d446b9bfaab3989533`. The upstream card links to [Texo](https://github.com/alephpi/Texo); the included source snapshot is identified separately in `PROVENANCE.json`. That snapshot supplies upstream inference and training code, but the model card does not identify its exact training-source commit. Baker does not claim to reproduce the training run or publish a newly trained model.

## Redistribution

Retain the original copyright, licence notices and model cards. Pix2Text's MIT terms permit redistribution and modification with those notices. The Texo package retains AGPL-3.0 terms and includes the corresponding published model files, upstream source snapshot and Baker integration source. Preserve access to that source when redistributing the package, and publish applicable modifications under the required terms. The LGPL exception granted to another named application does not apply to Baker. Dependencies and base models retain their own notices; packaging does not replace their licences with Baker's.

## Maintenance

Use `tools/package_formula_models.py` with verified local model folders and the pinned Texo source archive. It produces immutable, versioned assets and app descriptors without uploading them. Publish a new model release when files change; do not overwrite an existing asset under the same version. Model release tags use `formula-models-v…` and are separate from app versions.
