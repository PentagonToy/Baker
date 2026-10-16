<picture>
  <source media="(prefers-color-scheme: dark)" srcset="others/assests/banner/baker_banner_dark.svg">
  <img src="others/assests/banner/baker_banner_light.svg" alt="Baker" width="960">
</picture>

# Baker

Capture a screen region, recognise text or maths, and put the result where you work. Baker lives in the macOS menu bar, with local processing and small panels that open when needed.

[Getting started](docs/getting-started.md) · [User guide](docs/README.md) · [Settings](docs/settings.md)

## Features

| Task | Output |
| --- | --- |
| Area or scrolling capture | Image to copy, save, drag or pin |
| Text recognition | Editable text and clipboard output |
| Formula recognition | LaTeX, Markdown maths, Keynote or Unicode |
| PDF text conversion | Markdown or LaTeX document |
| Short screen recording | Silent MP4 or animated GIF |

Unicode maths stays editable in ordinary text fields. Choose STIX Two Math, STIX or Latin Modern Math in Settings; copying includes plain Unicode and formatted text with the selected font.

## Get started

Open Baker and click its menu-bar icon. Choose **Text** or **Formula**, select a region, and paste the recognised result into your document. Use **Settings…** to select the maths font and clipboard behaviour.

Baker is a source preview; formula recognition needs a separately prepared local model. See [setup](docs/getting-started.md) before the first formula capture.

## Requirements

| Item | Support |
| --- | --- |
| Platform | Apple Silicon, macOS 14 or later |
| Supported language | English interface; OCR input depends on the recognition engine |
| Screen capture | macOS Screen Recording permission |
| Formula OCR | Local Python runtime and formula model |

PDF conversion currently extracts text; complex equations, tables and page layout need review. Recording is silent. Read the [PDF guide](docs/clipboard-and-files.md) and [recording limits](docs/record.md) and [troubleshooting guide](docs/troubleshooting.md) for details.
