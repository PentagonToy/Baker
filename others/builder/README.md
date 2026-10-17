# Build Baker

Double-click **[Build.command](Build.command)** in Finder to build, check, back up and replace the local Baker app. The builder opens Baker when installation succeeds. The app is installed in `/Applications/Baker.app`. The repository’s `Baker.app` link opens that app.

The build includes the formula runtime, the high-quality PDF runtime and its local models. PDF recognition starts only when needed; the document process exits after conversion. This preview is substantially larger than the capture-only app.

## Before the first build

This Mac needs the command-line build tools, the prepared Workspace Python environment and the validated document models. The builder checks these dependencies and stops if anything is missing. It does not install packages, download models, change your Python environment or publish to GitHub.

Machine paths live in `builder.local.json`, which Git ignores. This Mac is already configured, including a separate table-page check. The selected configuration uses `small_ocr_payload` for the verified standalone OCR bundle and `formula_models` for the existing fast MFR model directory. Packaging checks the selected bundle hashes before copying it. The builder derives the minimum macOS version from its native libraries; the current MLX payload requires macOS 26.2.

On another prepared Mac, copy `builder.example.json` to `builder.local.json` and select the verified payload, formula models, example PDF and accepted Markdown result. The legacy `document_configuration` path remains available for Pix2Text builds. The builder selects the M1 Pro or M5 environment after checking the hardware.

## What happens

1. Check the tools, runtime, models, disk space and installation target.
2. Verify the selected payload and package the small PDF engine together with the fast MFR capture model. Legacy configurations prepare the validated MFR INT8 variant and Pix2Text runtime.
3. Build the release app using `VERSION` and sign its native components.
4. Verify the app signature and convert the example PDF with the bundled engine.
5. Compare Markdown with the accepted example and check configured table cells and captions.
6. Back up the existing app, ask it to quit normally, replace it and open Baker.

A failed build or PDF comparison leaves the installed app unchanged. A failed final installation check restores the previous app. The builder refuses concurrent builds and never force-quits Baker. Interrupted build locks require checking the recorded PID before removal.

Build reports, logs, PDF checks and previous apps remain under `Workspace/Agents/Repository/baker/builder`. Backups are retained; remove unwanted old build folders manually after checking their contents. Your captures and settings remain outside the app bundle.

## Other runs

Run these from the prepared Workspace Python environment:

```sh
python others/builder/build.py --check
python others/builder/build.py --build-only
python others/builder/test_builder.py
```

`--check` checks preparation without building. `--build-only` builds and tests without replacing or opening the installed app. The local build uses ad-hoc signing unless `signing_identity` is configured. macOS may request screen-recording permission again after replacement.

The bundled document dependencies include components with their own licences. Their installed licence files and version manifest are retained. Review [third-party notices](../../docs/legal/third-party.md) before distributing a build.
