# Formula help

Crop one equation clearly. Compare the original and rendered result, especially signs, scripts and matrix entries.

Captured formulas appear in a popover below the Baker menu-bar icon and copy automatically. Choose **Workspace** for detailed review.

## Formula Workspace

Choose **Formula Workspace**, drop an image or edited capture thumbnail, or choose **Image…**. The preview, model score and copy fields remain empty until recognition.

**New** opens an empty input without deleting history. **History** lists saved equations across sessions; arrows move between results. From New, the left arrow returns to the last selected equation. Saved results reopen without rerunning OCR.

The workspace opens with the rendered equation. Choose **Original** or **Both** to compare it with the capture.

## Original image

Original fits the saved capture without enlargement and shows its pixel dimensions. Small on-screen equations contain few pixels even on Retina displays; enlarge the equation in the source app before capture. OCR reads the saved original independently of its preview.

## Confidence and correction

**Model score** is the geometric mean of emitted LaTeX token probabilities, not the probability that the whole equation is correct. A high score can accompany an extra bracket, a missing term or another confident mistake. **Recognition details** shows the model, original score, lowest token score and count below 80%. Tokens are model fragments; this count is not an error count.

Editing removes the current score while retaining original diagnostics. **Edit → Apply & Copy** saves a correction. **Recognise Again** explicitly reruns OCR.

## Copy formats

Choose LaTeX, Markdown, Keynote or Unicode. Keynote converts supported bracketed arrays to matrices, centred multiline groups to matrix rows and braced `\pmb{...}` to `\boldsymbol{...}`. Underlines, variable fonts and mathematical grouping remain intact. [Unicode maths](unicode-maths.md) approximates notation in ordinary text fields; its font setting affects clipboard output independently of the preview. The warning icon appears only when Unicode is unavailable.

Copying removes ordinary token spacing, such as `v _ { x }` → `v_{x}`, while preserving text groups and explicit spacing. Known standard operators such as `\operatorname{ e x p }` become `\exp`; custom and starred operators retain their structure. The catalogue follows [AMS operator definitions](https://github.com/latex3/latex2e/blob/develop/required/amsmath/amsopn.dtx).

Keynote has its own equation parser. [Apple documents](https://support.apple.com/en-gb/102138) support for `\boldsymbol` and limited `aligned` layouts. Baker preserves these rather than flattening every structure. Uneven matrix rows, custom row spacing and documented unsupported commands retain their source with a compatibility warning. This conversion does not use AI or rerun recognition. In Last Capture, the format selector has its own row above the copy action.

## Preview and chemistry

Bundled [KaTeX 0.19.0](https://katex.org/docs/support_table.html) renders common operators, accents, limits, sized delimiters, fractions, matrices, aligned equations and cases. Unsupported notation shows its source and an explanation; saved and copied LaTeX remain available.

The mhchem extension renders `\ce{H2O}`, ions, isotopes and reactions such as `\ce{2 H2 + O2 -> 2 H2O}`. Ordinary notation such as `\mathrm{SO_4}^{2-}` also works. Chemical OCR accuracy has not been established; Baker does not reconstruct molecular structures.

Chemformula’s braced `\ch{...}` and chemfig structures remain unsupported. Their LaTeX source and whitespace are preserved, with warnings for incompatible destinations. Successful rendering establishes neither OCR correctness nor Keynote or Unicode compatibility.

Previews accept up to 8,000 characters, bound macro expansion, dimensions and rendering time, and reset macro state for each equation. One renderer and a bounded cache serve the workspace.

## Offline use

Preview scripts, fonts and styles ship with Baker. Prepared text and formula recognition work locally; download the optional PDF engine before travelling. Installed engines work offline. Previews cannot retrieve external images or run user-supplied HTML.

## History

**Settings → General → History** defaults to 50 formula results with no age limit. Choose another count or a 10-day or 30-day expiry. Clearing formula history removes text and diagnostics while retaining captures.

**Settings → Formula → Clear Preview Cache** releases rendered previews. It also reconciles images deleted in Finder and removes their linked metadata; existing files remain. See [history and storage](storage.md#history).

## Long formulas and failures

MFR starts with a 256-token budget and can continue to 512 tokens within the original deadline, normally 45 seconds. Explicit non-default budgets keep their configured limit. Reaching the ceiling without an end token reports an error instead of accepting a partial equation.

Failures offer recovery for model setup, launch, timeout, output or token limits. Technical diagnostics stay out of ordinary alerts and copied results. Workers exit after each job and remove temporary process files.
