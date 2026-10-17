# Limits

## Capture and history

Images are limited to 8192 pixels per side and 32 megapixels. Scrolling is manual, downward only and limited to five minutes. Set global shortcuts in Settings → Shortcuts.

History holds up to 10,000 image records. Formula history defaults to 50 results, with a configurable limit and optional 10-day or 30-day expiry. Formula metadata is limited to 16 MB in total and 32 KiB per text field. Up to eight formula results and six capture thumbnails are cached in memory.

## PDF conversion

The complete app uses a mixed-precision GLM-OCR model with a small Baker adapter, ONNX layout detection and available PDF text. Capture formula recognition retains its smaller MFR engine. The current bundled MLX library requires macOS 26.2 or later on Apple Silicon. It exports structured Markdown or LaTeX and companion figure files. Recognition is approximate: review names, footnote markers, equations, merged table cells and reading order. Scans without a usable text layer cannot benefit from native-character correction.

| Limit | Maximum |
| --- | --- |
| Input | 256 MB, 2000 pages |
| Exported document text | 64 MiB |
| Structured job output, including assets | 512 MiB |
| Structured job duration | Two hours |

Unlock protected PDFs before conversion. Keep exported figure folders beside their document. LaTeX exports require LuaLaTeX or XeLaTeX with the packages named in the document; these tools are needed to compile the export, not to use Baker.

Development builds without the document engine use text extraction and text OCR. That fallback does not reconstruct equations, tables or figures.

## Recording

Recording is silent and does not upscale the selected area. Frames may be skipped if encoding falls behind. Video uses even pixel dimensions; GIFs loop continuously. Duration and size limits are listed in [Record](../guide/record.md).

## Text recognition

Select 1–3 languages from English, German, Korean, Swedish, Danish and Finnish. Text capture uses Apple Vision unless Finnish is selected, which uses the included Tesseract engine. The structured PDF engine uses native PDF text where reliable and a separate local document model elsewhere. Its language handling is separate from these screenshot settings; multilingual scans need review.

## Synced folders

Baker uses Finder-accessible folders and the provider’s sync software. Use one running Baker instance per shared folder; simultaneous edits from different Macs are not merged.
