# Models and references

Baker combines small task-specific engines with native macOS recognition. Baker mode processes captures and PDFs locally without an OCR API or server. The Unreleased [Mathpix option](settings.md#mathpix-and-usage-unreleased) sends selected formulas and PDFs to the signed-in Mathpix account.

For app-neutral local clients, see the [headless recognition adapter](adapter.md). It is independent of any reader integration.

## Current engines

| Task | Engine | Baker configuration |
| --- | --- | --- |
| Screenshot text | Apple Vision; [Tesseract](https://github.com/tesseract-ocr/tesseract) with [tessdata_fast](https://github.com/tesseract-ocr/tessdata_fast) when Finnish or a language unavailable in Apple Vision is selected | Up to five selected languages; native text OCR stays separate from the document model |
| Screenshot or imported formula image | [Pix2Text MFR 1.5](https://huggingface.co/breezedeus/pix2text-mfr-1.5), from [Pix2Text](https://github.com/breezedeus/Pix2Text) | ONNX Runtime; downloadable model with INT8 encoder feed-forward matrices and FP32 attention/decoder; sequential encoder/decoder sessions |
| Formula images, optional Texo model | [Texo](https://github.com/alephpi/Texo), [FormulaNet weights](https://huggingface.co/alephpi/FormulaNet) | Pinned 687-token transfer model; CPU ONNX with incremental decoder cache |
| Formula images, optional plus-S model | [PP-FormulaNet plus-S](https://huggingface.co/PaddlePaddle/PP-FormulaNet_plus-S) | FP32 CPU ORT; bounded 1,024-token graph; no Paddle runtime or confidence score |
| PDF layout | [DocLayout-YOLO](https://github.com/opendatalab/DocLayout-YOLO), [DocStructBench weights](https://huggingface.co/juliozhao/DocLayout-YOLO-DocStructBench) | ONNX export with 1024-pixel square input |
| PDF text, formula and table regions requiring recognition | [GLM-OCR](https://github.com/zai-org/GLM-OCR), [model weights](https://huggingface.co/zai-org/GLM-OCR) | MLX; 4-bit language weights, 8-bit vision linear layers and a small Baker LoRA adapter |
| PDF text and export | [PyMuPDF](https://github.com/pymupdf/PyMuPDF), Baker reconstruction and exporters | Reuse reliable PDF characters; reconstruct reading order, authors, equation labels, table spans and figure references |

The PDF model loads only when a region needs it. A usable native-text page can avoid loading GLM-OCR. The document process exits after each conversion. Individual formula images use the selected downloadable Pix2Text, Texo or plus-S model. They run per request and do not remain loaded while Baker is idle.

The document runtime uses [MLX](https://github.com/ml-explore/mlx) and extracted inference definitions from [MLX-VLM 0.7.8](https://github.com/Blaizzy/mlx-vlm). It excludes PyTorch, Transformers and the general MLX-VLM launcher. This build uses Metal on Apple Silicon; it does not claim Neural Engine acceleration. Its MLX library requires macOS 26.2 or later.

## Formula comparison

A development comparison on 24 October 2026 tested 72 authored images: 24 formula families rendered as clean, small-serif and slide-JPEG variants. A pass required preserved mathematical content and notation, plus valid LaTeX syntax; presentation-only differences were accepted.

| Engine | Content and syntax passed | Simple formula response |
| --- | ---: | ---: |
| Texo | 59/72 | 0.39 s |
| Pix2Text | 64/72 | 0.61 s |
| PP-FormulaNet plus-S, optimised FP32 | 60/72 | 0.65 s |
| Mathpix Snip account | 66/72 | 1.47 s |

Mathpix corrected four Pix2Text failures but missed two cases Pix2Text passed. Its remaining failures comprised four Greek/Latin character errors and two notation changes: a star became an asterisk, and blackboard-bold expectation became upright E. All 72 Mathpix outputs passed strict KaTeX parsing and XeLaTeX compilation without repairs. Syntactically valid output can still contain incorrect mathematics.

Local response times include a fresh process, model preparation, recognition and exit. Mathpix shows the median of three HTTPS requests, including upload, network and server processing but excluding sign-in; its median across the 72 images was 1.43 s. The timings therefore describe different execution paths. On the Apple M1 Pro with 16 GB RAM, earlier local peak memory was 0.23 GiB for Texo, 0.80 GiB for Pix2Text and 0.72 GiB for plus-S across a broader 158-input comparison. Mathpix's standalone request client peaked at approximately 17 MiB across 75 requests; this excludes Baker's interface and all cloud resources, so it is not a total-memory comparison.

This small diagnostic set contains dependent variants, and the review was conducted with engine identities known. It does not establish general accuracy or a decisive ranking. Mathpix provides a useful optional online path; the local models remain competitive on these samples. PDF conversion was not compared in this evaluation.

## What the Baker adaptation changes

The document checkpoint derives from GLM-OCR through quantisation and a rank-4 LoRA adapter. The checkpoint directory is approximately 815 MiB; the adapter is approximately 1.5 MiB. These figures exclude the interpreter, layout detector and libraries.

The adapter was trained for 40 updates on 54 checked, authored examples. Validation and test examples have separate content. PaddleOCR, Apple Vision, Tesseract and GLM-OCR supplied candidate teacher outputs that were checked against authored targets. User captures and research PDFs were excluded from training. The small dataset does not establish broad accuracy gains over the base model.

Baker starts from the [MLX community BF16 conversion](https://huggingface.co/mlx-community/GLM-OCR-bf16) of Z.ai GLM-OCR, then applies its own mixed precision and adapter. The pinned source revisions are `24f15402e83baa0a80eeeaecf5480e172abc6f2e` for that MLX conversion and `1cef9f0bdcd6a4c63df7de1311fb0894593340cc` for MFR. The optional engine retains provenance under `~/Library/Application Support/Baker/Engines/pdf-engine-v1.0.0`; downloaded formula models stay under `~/Library/Application Support/Baker/Models`. Both retain hashes, package versions and upstream notices. The checked inference code, evaluation and packaging tools are in [`tools/recognition`](https://github.com/PentagonToy/Baker/tree/main/tools/recognition).

## Repositories studied

| Repository | What informed Baker | Use in the current app |
| --- | --- | --- |
| [MinerU](https://github.com/opendatalab/MinerU) | Native-text reuse, bounded document processing and equation-number recovery | Architecture reference and comparison engine; not bundled |
| [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) | Document/formula comparison and checked training targets | Optional converted plus-S weights and focused PaddleX preprocessing; Paddle itself is not bundled |
| [Marker](https://github.com/datalab-to/marker) | Structured document blocks and separate output rendering | Design reference; not bundled |
| [GOT-OCR 2.0](https://github.com/Ucas-HaoranWei/GOT-OCR2.0) | Region prompts and separate evaluation of prose, equations and tables | Source review; not bundled or used as a measured Baker baseline |
| [unicodeit](https://github.com/svenkreiss/unicodeit) | Unicode mappings and unsupported-notation cases | Conversion reference; Baker uses its own bounded parser |

Unicode coverage was also reviewed against unicodeitplus, Open DevHub’s latex-to-unicode, UniTeX and unicode2latex. These are comparison references, not bundled converters or replacement tables. Baker retains its own Swift parser and preserves unsupported scripts rather than changing their case or discarding grouping.

CleanShot X, Mathpix and Dropzone informed capture and workspace interactions. Baker includes none of their code or artwork.

## Image editing

Background removal uses Baker’s smooth-background operation or Apple Vision foreground masks. Colour tracing uses [VTracer 0.6.15](https://github.com/visioncortex/vtracer); monochrome tracing uses [Potrace 1.16](https://potrace.sourceforge.net/). SVGcode informed the workflow. See [pinned inputs and packaging](https://github.com/PentagonToy/Baker/tree/main/others/image-tools) and [licences](../legal/third-party.md).

The capture palette follows Masataka Okabe and Kei Ito’s [Color Universal Design](https://jfly.uni-koeln.de/color/), with an additional white masking swatch.

## Recognition limits

Review names, mathematical symbols, table spans and reading order against the source. Small glyphs, dense equations, headings and complex tables can be misread. Enlarge a formula in its source app before capture when possible.

Texo uses the pinned transfer model; Pix2Text provides an alternative for everyday formulas. plus-S offers another option for multiline formulas and uses more request memory. Each worker exits after recognition. Formula scores describe token probabilities rather than verified accuracy; plus-S and the PDF model provide no calibrated score.

See [limits](limits.md), [model packages](../models/README.md) and [third-party notices](../legal/third-party.md).
