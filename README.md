<picture>
  <source media="(prefers-color-scheme: dark)" srcset="others/assests/banner/baker_banner_dark.svg">
  <img src="others/assests/banner/baker_banner_light.svg" alt="Baker" width="960">
</picture>

# Baker

**A keen eye. A fresh result.**

Baker is a macOS menu-bar app for local capture, text and formula recognition, and PDF conversion.

**[Download Baker for Mac (.dmg)](https://github.com/PentagonToy/Baker/releases/download/v0.0.4/Baker-0.0.4-arm64.dmg)**

Apple Silicon · macOS 26.0 or later · Version 0.0.4

[Website and guide](https://pentagontoy.github.io/Baker/) · [Getting started](docs/help/getting-started.md) · [Changelog](CHANGELOG.md)

See the [0.0.4 release notes](others/release/0.0.4.md) for changes and validation limits.

| Task | Result |
| --- | --- |
| Capture | Display, area, window and scrolling images |
| Edit | Annotations, masking, background removal and SVG tracing |
| Text | Editable text with up to five of thirteen language choices |
| Formula | Preview, LaTeX, Markdown maths, Keynote or Unicode |
| PDF | Structured Markdown or LaTeX with equations, tables and figures |
| Record | MP4 with optional system audio, or silent GIF |

## Start

1. Download and open the DMG.
2. Drag **Baker.app** to **Applications**, then open it there.
3. Allow Screen Recording when prompted. Choose **Text** or **Formula**, select an area and paste the result.

If macOS blocks the first launch, see [opening a downloaded app](docs/help/troubleshooting.md#opening-a-downloaded-app). Set shortcuts and your save folder in Settings.

Already use Homebrew? Install the same app from [our tap](https://github.com/PentagonToy/homebrew-tap):

```sh
brew install --cask pentagontoy/tap/baker
```

This is a developer-maintained tap, separate from Homebrew’s official cask collection. Use `brew upgrade --cask baker` for later releases. See the tap’s instructions if Baker is already in Applications.

Captures, recordings and formula history use one folder, initially `~/Documents/Baker`. A Finder-accessible synced folder also works with iCloud Drive, Dropbox or Google Drive. See [storage](docs/help/storage.md).

## Local recognition

Text uses Apple Vision or Tesseract; formula images use Pix2Text MFR 1.5. PDFs combine native text, DocLayout-YOLO and quantised GLM-OCR with a small Baker adapter. [Models and references](docs/help/recognition.md) documents sources, adaptations and measured limits.

Text, formula recognition and previews work offline with the included runtime. PDF conversion downloads and verifies [PDF Engine 1.0.0](https://github.com/PentagonToy/Baker/releases/tag/pdf-engine-v1.0.0) once, then works offline. Normal use needs no OCR account, Python path or model configuration.

## Requirements

**Apple Silicon and macOS 26.0 or later**; PDF conversion requires **macOS 26.2 or later**. The interface is English. Scrolling is manual. Review recognised symbols and complex layouts against the source; see [limits](docs/help/limits.md).

[Build from source](docs/help/development.md) · [Release preparation](others/release/README.md) · [Privacy](docs/legal/privacy.md)

## Licence

Copyright © 2026 PentagonToy. Baker’s source uses [GNU AGPL version 3](LICENSE) (`AGPL-3.0-only`). Fonts, models and other dependencies retain their own [licences and notices](docs/legal/third-party.md).

## Agent CLI

Baker includes a [JSON CLI](docs/help/cli.md) for local capture, recording, OCR, history and PDF conversion.
