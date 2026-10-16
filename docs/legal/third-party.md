# Third-party notices

Baker includes unchanged resources with their upstream notices. These licences apply to those resources; they do not assign a project-wide licence to Baker's own source code.

| Resource | Licence | Included notices |
| --- | --- | --- |
| Latin Modern Math 1.959 | GUST Font License, based on LPPL 1.3c or later | Original README, manifest, GUST licence and LPPL |
| TeX Gyre Termes Math 1.543 | GUST Font License | Original README, manifest, GUST licence and LPPL |
| TeX Gyre Pagella Math 1.632 | GUST Font License | Original README, manifest, GUST licence and LPPL |
| `tessdata_fast` language models | Apache 2.0 | Upstream licence, source revision and file hashes |

Notices ship with the app under `Contents/Resources/Fonts` and `Contents/Resources/Tessdata`. Repository copies are under `Sources/BakerCore/Resources`. The [GUST e-foundry](https://www.gust.org.pl/projects/e-foundry) publishes the fonts; [Tesseract](https://github.com/tesseract-ocr/tessdata_fast) publishes the language models.

The complete app also includes standalone CPython, NumPy, Pillow, ONNX Runtime, tokenizers and their required dependencies, plus Tesseract and its shared libraries. Runtime versions are recorded in `Contents/Resources/Runtime/manifest.json`. Python and package notices remain in the runtime and distribution metadata; native library notices are under `Runtime/licences`. The MFR 1.5 model is downloaded separately at a pinned revision; its upstream README, including its MIT declaration, is included in that download. Their respective distribution and model terms apply. Reference applications and source collections informed implementation choices; Baker does not redistribute CleanShot or Mathpix code or artwork.
