# Changelog

## Unreleased

- Use a square-root icon for Formula Workspace, with a compatible fallback on older systems.

- Make Scan cancellation and overlapping source selection safe, retain recoverable drafts and support Down Arrow page turns.
- Send a saved capture to Trash only through its thumbnail close action.
- Preserve delimited formula rows and annotations in previews and Keynote output. Align formula status and style controls.
- Add macOS build CI and standard core tests. Align the Swift package minimum with macOS 26.0.

## 0.1.1 — 2026-10-27

- Collect screen pages in a recoverable Scan draft, review their order and save one PDF with optional on-device searchable text.
- Choose a reader from window previews, capture the whole window or an area within it, and turn pages without moving the pointer. Include automatic stopping, manual capture and CLI inspection, pause, resume and draft recovery.
- Prepare capture and control permissions together on first launch.
- Simplify website navigation into three tabs with collapsible task groups.
- Refine Scan controls, pause/resume actions and review thumbnails.

## 0.1.0 — 2026-10-27

- Distribute Baker with Developer ID signing and Apple notarisation.
- Release closed formula popover content to reduce retained resources.
- Cancel unused thumbnail requests and keep the image cache bounded.
- Cancel superseded image-copy work and expose its status in CLI diagnostics.

## 0.0.9 — 2026-10-26

- Add one optional OCR plugin from a ZIP, with explicit approval, Keychain credentials and separate priorities for formulas, Markdown and LaTeX.
- Support compact in-app plugin setup, a reusable login helper and separate plugin usage. Baker remains the local fallback; cancellation never retries.
- Harden ZIP imports, limit inherited process variables and remove saved credentials with their plugin.
- Align history controls and provider badges; offer 7-, 10-, 30- and 90-day formula retention.
- Display update notes with readable headings, lists, emphasis and links instead of raw Markdown.

## 0.0.8 — 2026-10-26

- Add one optional, approved OCR plugin with a generic JSON protocol and optional Keychain credentials.
- Keep local recognition as fallback, keep cancellation final and distinguish local and plugin usage.

## 0.0.7 — 2026-10-26

- Process image, formula and PDF recognition locally, with no OCR account login or cloud conversion.
- Offer Pix2Text, Texo and PP-FormulaNet plus-S as separate verified model downloads; retain the optional offline PDF engine.
- Keep capture editing, recording, formula history, direct copy, confirmed metadata deletion and the agent CLI.
- Preserve local usage counts and saved results when upgrading from an earlier installation.

This repository starts from the local-processing edition. Earlier release history is not mirrored here.
