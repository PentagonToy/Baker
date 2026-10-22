# Third-party notices

Baker includes unchanged resources with their upstream notices. Baker’s own source is licensed under [GNU AGPL version 3](https://github.com/PentagonToy/Baker/blob/main/LICENSE), identified as `AGPL-3.0-only`. Dependencies retain their separate terms.

| Resource | Licence | Included notices |
| --- | --- | --- |
| Latin Modern Math 1.959 | GUST Font License, based on LPPL 1.3c or later | Original README, manifest, GUST licence and LPPL |
| TeX Gyre Termes Math 1.543 | GUST Font License | Original README, manifest, GUST licence and LPPL |
| TeX Gyre Pagella Math 1.632 | GUST Font License | Original README, manifest, GUST licence and LPPL |
| KaTeX 0.19.0 scripts, styles and fonts | MIT | Upstream licence, version and SHA-256 inventory |
| KaTeX mhchem extension | MIT adaptation with retained Apache-2.0 upstream notices | Original attribution and Apache-2.0 licence |
| VTracer 0.6.15 | MIT | Original licence, pinned wheel, source archive and hashes |
| Potrace 1.16 command-line tool and private library | GPL-2.0-or-later | Original COPYING, exact source archive, Homebrew build recipe and provenance |
| `tessdata_fast` language models | Apache 2.0 | Upstream licence, source revision and file hashes |

The offline formula renderer comes from [KaTeX](https://github.com/KaTeX/KaTeX/tree/v0.19.0), including its mhchem extension. Its notices and pinned file inventory ship under `Contents/Resources/FormulaPreview`; the source copy is `Sources/Baker/Resources/FormulaPreview`. Baker does not load these resources from a CDN.

Font and OCR-model notices ship with the app under `Contents/Resources/Fonts` and `Contents/Resources/Tessdata`. Repository copies are under `Sources/BakerCore/Resources`. The [GUST e-foundry](https://www.gust.org.pl/projects/e-foundry) publishes the fonts; [Tesseract](https://github.com/tesseract-ocr/tessdata_fast) publishes the language models.

The complete app also includes standalone CPython, NumPy, Pillow, ONNX Runtime, tokenizers and their required dependencies, plus Tesseract and its shared libraries. Runtime versions are recorded in `Contents/Resources/Runtime/manifest.json`. Python and package notices remain in the runtime and distribution metadata; native library notices are under `Runtime/licences`. The MFR 1.5 model is included in complete builds or downloaded at a pinned revision; its upstream README, including its MIT declaration, is retained beside the model. Their respective distribution and model terms apply. Reference applications and source collections informed implementation choices; Baker does not redistribute CleanShot or Mathpix code or artwork.

Document-enabled builds include MLX, a quantised GLM-OCR checkpoint with a Baker adapter, extracted inference definitions from MLX-VLM, DocLayout-YOLO ONNX, OpenCV and PyMuPDF. The inference runtime excludes PyTorch, Transformers and the general MLX-VLM launcher. Upstream notices, model provenance, package versions and payload hashes remain under `Contents/Resources/DocumentEngine`. PyMuPDF retains its AGPL terms. The selected DocStructBench weights declare Apache-2.0; the DocLayout-YOLO repository and its tools have separate terms. Model and code licences must be read separately. Earlier Pix2Text-based document builds remain supported by the builder but are not the selected local configuration.

## Model and inference-code sources

| Component | Upstream source | Declared terms |
| --- | --- | --- |
| GLM-OCR model weights and BF16 conversion | [Z.ai model card](https://huggingface.co/zai-org/GLM-OCR), [MLX conversion](https://huggingface.co/mlx-community/GLM-OCR-bf16) | MIT model licence; the SDK repository has separate Apache-2.0 terms |
| Extracted MLX-VLM inference definitions | [MLX-VLM](https://github.com/Blaizzy/mlx-vlm) | MIT; extracted-file inventory and original licence retained |
| DocStructBench layout weights | [DocLayout-YOLO-DocStructBench](https://huggingface.co/juliozhao/DocLayout-YOLO-DocStructBench) | Apache-2.0 model declaration |
| MFR 1.5 formula weights | [Pix2Text MFR](https://huggingface.co/breezedeus/pix2text-mfr-1.5) | MIT declaration in the retained upstream README |

[Models and references](../help/recognition.md) distinguishes included dependencies, Baker adaptations and comparison-only repositories. Package metadata and retained notices identify the precise bundled versions.

Model cards retained in [`tools/recognition/notices`](https://github.com/PentagonToy/Baker/tree/main/tools/recognition/notices) identify upstream declarations. New document-engine packages include these cards and corrected checkpoint provenance. Baker’s AGPL source and the corresponding build scripts must accompany the binary distribution alongside dependency notices.

Capture image-tool inputs and provenance are documented in [Local capture image tools](https://github.com/PentagonToy/Baker/tree/main/others/image-tools). App builds retain their notices, corresponding source archives and build recipe under `Contents/Resources/ImageTools`. VTracer handles colour outlines; Potrace handles monochrome outlines. SVGcode and AutoTrace are research references, not bundled applications.

## Installer helpers

The DMG alias and layout helpers derive from remile. by PentagonToy under the MIT licence. Their notice is retained in [tools/remile-LICENSE.txt](../../tools/remile-LICENSE.txt).
