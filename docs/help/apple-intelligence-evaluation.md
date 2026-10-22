# Apple Intelligence and PDF conversion

Apple’s current Foundation Models documentation describes image understanding and on-device Vision OCR integration. This makes optional layout interpretation or extracted-text refinement worth evaluating, but does not establish that a generative model is a faster or more faithful replacement for Baker’s existing PDF conversion pipeline. Source: [Foundation Models framework](https://developer.apple.com/foundation-models-framework/) and [multimodal prompting](https://developer.apple.com/documentation/FoundationModels/analyzing-images-with-multimodal-prompting).

Keep original extraction and dedicated formula recognition as the baseline. Before offering an optional Apple Intelligence path, compare representative text, equation, table and scanned pages for transcription fidelity, reading order, equation accuracy, cold/warm latency and peak memory on supported Macs. Verify SDK and model availability, provide a deterministic fallback, and never silently rewrite equations or factual text. No inference backend, model download or performance claim was added during the 19 October UX refinement.


## M1 Pro preliminary comparison — 19 October 2026

Apple Intelligence reported available on macOS 27.0.1. The installed PDF engine used its own Python 3.12.13 arm64 runtime and the existing baker-small-ocr-1 model without downloads; the Swift SDK exposed macOS 27 image attachments. The test used one synthetic multilingual page with seven numeric values, formula symbols and a small table, plus one native-text PDF. This is an exploratory fidelity check, not a representative corpus or end-to-end app benchmark.

| Method | Measured processing time | Observation |
| --- | --- | --- |
| Existing Baker, scanned page | 11.20 s | All seven exact numeric values retained; one Korean character incorrect; inline formula delimiter and table structure still imperfect |
| Apple Intelligence image, first/repeat call | 11.67 / 5.19 s | Changed 0.0037 to 0.00337, misread Korean and superscripts; did not produce the requested LaTeX/table structure |
| Apple Intelligence formatting after Baker | +6.72 s | Output identical after trimming outer whitespace; existing defects remained |
| Existing Baker, native-text PDF | 2.16 s | Whitespace-normalised word order preserved; recognition model was not loaded |

Baker timings are engine-reported processing times and exclude Python startup/imports; Apple timings surround session construction and response, excluding interpreter startup and fixture rendering. No peak-memory measurement was taken. The initial oversized PDF fixture hit the existing 24-megapixel raster guard; the same raster was then embedded on a 600×800-point page. Raw prompts, outputs, fixtures and metrics are preserved under Agents/Repository/baker/2026-10-19-apple-intelligence.

Decision: retain the current Baker pipeline and do not add an automatic Apple Intelligence replacement or formatting pass on this evidence. A repeated image call was faster on this fixture, but introduced a numerical error; the extra formatting pass gave no benefit. Baker’s own Korean/formula/table defects remain work to address. A broader real-document evaluation is needed before exposing an optional path.
