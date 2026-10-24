# Changelog

## Unreleased

- Add optional Mathpix Snip account sign-in in Advanced, a Baker/Mathpix selector, local fallback when offline, and separate on-device usage counts. Keep session tokens in Keychain; online LaTeX PDF exports use `.tex.zip`.
- Name new captures `baker_<type>_<timestamp>` using `formula`, `image`, `video` or `gif`, with collision suffixes. Keep existing filenames and preserve the stem when editing or converting to SVG.

## 0.0.5 — 2026-10-24

- Choose Pix2Text, Texo or PP-FormulaNet plus-S as a verified, optional formula download. Keep weights outside the base app and reuse installed models.
- Prepare the selected model directly in Quick Start after Screen Recording permission.
- Fit capture thumbnails to the display’s usable height, with optional fixed limits of one to five.
- Refine Settings, Workspace, History and the formula popover; align controls, simplify model management and dismiss the popover on outside clicks.
- Improve dark-capture recognition, Keynote bold and multiline output, and the Last Capture format selector.
- Bound preview memory and rendering queues, cancel pending cache work, and add read-only CLI diagnostics for memory and active operations.

## 0.0.4 — 2026-10-22

- Add Window capture, an arranged drag-to-install DMG and a permission-first Quick Start covering formulas, scrolling, recording and history.
- Show captured formulas in a menu-bar popover. Refine Workspace and Settings cards, align menu icons and slow thumbnail movement between displays.
- Simplify Unicode styling and leave unsupported conversions empty. Show a warning only when Unicode is unavailable, strengthen thin preview rules and keep model scores distinct from verified accuracy.
- Release idle formula WebKit resources, bound preview retention and disable ONNX thread spinning.
- Manage the optional offline PDF model in Advanced and refine file-conversion actions. Captures and formula recognition remain independent of the PDF download.
- Add a bundled JSON CLI with fixed live-app commands and event-driven local IPC. Retain the app-neutral headless formula adapter.
- Reuse configured local signing identities across builds to preserve app identity and reduce repeated privacy approval.

## 0.0.3 — 2026-10-18
- Add manual update checks and optional daily GitHub release checks, with release notes and browser-based DMG downloads; exclude PDF engine releases and leave app replacement to the user.
- Handle smoothly shaded slide backgrounds while preserving text, thin axes and filled figures; retain the exact uniform-background path and reversible editing.
- Add Screen Recording status, System Settings access and an explicit reopen action without resetting privacy permissions or changing signing certificates.
- Add reversible background removal and colour or monochrome SVG tracing to the capture editor, using native Vision, VTracer and Potrace without a resident worker.
- Replace each edited capture with one PNG or SVG; preserve the original until Done succeeds, offer SVG-only preview actions in History and rasterise vectors in memory when reopening the thumbnail editor.
- Group image and formula history under General; default image retention to no count or age limit, review removals before using Trash and retain folder-specific approval for future captures.
- Reconcile missing capture files and linked formula metadata when clearing caches, opening history and starting Baker; preserve existing unreadable files and unavailable-folder errors.
- Retain workspace windows through one lifecycle owner; reopening Settings preserves the selected page and hosted view, while recovery actions select their intended page.
- Wake PDF waits on process termination, share bounded termination and diagnostic-tail handling, and reduce progress-file reads while retaining cancellation and output limits.
- Separate capture, recognition, document, clipboard, storage and export lifecycles from the UI model without adding a resident worker.
- Show thumbnail cards and media filters in Capture History; save recordings automatically alongside images and formulas, and put Open Capture Folder first in Recent.
- Use the summation symbol consistently for formula commands, and add copy feedback and reduced-motion-aware selection transitions.
- Increase control and supporting-text sizes, and remove language-picker footnotes.
- Centralise typed preference keys and defaults, preserve existing domains and make language migration idempotent.
- Require typed errors, retain their recovery guidance at UI boundaries and keep technical diagnostics out of ordinary alerts; bound PDF installer output through the shared process runner.
- Add up to five text OCR languages, including Arabic, Persian, Spanish, French, Chinese and Japanese, with bundled offline fallback models. Move language choices to Capture, shorten the PDF sidebar label and group settings by workflow.
- Reorder menu groups and commands using drag handles, with accessible move actions and explicit Apply/Revert controls.
- Add a compact capture editor with a built-in Okabe–Ito palette, white masking preset and undo/redo.
- Add Repeat Area with a separate shortcut, an authored symbol and validated per-display selection persistence.
- Preserve script scope on grouped sums and linear fractions, support scoped legacy fonts and OCR operator wrappers, and align Greek variants with the preview. Preserve unsupported structures exactly and warn on malformed syntax.
- Convert derivative primes and repeated or reverse primes to Unicode instead of preserving representable LaTeX.
- Combine recording under Capture → Record… with an area-adjacent Video/GIF setup panel, cursor option and compact elapsed-time controls; retain format shortcuts and migrate menu preferences.
- Add optional system audio to MP4 recording and extend limits to three minutes for video and 30 seconds for silent GIF, retaining frame-by-frame GIF export.
- Expand Unicode scripts, mathematical alphabets, accents and standard symbols; handle spaced invisible delimiters and report unsupported scripts and lost delimiter sizing accurately.
- Continue long formulas beyond the default 256-token budget up to the existing 512-token ceiling, without reloading models or extending the original deadline.
- Classify local recognition failures, retain bounded diagnostic tails and cap process output before loading it into memory; process completion now wakes its waiter directly.
- Coalesce concurrent thumbnail reads while retaining the six-image cache and cancelling obsolete reads on cache clear or storage changes.
- Offer login startup once and add a General setting that reflects macOS registration and approval status.

## 0.0.2 — 2026-10-17
- Render formula previews offline with bundled KaTeX and mhchem, covering accents, limits, aligned equations and chemical notation; retain source for unsupported input.
- Reuse one preview renderer, bound its image cache and isolate equation macros; block external resources and preserve copied LaTeX.
- Complete the 34 basic AMS operator names, add equilibrium arrows and preserve unsupported chemistry syntax and whitespace across output formats.
- Normalise OCR-spaced standard operators and preview fixed-size delimiters, multiple aligned pairs and piecewise cases.
- Separate the optional PDF runtime and models from the base app while keeping capture formula recognition included.
- Add PDF engine download, progress, cancellation, verified installation and removal controls; queued PDFs continue after installation.
- Use the separately published PDF Engine 1.0.0, verified through public download, installation and PDF-output checks.

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
