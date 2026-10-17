<picture>
  <source media="(prefers-color-scheme: dark)" srcset="others/assests/banner/baker_banner_dark.svg">
  <img src="others/assests/banner/baker_banner_light.svg" alt="Baker" width="960">
</picture>

# Baker

Version **0.0.2** · [Changelog](CHANGELOG.md)

**A keen eye. A fresh result.**

Capture the detail. Serve the result fresh from Baker.

**[Website and user guide](https://pentagontoy.github.io/Baker/)** · [Getting started](docs/help/getting-started.md) · [Settings](docs/help/settings.md)

Baker is a macOS menu-bar app for local screen capture, text and formula recognition, and PDF conversion. Copy results straight into your work without an OCR account.

| Task | Result |
| --- | --- |
| All, Area or Scrolling | Images to copy, save, drag, pin or edit |
| Text | Editable text in six supported languages |
| Formula | Rendered preview, LaTeX, Markdown maths, Keynote or Unicode |
| PDF conversion | Structured Markdown or LaTeX with equations, tables and figure files |
| Video or GIF | Short silent recordings |

The capture app includes local text and formula recognition, plus offline KaTeX and mhchem previews. PDF conversion downloads and verifies [PDF Engine 1.0.0](https://github.com/PentagonToy/Baker/releases/tag/pdf-engine-v1.0.0) once; the installed engine works offline. Normal use needs no Python path or model configuration.

## Recognition engines

Formula images use Pix2Text MFR 1.5 with ONNX Runtime. PDFs combine native text, DocLayout-YOLO and a quantised GLM-OCR model with a small Baker adapter running through MLX. Screenshot text uses Apple Vision or local Tesseract. See [models and reference repositories](docs/help/recognition.md) for upstream links, adaptations, validation and limitations.

## Start using Baker

Move a packaged **Baker.app** to Applications and open it. Allow Screen Recording when prompted. Choose **Formula** or **Text**, select a region and paste the recognised result. Set global shortcuts and your save folder in Settings.

Captures and formula history use one folder, initially `~/Documents/Baker`. Choose a Finder-accessible synced folder to use iCloud Drive, Dropbox or Google Drive; Baker has no cloud login. See [storage](docs/help/storage.md).

## Requirements

The capture app requires **Apple Silicon and macOS 26.0 or later**; PDF conversion requires **macOS 26.2 or later**. The interface is English. Text OCR offers English, German, Korean, Swedish, Danish and Finnish, with up to three selected languages. Formula OCR uses its own model.

This is a preview: compare mathematical symbols and complex PDF layouts with the source. Scrolling is manual and recording is silent. See [limits](docs/help/limits.md).

[Build from source](docs/help/development.md) · [Privacy](https://pentagontoy.github.io/Baker/legal/privacy.html) · [Third-party notices](docs/legal/third-party.md)

## Licence

Baker’s own source is licensed under [GNU AGPL version 3](LICENSE) (`AGPL-3.0-only`). Copyright © 2026 Hanseul Kang. Fonts, models and other dependencies retain their own [licences and notices](docs/legal/third-party.md).

[Release preparation](others/release/README.md) records the checks and remaining steps for the current preview package.
