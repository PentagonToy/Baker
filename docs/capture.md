# Capture

Click Baker's menu-bar icon to start a task. Successful captures are saved in `~/Pictures/Baker` and appear as a stack in the bottom-left corner. Drag a thumbnail into another application.

## Capture an area

Choose **Area**, drag a region within one display, and release. Press Escape to cancel selection. Selection uses a thin white boundary with an undimmed interior, shows its size in points and has no persistent instruction banner; a click or a drag smaller than the minimum keeps selection active so you can try again. Small single-line equations are supported; drag at least 2 points in each direction. Hover over a thumbnail to copy PNG/TIFF image data, save a separate copy, pin the image, recognise text, or recognise an equation with the formula button. Pinned images remain above other windows.

**Text** captures and recognises in one action. **Formula** captures a cropped equation and automatically opens the Formula Workspace. The selected LaTeX, Markdown, Keynote or Unicode output is copied automatically when recognition succeeds. Formula recognition requires the [local model setup](getting-started.md#prepare-formula-recognition).

## Formula results

Choose **LaTeX**, **Markdown**, **Keynote** or **Unicode** in the Formula Workspace. Switching formats copies immediately without recognising the image again. The toolbar captures another equation, opens an image, navigates recent session results, opens history or edits the current result. Select **Original**, **Rendered** or **Both** to compare recognition with the source.

Markdown copies display maths with `$$` on separate lines. It uses the original recognised LaTeX and does not perform another OCR request. LaTeX offers bare source, inline dollar or bracket delimiters, display dollar or bracket delimiters, and a numbered equation environment. Keynote copies bare maths and converts supported bracketed arrays into compatible matrix environments, such as `bmatrix`. It preserves unsupported structures with a warning. The original LaTeX remains available. Baker remembers the selected format and LaTeX style for the next capture. Hover over or click the Unicode warning icon to read its explanation. Unicode includes editable text and RTF with the maths font chosen in Settings; it approximates two-dimensional layout and warns when notation is unsupported.

**OCR confidence** shows a local model score as a bar and percentage. It is the geometric mean of the probabilities assigned to emitted LaTeX tokens, excluding start/end tokens. Its colour moves from red through orange to green as the score rises; these are presentation colours, not validated accuracy categories. It is not a calibrated probability that the whole equation is correct, and is not comparable to Mathpix's score. Compare the original with the rendered result, especially for indices, signs and matrix entries. Editing the recognised LaTeX removes its previous confidence; changing copy format preserves it. Older worker responses without the score remain usable and show confidence as unavailable.

Use **Edit** to correct a recognised formula, then **Apply & Copy** to update the result. The original capture remains in `Pictures/Baker`. Recognised results and edits are kept for this session only, up to eight formulas; copy them into your document before quitting. Recognition errors offer **Try Again**. The native preview supports common fractions, scripts, roots, operators, delimiters, simple arrays and matrices, and bounded aligned or gathered equations. Unsupported syntax is shown as LaTeX source; copying remains available.

## Scrolling capture

Choose **Scrolling** and select only the moving content area. Exclude fixed headers, footers, sidebars and scrollbars. The first frame is captured immediately. Scroll down by less than half a screen, then pause until the panel shows the accepted strip and updated height. A persistent capture stream samples settled content rather than adding frames while the page is moving. Use **Finish** to include the final settled frame and assemble the image or **Cancel** to discard it.

Repeated patterns, animation, large jumps and reverse scrolling may prevent alignment. A rejected frame does not alter the accepted canvas. Return to the last accepted position before continuing, or finish and start a new segment. Scrolling is manual and downward only.

Scrolling capture stops after five minutes. The canvas is limited to 32 megapixels, with each side at most 8192px. These limits do not guarantee alignment in every application.

Global capture shortcuts, annotation and automatic scrolling are not available yet.
