# Limits

## Capture and history

Images are limited to 8192 pixels per side and 32 megapixels. Scrolling is manual, downward only and limited to five minutes. Set global shortcuts in Settings → Shortcuts.

Background removal accepts up to eight megapixels; SVG tracing accepts four megapixels, 60 seconds and an 8 MB result with at most 50,000 paths. Photo Cutout can omit thin labels or axes; inspect traced text and small details.

History holds up to 10,000 image records. Image retention defaults to no count or age limit. Formula history defaults to 50 results, with a configurable limit and optional 7-, 10-, 30- or 90-day expiry. Formula metadata is limited to 16 MB in total and 32 KiB per text field. Up to eight formula results and six capture thumbnails are cached in memory.

## PDF conversion

The optional PDF engine exports structured Markdown or LaTeX and companion figures. Its MLX library requires macOS 26.2 or later on Apple Silicon. Recognition is approximate: review names, footnote markers, equations, merged table cells and reading order. Scans without a usable text layer cannot benefit from native-character correction.

| Limit | Maximum |
| --- | --- |
| Input | 256 MB, 2000 pages |
| Exported document text | 64 MiB |
| Structured job output, including assets | 512 MiB |
| Structured job duration | Two hours |

Unlock protected PDFs before conversion. Keep exported figure folders beside their document. LaTeX exports require LuaLaTeX or XeLaTeX with the packages named in the document; these tools are needed to compile the export, not to use Baker.

Development builds without the document engine use text extraction and text OCR. That fallback does not reconstruct equations, tables or figures.

## Recording

Recording does not upscale the selected area. Video can include system audio, while GIF is silent; microphone capture is not supported. Frames or audio buffers may be skipped if real-time encoding falls behind. Longer GIFs take more time to export and can produce large files; export processes one frame at a time rather than retaining the whole animation. Video uses even pixel dimensions; GIFs loop continuously. Duration and size limits are listed in [Record](../guide/record.md).

## Text recognition

Select 1–5 languages in Settings → Capture. The thirteen choices include Arabic, Persian, Chinese and Japanese. Text capture uses Apple Vision where the complete selection is supported; Finnish and unsupported languages use the included local Tesseract engine. Mixed-script layouts and right-to-left text need review. The structured PDF engine uses native PDF text where reliable and a separate local document model elsewhere. Its language handling is separate from these screenshot settings; multilingual scans need review.

## Synced folders

Baker uses Finder-accessible folders and the provider’s sync software. Use one running Baker instance per shared folder; simultaneous edits from different Macs are not merged.
