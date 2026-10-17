# Capture

Choose a capture action from Baker’s menu-bar icon. A centred hint disappears when you start dragging and is excluded from the saved image. For Area, Scrolling, Text or Formula, drag an area and release; press Escape to cancel. **All** captures the entire monitor containing the pointer immediately, including its menu bar and Dock.

| Action | Result |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-all-dark.svg"><img src="../../others/assests/symbols/capture-all.svg" width="22" alt="All"></picture> All | Captures the monitor containing the pointer without dragging |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-area-dark.svg"><img src="../../others/assests/symbols/capture-area.svg" width="22" alt="Area"></picture> Area | Saves an image and shows a thumbnail at the bottom left |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-scroll-dark.svg"><img src="../../others/assests/symbols/capture-scroll.svg" width="22" alt="Scrolling"></picture> Scrolling | Joins a page as you scroll down |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-text-dark.svg"><img src="../../others/assests/symbols/capture-text.svg" width="22" alt="Text"></picture> Text | Saves the source and recognises text without a thumbnail |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-formula-dark.svg"><img src="../../others/assests/symbols/capture-formula.svg" width="22" alt="Formula"></picture> Formula | Saves the source without a thumbnail, opens the equation and copies the selected format |

Baker prepares Apple text OCR in the background after launch. The first recognition can still take longer while macOS prepares its model. Text recognition copies automatically when **Settings → General → Copy recognised text** is enabled. Formula recognition always copies the selected format. Both retain the source image in history without adding a quick preview.

Image previews use the same golden-ratio rectangle for every capture. Images fit inside it without cropping. The stack follows the pointer to the lower-left corner of the active monitor; it stays in place during a drag.

Hover over an image thumbnail to copy, save, pin or recognise it. **Save** confirms the file in the capture folder and closes the thumbnail without a location chooser. For another destination, use **Save a Copy As…** in the context menu.

A successful drop into another app closes its thumbnail; cancelled or rejected drops keep it. Older thumbnails slide upwards and fade as new captures fill the stack. Images are preserved in the chosen save folder before previews appear, including captures that leave the stack.

In **Settings → Capture**, enable **Hide desktop icons in captures and recordings** to exclude Finder’s desktop icons from images, scrolling captures and recordings. Your desktop stays unchanged; open Finder windows remain visible.

## Shortcuts

Open **Settings → Shortcuts** to record shortcuts for Area, All, Scrolling, Text, Formula, Video and GIF. Include Command or Control. Shortcuts work while another app is active and appear to the right of their menu commands. Menu labels update when the menu opens. Press Escape to cancel recording, or Delete to clear a shortcut. Baker reports conflicting assignments. Tab, arrows and function keys have readable labels; for example, Control–Tab appears as `⌃⇥`.

The recorder highlights while listening and pauses Baker’s capture shortcuts. Escape or switching away cancels recording. The Settings window stays visible when a capture or recording starts; close it with its red window button when finished.

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

Results and edits are saved. Find them in [Recent](recent.md) without repeating OCR. See [formula help](../help/formula.md), [Unicode pasting](../help/unicode-maths.md) or [setup](../help/getting-started.md#capture-a-formula).

## Edit a capture

Double-click an image thumbnail, or choose its **Edit** action. Add a pen stroke, rectangle, ellipse, arrow or text; drag with Crop to select a crop. **Undo** removes the last edit.

Enable **Fill** for an opaque rectangle or ellipse to mask content. **Done** overwrites this capture and returns it to the same stack position; its previous OCR result is removed. **Cancel** discards the edits. Previously exported copies remain unchanged.

Area, Text and Formula use a non-activating selection panel and prepare a snapshot of the pointer’s monitor when capture starts. This helps preserve open menus without activating Baker. Other monitors and failed snapshots use the normal live capture path; menu preservation depends on the application and timing. Scrolling and recording remain live.

Baker’s workspaces stay visible during selection. Capture thumbnails hide temporarily; selection controls are excluded from captured images. Ordinary workspaces remain visible in the frozen selection and can be captured.
