# Settings

| Category | Controls |
| --- | --- |
| General | Quick Start, login startup, update checks, clipboard, appearance, save folder, history and presets |
| Capture | Screen Recording access, desktop icons, sounds, visible previews and OCR languages |
| Formula | Model preparation and repair, Unicode maths font and preview cache |
| Shortcuts | Capture and recording shortcuts |
| Menu | Menu group order, command order and visibility |
| Advanced | Offline PDF model and developer runtime overrides |

Settings remembers its selected page and window position during the session. Closing it leaves Baker running in the menu bar. See [storage and history](storage.md) for retention and presets.

## OCR languages

Select 1–5 languages in Capture. Labels pair English and native names, such as **Korean — 한국어**. The thirteen choices include Arabic, Persian, Spanish, French, simplified and traditional Chinese, Japanese and the Nordic languages. Deselect a language before replacing it when all five slots are used.

Apple Vision handles supported selections. Finnish, Persian or another language unavailable in Vision switches the complete selection to bundled Tesseract. Review mixed-script layouts and right-to-left text. These settings affect text capture and fallback PDF text OCR; structured PDF conversion uses its separate document engine. See [models and references](recognition.md).

## Menu layout

Drag the three-line handles in **Settings → Menu** to reorder groups or commands. Commands stay within their group; untick one to hide it. Handles also offer accessible move actions and a right-click menu.

**Apply** saves the layout for the next menu opening. **Revert** discards pending changes. **Restore Defaults** prepares the original layout; choose Apply to save it. A restart is unnecessary.

Settings, Quit and active Stop/Cancel controls remain available. Hidden commands retain their shortcuts. Layout preferences stay on this Mac and are excluded from presets. Video and GIF share **Record…**, with separate shortcuts; **Repeat Area** also has its own shortcut.

## Keyboard commands

With a Baker window focused, **⌘Q** quits, **⌘W** closes the window and **⌘,** opens Settings. Text fields support standard macOS editing commands. An ellipsis (`…`) marks a command that opens a chooser or dialog.

## PDF engine

**Settings → Advanced → Offline Model** shows download and installed sizes, progress, cancellation and removal. The engine stays under `~/Library/Application Support/Baker/Engines/pdf-engine-v1.0.0`. Removing it preserves captures, history and exports. See [PDF conversion](../guide/clipboard-and-files.md#pdf-conversion).

## Launch at Login

Baker offers a one-time choice on the first launch after this feature becomes available. **Not Now** leaves startup disabled; **Enable Launch at Login** registers Baker with macOS. Already registered apps skip the offer.

Change the choice in **General → Startup**. If macOS requires approval, use **Open Login Items…**. The control reflects actual registration status and reports failures beside it. This preference stays on the Mac and is excluded from presets.

## Updates

Use **General → Updates → Check for Updates…** to check stable Baker releases. A newer release offers notes, **Download DMG** and **Later**. Open the downloaded disk image and replace Baker in Applications when ready; Baker never installs an update automatically.

Automatic checks are off initially. When enabled, Baker checks GitHub at most once a day while running and shows an available version in Settings and the menu. Background checks show no pop-up and failures stay quiet. Manual checks work regardless of this option. Offline capture and OCR remain available; update preferences stay on this Mac and are excluded from presets.
