# Capture

Choose a capture action from Baker’s menu-bar icon. Drag to select an area; Escape cancels. The centred hint disappears when dragging begins and stays out of the capture. **All** immediately captures the monitor containing the pointer, including its menu bar and Dock.

| Action | Result |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-all-dark.svg"><img src="../../others/assests/symbols/capture-all.svg" width="22" alt="All"></picture> All | Captures the monitor containing the pointer without dragging |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-area-dark.svg"><img src="../../others/assests/symbols/capture-area.svg" width="22" alt="Area"></picture> Area | Saves an image and shows a thumbnail at the bottom left |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-scroll-dark.svg"><img src="../../others/assests/symbols/capture-scroll.svg" width="22" alt="Scrolling"></picture> Scrolling | Joins a page as you scroll down |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-text-dark.svg"><img src="../../others/assests/symbols/capture-text.svg" width="22" alt="Text"></picture> Text | Saves the source and recognises text without a thumbnail |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-formula-dark.svg"><img src="../../others/assests/symbols/capture-formula.svg" width="22" alt="Formula"></picture> Formula | Saves the source without a thumbnail, opens the equation and copies the selected format |

Text copies automatically when **General → Copy recognised text** is enabled. Formula always copies the selected format. Both save the source in history without a thumbnail. Baker warms text recognition after launch; the first use can still take longer.

Image thumbnails fit without cropping and follow the pointer to the lower-left corner of the active monitor. The stack stays in place during a drag.

Hover over an image thumbnail to copy, save, pin or recognise it. **Save** confirms the file in the capture folder and closes the thumbnail without a location chooser. For another destination, use **Save a Copy As…** in the context menu.

A successful drop closes its thumbnail; a cancelled or rejected drop keeps it. Closing a thumbnail preserves the saved file.

In **Settings → Capture**, enable **Hide desktop icons in captures and recordings** to exclude Finder’s desktop icons from images, scrolling captures and recordings. Your desktop stays unchanged; open Finder windows remain visible.

## Shortcuts

Assign shortcuts in **Settings → Shortcuts**, including Command or Control. They work across apps and appear beside menu commands; for example, Control–Tab appears as `⌃⇥`. **Record…** shows the Video shortcut; the GIF shortcut opens the same recorder with GIF selected. Escape cancels shortcut entry, Delete clears it and conflicting assignments are reported.

While entering a shortcut, Baker pauses its capture shortcuts. Switching away cancels entry. Settings stays visible during capture.

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

Double-click an image thumbnail, or choose its **Edit** action. Add a pen stroke, rectangle, ellipse, arrow or text; drag with Crop to select a crop. **Undo** removes the last edit; **Redo** restores it. The drawing canvas supports Command–Z and Shift–Command–Z.

Choose from the eight **Okabe–Ito** colours or Baker’s additional white masking swatch. **Mask** selects a white, filled rectangle; **Fill** makes rectangles and ellipses opaque. **Done** replaces the capture, removes its previous OCR result and returns it to the thumbnail stack. **Cancel** preserves the original. Previously exported copies remain unchanged.

**Remove Background → Paper & Slides** removes plain or softly shaded backgrounds from diagrams. **Photo Cutout** isolates a subject but can omit graph axes and labels. A checkerboard shows transparency. Both support Undo and images up to eight megapixels.

**Vectorise** traces the edited image as Colour or Black & White, after applying masks and crops. Undo restores the image and edits. Done replaces the PNG with one SVG; Save, Copy and drag use that SVG. Tracing supports up to four megapixels. Inspect small text and fine lines before confirming.

Reopening a thumbnail’s SVG editor converts it to an image in memory. Done saves one PNG, or one SVG if vectorised again; Cancel preserves the SVG. History offers SVG preview, copy, save and drag. To recognise text or maths again, first edit the SVG as an image.

Area, Text and Formula prepare a snapshot of the pointer’s monitor to help capture open menus. Other monitors and failed snapshots use live capture; menu preservation depends on the app and timing. Scrolling and recording remain live.

Baker workspaces remain visible and can be captured. Thumbnails hide temporarily; selection controls stay out of the image.

## Repeat an area

<picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/capture-repeat-dark.svg"><img src="../../others/assests/symbols/capture-repeat.svg" width="22" alt="Repeat Area"></picture> **Capture → Repeat Area** captures the last successfully saved Area, Text or Formula selection again without showing the selector. It creates a new image through the normal save, clipboard and thumbnail flow; it does not rerun the previous OCR action. Assign its own shortcut in **Settings → Shortcuts** for repeated capture workflows.

The area follows its original display. Disconnecting or resizing that display disables Repeat Area until a new selection is captured. All, Scrolling and Record leave the remembered area unchanged. The selection stays on this Mac and is excluded from presets.

Palette values follow Masataka Okabe and Kei Ito’s [Color Universal Design](https://jfly.uni-koeln.de/color/). Names and selection marks supplement colour.
