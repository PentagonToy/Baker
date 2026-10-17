# Optional PDF engine

The base app includes capture, text OCR, formula OCR and their runtime. Only structured PDF conversion needs the separate engine. The published 0.0.1 release remains unchanged; the [PDF Engine 1.0.0 release](https://github.com/PentagonToy/Baker/releases/tag/pdf-engine-v1.0.0) is available separately and passed public round-trip verification.

## Package locally

Use the prepared Workspace Python 3.12 environment and a tested small-engine directory. Generated outputs must remain outside the checkout.

```sh
python others/builder/package_pdf_engine.py --source /path/to/DocumentEngine --destination /external/build/pdf-package
```

The output contains `Baker-PDF-Engine-1.0.0-arm64.tar.gz`, `pdf-engine.json`, `SHA256SUMS` and an unpacked `PDFEngine` for inspection. The archive includes the quantised GLM checkpoint, corrected Baker adapter, layout model, relocatable Python runtime, inference code, licences and provenance. It excludes the capture MFR model, which belongs in the base app. Native files are signed before the package inventory and archive hash are generated. Use `--signing-identity` for a configured distribution identity; the default is ad-hoc signing, without notarisation.

Archive timestamps and ownership metadata are normalised so an unchanged payload has a stable archive hash. Keep `pdf_distribution` in the local builder configuration pointed at the accepted package directory to reuse that exact archive for app-only builds.

The descriptor pins the exact archive size, SHA-256, unpacked size, inventory hash, architecture, minimum macOS version and URL. `available` defaults to `false`: packaging cannot make an unpublished download appear ready. Treat the archive as immutable after acceptance; a changed payload needs a new engine ID and a matching descriptor, not a silent replacement at the same URL.

## Build and verify

The configured builder defaults to a separate engine when `small_ocr_payload` is selected. `--build-only` preserves the installed app. It checks archive extraction and the accepted PDF/table results before reporting success. Set `include_pdf_engine: true` in the local configuration when an all-in-one offline build is required.

While the descriptor has `available=false`, the builder refuses to replace the installed app with a separate-engine build. Use build-only checks or select the complete offline build until the download is published.

For a direct base-app build, pass `BAKER_FORMULA_MODELS_DIRECTORY` pointing to the prepared directory containing `mfr` and `formula-model.json`, and `BAKER_PDF_ENGINE_MANIFEST` pointing to the generated descriptor. Omit `BAKER_DOCUMENT_ENGINE_DIRECTORY`. The app packager removes a stale bundled DocumentEngine from reused output folders, and retains the MFR model under Runtime.

The installer runs from the base app’s Python runtime. It checks the entire archive before extraction, rejects escaping paths/links and special files, enforces the unpacked-size limit, then verifies every extracted file against the pinned inventory. The app stages installation beside the final engine directory and preserves an existing installation until verification succeeds. Cancellation removes the pending archive and staging directory. A completed installation receipt identifies the exact accepted archive.

Test a fresh installation, corrupt/truncated downloads, cancellation/retry, insufficient disk space, installation failure, deletion and a second launch. Confirm that capture/formula OCR work without a PDF engine and that queued PDFs continue after installation. Run the accepted research PDF and complex-table comparisons through the extracted runtime. A local archive test does not establish that a future public URL works; repeat the download path after publishing the asset, before releasing the lighter app.

```sh
python others/builder/test_pdf_engine.py
python others/builder/test_builder.py
```

## Publish later

After acceptance and explicit publication approval, create a separate engine release such as `pdf-engine-v1.0.0` and upload the exact tested archive, its checksums, provenance and corresponding source material. Keep the application release separate and mark the engine release as non-latest so it does not replace the app’s Latest download. Model-only weights are insufficient for a user who has no Python or inference libraries installed.

Verify the public download size and SHA-256. Only then set `available` to `true` in the descriptor packaged with the next app build. Keep the URL and hashes pinned in the app; do not discover or execute an arbitrary “latest” engine from a mutable remote manifest. The current descriptor enables the verified 1.0.0 release. New packages still default to a disabled descriptor until their own public verification succeeds.

The user sees the download and installed sizes before confirming. Settings → PDF Conversion offers progress, cancellation, reinstall and removal. The first queued PDF can download the engine and continue automatically. Installed files live under `~/Library/Application Support/Baker/Engines/pdf-engine-v1.0.0`; removing them does not delete captures, history or exports. Future engine versions should retain compatibility checks and avoid redownloading unchanged weights unnecessarily.
