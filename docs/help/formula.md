# Formula help

Use a clear crop around one equation. Compare the original and rendered result, especially signs, scripts and matrix entries.

## Confidence

Confidence is the geometric mean of emitted LaTeX token probabilities. **Recognition details** shows the model identifier, calculation method, original score, lowest token score and count below 80%. Tokens are model fragments, not individual visible symbols; the count is not an error count.

Editing removes confidence from the current result. The original source, score and diagnostics remain in Recognition details. **Recognise Again** runs OCR explicitly.

## Output compatibility

Keynote output converts supported bracketed arrays to matrix environments while preserving original LaTeX. Unsupported notation carries a warning. The native preview supports common fractions, scripts, roots, simple matrices and aligned equations; other notation falls back to source.

Saved results reopen without the OCR runtime. The current code and maths font regenerate their preview and derived formats; explicit Unicode edits are preserved.

## History and storage

Settings → Formula keeps the latest 50 results by default. Choose a different limit or expire results after 10 or 30 days. Clear Formula History removes recognised text and diagnostics while keeping capture images and cloud copies. Clear Preview Cache releases in-memory previews; saved results remain available.

Copy formats remove ordinary LaTeX token spacing, such as `v _ { x }` → `v_{x}`. Text groups and explicit TeX spacing are preserved. Unicode uses the selected maths font; characters missing from that font may use a macOS fallback.
