# Baker PDF Engine 1.0.0

Optional local PDF recognition runtime for Apple Silicon Macs running macOS 26.2 or later. This is an engine release, not a new Baker app release. Baker 0.0.1 already includes its PDF engine; existing users do not need to install this archive manually. The lighter app will download and verify this asset when PDF conversion is first requested.

## Included

- Native PDF text reuse and Baker Markdown/LaTeX reconstruction.
- DocLayout-YOLO exported to ONNX for page layout.
- Quantised GLM-OCR through MLX, with 4-bit language weights, 8-bit vision linear layers and the corrected Baker LoRA adapter.
- Relocatable Python runtime, inference libraries, upstream notices and model provenance.

The selected weights and adapter are unchanged from the tested 0.0.1 engine. This package excludes the separate capture-formula MFR model. It is about 1.06 GB to download and 1.55 GB unpacked. No user documents, captures or evaluation papers are included.

## Files

- `Baker-PDF-Engine-1.0.0-arm64.tar.gz`: the complete optional engine.
- `Baker-PDF-Engine-1.0.0-source.tar.gz`: corresponding source, build/packaging tools, dependency source material and authored adapter-training inputs.
- `pdf-engine.json`: pinned download and installation descriptor.
- `PROVENANCE.json`: base-model lineage, adaptations and limits.
- `release-manifest.json` and `SHA256SUMS`: release metadata and checksums.

Baker source uses AGPL-3.0-only; dependencies and model material retain their own licences. Native components are ad-hoc signed and not notarised. Do not run unverified archives; the app verifies the pinned archive and complete file inventory before installing it outside the application bundle.

## Validation and limits

Local extraction/integrity checks, byte-identical research-PDF Markdown and complex-table cells/captions passed on an M1 Pro with 16 GB RAM. The small authored training corpus does not establish general accuracy gains over the base checkpoint. Review names, equations and complex table structure. Separate clean-Mac validation remains pending.

[Models and references](https://pentagontoy.github.io/Baker/help/recognition.html) · [App release](https://github.com/PentagonToy/Baker/releases/tag/v0.0.1)

Public round-trip verification passed: the complete engine was downloaded from this release through Baker’s setup client, checked, installed in a fresh folder and reopened. A two-page research PDF produced byte-identical accepted Markdown. This ran on the same M1 Pro, not a separate clean Mac.
