# Clipboard & Files

Open an existing image, recognise clipboard content or convert PDF text from the **Clipboard & Files** menu category.

## Use an existing image

Choose **Open Image…** for a file or **Open Clipboard Image** for a copied image. **Read Clipboard Text** recognises text in the clipboard image. Baker reads the clipboard only when you request it.

Imported images are copied into the capture archive without changing their source. Use the thumbnail’s formula action to recognise an equation, then choose an output in the [Formula Workspace](capture.md#formula-results).

## Convert PDF text

Choose **Convert PDF → Markdown…** or **LaTeX…**, then select a PDF. Baker reads the existing text layer and uses text OCR on pages without one. The panel shows progress and offers Cancel.

This is text extraction. Reading order and paragraph grouping are approximate; equations, tables, columns and figures are not reconstructed. Pages with existing text do not separately recognise text inside embedded images. Review mathematical notation and scanned output before using it.

LaTeX exports require LuaLaTeX or XeLaTeX, with a font that covers the extracted characters. They have not yet been validated through a complete TeX compilation.

| Limit | Maximum |
| --- | --- |
| PDF input | 256 MB, 2000 pages |
| Text per page | 250,000 characters |
| Export | 64 MiB |
| OCR page raster | 8 megapixels, 4096px per side |

Unlock password-protected PDFs before conversion. Documents that disallow copying cannot be extracted. Cancellation waits for an in-progress text-recognition request to finish.

## Save an export

PDF conversion finish in an Export panel. **Save…** keeps a file; **Save & Copy…** saves it and copies the saved file for pasting into another app. Unsaved exports are temporary and are replaced by the next export or removed on normal quit.
