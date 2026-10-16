# Capture

Choose a capture action from Baker’s menu-bar icon, then drag an area and release. Press Escape to cancel.

| Action | Result |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-area-dark.svg"><img src="../../others/assests/symbols/capture-area.svg" width="22" alt="Area"></picture> Area | Saves an image and shows a thumbnail at the bottom left |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-scroll-dark.svg"><img src="../../others/assests/symbols/capture-scroll.svg" width="22" alt="Scrolling"></picture> Scrolling | Joins a page as you scroll down |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-text-dark.svg"><img src="../../others/assests/symbols/capture-text.svg" width="22" alt="Text"></picture> Text | Recognises text in the selected area |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-formula-dark.svg"><img src="../../others/assests/symbols/capture-formula.svg" width="22" alt="Formula"></picture> Formula | Opens the recognised equation and copies the selected format |

Hover over an image thumbnail to copy, save, pin or recognise it. **Save** confirms the file in the capture folder and closes the thumbnail without a location chooser. For another destination, use **Save a Copy As…** in the context menu.

A successful drop into another app closes its thumbnail; cancelled or rejected drops keep it. Older thumbnails slide upwards and fade as new captures fill the stack. Images are preserved in `~/Documents/Baker` before previews appear, including captures that leave the stack.

## Scrolling

Select the moving content, leaving out fixed headers and sidebars. Scroll down steadily as new content appears in the preview. Baker matches overlapping frames while the page moves. Choose **Finish** for one long image, or **Cancel** to discard it.

Scrolling is manual and downward only. Slower scrolling helps when the page contains repeated patterns or animation.

## Formula results

Compare **Original**, **Rendered** or **Both** in the Formula Workspace. Choose a format to copy immediately:

| Format | Paste into |
| --- | --- |
| LaTeX | An equation editor; choose bare source or delimiters |
| Markdown | A document that supports display maths between `$$` lines |
| Keynote | Keynote’s equation editor; compatible arrays become matrices |
| Unicode | Ordinary text, including table cells |

Use **Edit → Apply & Copy** to correct a result. Hover over or click a warning for its explanation. Confidence runs from red to green; it reflects the model’s certainty, not guaranteed correctness.

Results and edits are saved. Find them in [Recent](recent.md) without repeating OCR. See [formula help](../help/formula.md), [Unicode pasting](../help/unicode-maths.md) or [setup](../help/getting-started.md#prepare-formula-recognition).

## Edit a capture

Double-click an image thumbnail, or choose its **Edit** action. Add a pen stroke, rectangle, ellipse, arrow or text; drag with Crop to select a crop. **Undo** removes the last edit.

Enable **Fill** for an opaque rectangle or ellipse to mask content. **Done** overwrites this capture and returns it to the same stack position; its previous OCR result is removed. **Cancel** discards the edits. Previously exported or uploaded copies remain unchanged.

On the next launch, Baker moves the previous `~/Pictures/Baker` archive to `~/Documents/Baker` if the destination does not exist. If both folders exist, they remain separate; Baker uses Documents and leaves the older folder intact.
