# Formula help

Use a clear crop around one equation. Compare the original and rendered result, especially signs, scripts and matrix entries.

## Original image

Original loads the saved capture at full resolution and fits it without enlargement. The pixel dimensions appear below it. A small equation on screen contains few pixels even on a Retina display; enlarge the equation in the source app before capture when possible. OCR reads the saved original, independently of the preview.

## Confidence

Confidence is the geometric mean of emitted LaTeX token probabilities. **Recognition details** shows the model identifier, calculation method, original score, lowest token score and count below 80%. Tokens are model fragments, not individual visible symbols; the count is not an error count.

Editing removes confidence from the current result. The original source, score and diagnostics remain in Recognition details. **Recognise Again** runs OCR explicitly.

## Output compatibility

Keynote output converts supported bracketed arrays to matrix environments while preserving original LaTeX. Unsupported notation carries a warning. Successful preview rendering does not establish compatibility with Keynote or Unicode output.

Formula previews use bundled [KaTeX 0.19.0](https://katex.org/docs/supported.html) and its mhchem extension. Common operators, accents, limits, sized delimiters, fractions, matrices, aligned equations and piecewise cases render locally. This is not a complete TeX installation; unsupported notation shows its source and an explanation. The app preserves saved and copied LaTeX independently of preview rendering.

Saved results reopen without the OCR runtime. The current renderer regenerates their preview and derived formats; explicit Unicode edits are preserved. KaTeX uses its bundled maths fonts. Settings → Formula → Unicode maths controls the font attached to Unicode clipboard output, independently of the rendered preview.

## Offline use

Preview scripts, styles and fonts ship inside Baker; no CDN, account or TeX installation is required. Screenshot text and formula recognition also run locally once their included runtime is prepared. PDF conversion requires the separate PDF engine to be downloaded once before travelling; installed engines work offline. Previews cannot open links, retrieve external images or run user-supplied HTML.

## Formula Workspace

Choose **Formula Workspace** below **Open Files** in the menu. The upper area accepts a formula image; the rendered preview, confidence and copy fields stay empty until an image is recognised. Drop an edited capture thumbnail or choose **Image…**.

**New** returns to this empty input state without deleting history. **History** lists saved equations by date and source text, including earlier app sessions. The left arrow returns from New to the last selected result; the arrows then move between actual records. A new input does not add a history entry until recognition begins.

## History and storage

Settings → Formula keeps the latest 50 results by default. Choose a different limit or expire results after 10 or 30 days. Clear Formula History removes recognised text and diagnostics while keeping capture images. Clear Preview Cache releases in-memory previews; saved results remain available.

Copy formats remove ordinary LaTeX token spacing, such as `v _ { x }` → `v_{x}`. Text groups and explicit TeX spacing are preserved. Unicode uses the selected maths font; characters missing from that font may use a macOS fallback.

Known standard operators inside `\operatorname`, such as `\operatorname{ e x p }`, are normalised to `\exp` when copying or preparing recognised LaTeX. The same rule covers `log`, `sin` and other supported standard names. Ordinary text, custom operator names and starred operator declarations retain their spacing and structure. Existing saved results benefit when their preview is regenerated.

## Chemistry and preview limits

The bundled mhchem extension renders `\ce{H2O}`, ions, isotopes and reaction notation such as `\ce{2 H2 + O2 -> 2 H2O}`. Ordinary mathematical notation such as `\mathrm{SO_4}^{2-}` also works. These are typesetting capabilities, not an evaluation of chemical OCR accuracy. Baker does not infer chemical bonds or reconstruct molecular structures.

Chemformula's braced `\ch{...}` language and chemfig's molecular structures remain unsupported. Their source and internal whitespace remain intact in LaTeX/Markdown, with destination warnings for Unicode and Keynote. KaTeX's mathematical `\ch` alias is not a chemformula parser; Baker rejects braced chemistry input rather than displaying a misleading result.

The standard named-operator catalogue follows the basic [AMS operator definitions](https://github.com/latex3/latex2e/blob/develop/required/amsmath/amsopn.dtx). Known names are normalised conservatively; custom and starred operator names retain their structure. Consult the [KaTeX support table](https://katex.org/docs/support_table.html) for additional notation. A successful preview does not guarantee that OCR read the original correctly.

Previews accept at most 8,000 characters, limit macro expansion and user-defined sizes, and impose image dimensions and a timeout. Each equation starts with fresh macro state. A single reusable renderer and a bounded cache avoid creating one web view per history entry. **Clear Preview Cache** also clears cached rendered images.
