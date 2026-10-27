# Getting started

Move a packaged **Baker.app** to Applications and double-click it. If supplied as a disk image, open it and drag Baker to Applications first. Baker appears in the menu bar. Normal use needs no Python, Homebrew or model configuration file.

The capture app supports Apple Silicon and macOS 26.0 or later; the optional PDF engine requires macOS 26.2 or later. Baker is distributed outside the Mac App Store. A source archive needs a [development build](development.md) before it can run.

## Try the essentials

Quick Start introduces formulas, the workspace, copy formats, scrolling, recording and history. Allow Screen Recording before practising, or continue without capturing. The guide resumes after a requested reopen.

Use the step list, Back and Next to move around. Skip Tour closes the guide. Reopen it from **Baker → Quick Start…** or **Settings → General**. Practice saves and copies a normal capture. Recording starts only after you choose a region and press Record.

## Install with Homebrew

If you already use Homebrew, install from [Baker’s tap](https://github.com/PentagonToy/homebrew-tap):

```sh
brew install --cask pentagontoy/tap/baker
```

This installs the same app as the DMG. Open Baker from Applications, then allow screen capture. Use `brew upgrade --cask baker` for updates. See the tap’s instructions for adopting an identical app already in Applications. Removing the cask keeps your captures, models and preferences.

## Allow screen capture

The first capture needs permission in **System Settings → Privacy & Security → Screen Recording**. Enable Baker and reopen it if macOS requests a restart. Imported images and clipboard images do not need screen capture permission.

Development builds also offer control access at first launch for automatic [Scan](scan.md) page turning. Existing permissions are reused; you can continue with manual capture.

## Capture a formula

Choose Pix2Text or Texo in **Quick Start → Capture a formula** and download it there after allowing screen recording. You can also manage models in **Settings → Formula**. The model files occupy about 77 MB for Pix2Text and 100 MB for Texo; downloads are compressed. Baker verifies the files before recognition becomes ready. Existing installed models are reused.

Capture previews fit the current display’s usable height. When the stack fills, the oldest preview closes and its saved capture remains in History. Choose **Settings → Capture → Visible captures** to use a fixed limit instead.

Choose **Formula**, drag around one equation and release. Compare **Original** and **Rendered**, then select **LaTeX**, **Markdown**, **Keynote** or **Unicode**. Baker copies the selected format automatically.

Formula models live under `~/Library/Application Support/Baker/Models` and work offline after download. **Repair Model** downloads a verified replacement; **Remove Model** removes the selected model without deleting captures. Existing optimised Pix2Text caches remain usable; repair downloads the verified optimised package.

## Daily use

Use the menu to capture, record or open files. Set global shortcuts in **Settings → Shortcuts** and your save folder in **Settings → Storage**. Close a workspace with its red window button; Baker continues in the menu bar. **Quit Baker** stops the app.

## Appearance and storage

In **Settings → General**, choose **System**, **Light** or **Dark**. Light appearance uses neutral surfaces. Storage groups the save folder, history, caches and presets. Clipboard options live in Capture. The sidebar shows Baker’s version.
