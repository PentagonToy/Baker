# Limits

## Capture and history

Scrolling runs for up to five minutes, downward only. Images fit within 8192 pixels per side and 32 megapixels. Global shortcuts and automatic scrolling are not available yet.

History keeps up to 10,000 image records. Formula metadata has a 16 MB total limit and 32 KiB per text field. Eight formula previews are kept in memory. Save errors preserve existing data and report the problem.

## PDF conversion

PDF conversion extracts a text layer or uses text OCR. Check equations, tables, figures and column order against the original. Text inside embedded images on an otherwise text-based page may be omitted.

| Limit | Maximum |
| --- | --- |
| Input | 256 MB, 2000 pages |
| Text per page | 250,000 characters |
| Export | 64 MiB |
| OCR raster | 8 megapixels, 4096px per side |

Unlock protected PDFs before conversion. LaTeX document exports require LuaLaTeX or XeLaTeX and a suitable font.

## Recording

Recording is silent and does not upscale the selected area. Frames may be skipped if encoding falls behind. Video dimensions use even pixel sizes; GIFs loop continuously.

## Cloud transfers

Transfers support capture images up to 128 MiB and formula metadata up to 256 KiB. The list loads 100 entries at a time, up to 1000 displayed captures. Drive and Dropbox transfers run on request. Interrupted uploads require another upload attempt; transfers do not resume across app restarts.

## Text recognition languages

Select at most three of the six supported text languages. When Finnish is selected, Tesseract reads those selected languages using bundled `tessdata_fast` models. Otherwise, text OCR uses Apple Vision. Scanned PDF output records its OCR source and needs review for paragraph and column order. The complete app includes the Tesseract executable and its required libraries.
