# Baker action symbols

These original Baker SVGs use a 24 × 24 view box, 1.7-unit rounded strokes and monochrome template rendering. They are editable source assets, not exports from the reference applications.

- `capture-all.svg`: a monitor and full-display brackets.
- `capture-text.svg`: region brackets and a text glyph.
- `capture-formula.svg`: region brackets and a summation glyph.
- `capture-scroll.svg`: content lines and a bidirectional vertical arrow.

Packaging copies SVGs into the app resources. AppKit renders and caches them at 18 points as template images so macOS supplies tint. Generated previews and icon renditions belong under `Agents/Repository/baker`, outside this source directory.

Area, Video, GIF, Files, Clipboard Image, Clipboard Text, PDF, History and Settings also have original SVG sources here. The menu and documentation use the same geometry; dark documentation variants live under `docs/assets/symbols`.
