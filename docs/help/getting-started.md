# Getting started

Move a packaged **Baker.app** to Applications and double-click it. If supplied as a disk image, open it and drag Baker to Applications first. Baker appears in the menu bar. Normal use needs no Python, Homebrew or model configuration file.

The capture app supports Apple Silicon and macOS 26.0 or later; the optional PDF engine requires macOS 26.2 or later. Baker is distributed outside the Mac App Store. A source archive needs a [development build](development.md) before it can run.

## Allow screen capture

The first capture needs permission in **System Settings → Privacy & Security → Screen Recording**. Enable Baker and reopen it if macOS requests a restart. Imported images and clipboard images do not need screen capture permission.

## Capture a formula

The complete app prepares its included formula model automatically. Wait for **Settings → Formula** to report that it is ready. If your build does not include the model, choose **Download Model · 120 MB**; Baker checks the downloaded files and prepares them without a Python path.

Choose **Formula**, drag around one equation and release. Compare **Original** and **Rendered**, then select **LaTeX**, **Markdown**, **Keynote** or **Unicode**. Baker copies the selected format automatically.

Formula models are prepared under `~/Library/Application Support/Baker/Models`. Recognition runs locally after preparation. **Repair Model** restores the included model or downloads a replacement when required; **Remove Model** removes the prepared cache without deleting captures. The bundled copy, when present, remains in the app.

## Daily use

Use the menu to capture, record or open files. Set global shortcuts in **Settings → Shortcuts** and your save folder in **Settings → General**. Close a workspace with its red window button; Baker continues in the menu bar. **Quit Baker** stops the app.

## Appearance and storage

In **Settings → General**, choose **System**, **Light** or **Dark**. Light appearance uses warm cream surfaces. Save location, History and Presets appear below the clipboard and appearance controls. The sidebar shows Baker’s version.
