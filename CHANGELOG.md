# Changelog

## Unreleased

- Separate the optional PDF runtime and models from the base app while keeping capture formula recognition included.
- Add PDF engine download, progress, cancellation, verified installation and removal controls; queued PDFs continue after installation.
- Keep the published 0.0.1 release unchanged. PDF Engine 1.0.0 is published separately and passed public download, installation and PDF-output checks.

## 0.0.1 — 2026-10-17

First preview for Apple Silicon Macs.

### Capture and recording

- Capture the active monitor, an area, text or a formula, with configurable global shortcuts shown in the menu.
- Join manually scrolled pages and record short silent MP4 videos or GIFs.
- Copy, save, drag, pin and edit captures from a consistent thumbnail stack.
- Keep workspaces open during capture and show a centred selection hint that disappears on drag.

### Recognition and documents

- Recognise formulas locally, compare original and rendered previews, and copy LaTeX, Markdown maths, Keynote or Unicode.
- Import formula images by dropping files or edited capture thumbnails into a new-image area in Formula Workspace. New clears preview, confidence and copy fields while preserving searchable history.
- Render legacy scoped LaTeX font declarations, including `\bf`, and use the available width for confidence.
- Preserve original capture pixels in formula previews and display their dimensions.
- Convert PDFs to structured Markdown or LaTeX with equations, tables, figures and page-based progress estimates.
- Recover first-page author names, affiliation superscripts and supported correspondence markers from native PDF text.
- Preserve ordinary numeric styling when native PDF fonts confirm that digits are not bold.
- Select up to three text OCR languages from English, German, Korean, Swedish, Danish and Finnish.

### Storage and setup

- Choose one save folder for images and formula history, with portable settings presets in a subfolder.
- Prepare included recognition models without asking for Python paths.
- Build, validate, back up and replace the local app with the automatic builder.

### Performance

- Release document models when a PDF job ends and bound retained recognition buffers.
- Read saved document sizes without allocating another full-file buffer.
- Quantise MFR encoder feed-forward matrices to INT8 while retaining FP32 attention and decoder weights.
- Prepare Apple text OCR in the background at launch using a generated sample.
- Release encoder sessions before loading the decoder to reduce formula-worker peak memory.
- Verify optimised-model hashes, retain their source revision and use a separate model cache.
- Use a mixed-precision GLM-OCR checkpoint and small Baker adapter for PDF regions, with native-text reuse and lazy model loading. Keep fast MFR capture recognition separate.
- Exclude PyTorch, Transformers and the general MLX-VLM launcher from the selected document runtime; this MLX build requires macOS 26.2 or later.

### Interface

- Customise menu section order, command order and visibility in Settings → Menu, then Apply without restarting.
- Register standard macOS app, editing and window commands, including ⌘Q, ⌘W and ⌘,.

- Use warm cream surfaces in Light appearance, including file lists and rendered formula previews.
- Keep a rolling scrolling-capture preview instead of replacing it with individual strips.
- Save Text and Formula captures without quick-preview thumbnails; copy recognised text before updating the result view.
- Start menu capture after menu tracking ends and use one Open Files entry for images and PDFs.
- Add System, Light and Dark appearance, matching sidebar logos, the catchphrase and version. Place storage and preset controls below clipboard preferences.

### Limits

Scrolling is manual and downward only. Recording has no audio. The complete build requires Apple Silicon and macOS 26.2 or later. Recognition remains approximate; review mathematical symbols and complex document layouts against the source.

