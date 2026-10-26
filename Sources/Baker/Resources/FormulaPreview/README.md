# Offline formula preview

KaTeX 0.19.0 is vendored from https://registry.npmjs.org/katex/-/katex-0.19.0.tgz, with its mhchem extension and all distributed font formats. `vendor.json` records the upstream npm SHA-512 integrity value and SHA-256 hashes of the retained distribution files. The archive integrity was verified before extraction. These files are unchanged; Baker's wrapper is `index.html`, `preview.css` and `preview.js`.

The complete folder is copied by SwiftPM and `tools/prepare_app.sh`. Runtime loading uses local files only. Retain `LICENSE`, `MHCHEM-NOTICE.txt` and `MHCHEM-APACHE-2.0.txt` when redistributing it. The mhchem source attribution identifies the MIT adaptation and its Apache-2.0 MathJax ancestry.

Run `tools/test_formula_preview.py --output <external-evidence-directory>` with the designated agent Python to verify the pinned resources and exercise the current Swift renderer through WebKit without building or installing Baker. The test requires a logged-in macOS GUI session. The retained native BakerCore renderer remains available for its separate regression tests; the app uses `FormulaPreviewRenderer`.
