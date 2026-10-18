# Next Baker preview — draft

The next planned app version is 0.0.3. This is source preparation; `VERSION` and the installed app remain 0.0.2 until a release candidate is built and checked.

## Changes to review

- Preserve Settings state when reopening and use one owner for workspace window lifecycles.
- Observe PDF process completion directly, retain bounded cancellation and diagnostics, and reduce progress-file reads without changing the recognition models.
- Include the pending capture editor, Repeat Area, unified recording with optional system audio, durable media history, multilingual text OCR, Unicode output and menu/settings improvements described in the Unreleased changelog.
- Review background removal, vector Undo/Redo, one-file PNG/SVG replacement and SVG history previews. Check the relocated Potrace library and bundled VTracer on a clean Mac before publishing.

## Before publication

1. Build and install the final candidate with the prepared builder. Test close/reopen, settings recovery navigation, ordinary macOS shortcuts, capture overlays and workspace focus.
2. Test video with system audio, silent GIF and history persistence after quitting. Confirm existing captures and preferences remain available.
3. Run the accepted PDF comparison and verify cancellation, progress and a missing-engine recovery path in the installed app.
4. Update `VERSION` and the changelog for the agreed release, then build the exact final source. Verify signatures, corresponding source, notices and model hashes; package and check the DMG with its checksums.
5. Commit the reviewed source, tag the tested commit and publish matching assets. Keep the optional PDF engine release unchanged unless its payload changes.

Source checks completed for the window/PDF changes: 33 window-lifecycle checks, 13 PDF-process checks, 27 process/reliability checks and 90 preference/error checks. These checks do not establish live recording, window focus, installed OCR quality or clean-machine compatibility.

## Homebrew plan

Keep the app and cask name **Baker** (`baker`). The intended first step is a maintained tap using the same versioned DMG and SHA-256 as the direct download. Add a beginner-facing brew command to README only after that tap is published and installation is verified. No Homebrew package is currently offered. Official Homebrew inclusion additionally requires its acceptance and Gatekeeper checks; the current ad-hoc, unnotarised app has not passed those distribution gates.
