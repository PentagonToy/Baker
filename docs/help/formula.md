# Formula help

Use a clear crop around one equation. Compare the original and rendered result, especially signs, scripts and matrix entries.

## Original image

Original loads the saved capture at full resolution and fits it without enlargement. The pixel dimensions appear below it. A small equation on screen contains few pixels even on a Retina display; enlarge the equation in the source app before capture when possible. OCR reads the saved original, independently of the preview.

## Confidence

Confidence is the geometric mean of emitted LaTeX token probabilities. **Recognition details** shows the model identifier, calculation method, original score, lowest token score and count below 80%. Tokens are model fragments, not individual visible symbols; the count is not an error count.

Editing removes confidence from the current result. The original source, score and diagnostics remain in Recognition details. **Recognise Again** runs OCR explicitly.

## Output compatibility

Keynote output converts supported bracketed arrays to matrix environments while preserving original LaTeX. Unsupported notation carries a warning. The native preview supports common fractions, scripts, roots, simple matrices and aligned equations; other notation falls back to source.

Saved results reopen without the OCR runtime. The current code and maths font regenerate their preview and derived formats; explicit Unicode edits are preserved.

## Formula Workspace

Choose **Formula Workspace** below **Open Files** in the menu. The upper area accepts a formula image; the rendered preview, confidence and copy fields stay empty until an image is recognised. Drop an edited capture thumbnail or choose **Image…**.

**New** returns to this empty input state without deleting history. **History** lists saved equations by date and source text, including earlier app sessions. The left arrow returns from New to the last selected result; the arrows then move between actual records. A new input does not add a history entry until recognition begins.

## History and storage

Settings → Formula keeps the latest 50 results by default. Choose a different limit or expire results after 10 or 30 days. Clear Formula History removes recognised text and diagnostics while keeping capture images. Clear Preview Cache releases in-memory previews; saved results remain available.

Copy formats remove ordinary LaTeX token spacing, such as `v _ { x }` → `v_{x}`. Text groups and explicit TeX spacing are preserved. Unicode uses the selected maths font; characters missing from that font may use a macOS fallback.
