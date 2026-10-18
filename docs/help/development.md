# Development builds

Normal use needs no Python path or JSON configuration. Developers can enable **Settings → Advanced → Developer overrides → Use external OCR runtimes** to select Python, model configuration and Tesseract paths.

## Local build

On a prepared Workspace Mac, run `others/builder/Build.command`. It checks runtimes, builds the app, validates PDF output, backs up the installed app and replaces it. It installs no packages and downloads no models. The [builder guide](https://github.com/PentagonToy/Baker/blob/main/others/builder/README.md) covers preparation and build-only checks.

The app contains the formula runtime and MFR model; the structured-PDF engine is optional. `VERSION` supplies the app version. Update it with `CHANGELOG.md` before packaging a release.

## Runtime packaging

Prepare standalone arm64 CPython 3.12 with `tools/formula-requirements.txt` and a local Tesseract installation. Keep generated files outside the checkout:

```sh
python tools/bundle_runtime.py --destination /external/build/runtime --tesseract /absolute/path/to/tesseract
BAKER_RUNTIME_DIRECTORY=/external/build/runtime BAKER_FORMULA_MODELS_DIRECTORY=/external/build/prepared-engine BAKER_BUILD_DIRECTORY=/external/build/app ./tools/prepare_app.sh
```

The runtime tool copies the standalone interpreter and dependencies, retains notices, relocates non-system libraries and checks imports. The app build stages pinned image tools offline, relocates Potrace’s private library and signs nested native binaries. See [image-tool packaging](https://github.com/PentagonToy/Baker/tree/main/others/image-tools).

Current packaged libraries require macOS 26.0 for capture and 26.2 for PDF conversion. The Swift source target of macOS 14 does not establish compatibility with those older systems. The runtime manifests determine the packaged minimum.

Use `BAKER_SIGN_IDENTITY` for a distribution signing identity. Ad-hoc signing supports local development; it provides no notarisation. After building, `tools/package_dmg.sh /path/to/Baker.app /external/build/Baker.dmg` creates and verifies the disk image. See [release preparation](https://github.com/PentagonToy/Baker/blob/main/others/release/README.md) for final checks.

## Signing

The builder accepts a `signing_identity` in its ignored local configuration and passes it to nested native files and the app. Without one it uses ad-hoc signing, whose designated requirement changes with the binary and can invalidate privacy permission records across builds.

Developer ID requires [Apple Developer Program membership](https://developer.apple.com/programs/whats-included/). A self-signed local code-signing certificate can provide a stable identity for development, but does not provide Developer ID distribution or notarisation; permission retention still needs testing. Creating or trusting a certificate changes the login keychain and requires the owner’s consent. Keep its private key out of the repository. See [Apple’s code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

## Unbundled development

```sh
BAKER_BUILD_CONFIGURATION=debug BAKER_BUILD_DIRECTORY=/external/build/debug ./tools/prepare_app.sh
```

Enable developer overrides, select Python with the pinned formula requirements and prepare a model with `tools/provision_formula_model.py`. Its `baker-config.json` supports decoding experiments. `BAKER_BUILD_SYSTEM=native` remains available for affected Swift toolchains.

## Models and PDF distribution

`tools/optimize_document_models.py` prepares MFR `mlp-int8-v1`: encoder feed-forward matrices use INT8; attention and decoder remain FP32. It checks pinned inputs and records the recipe and output hashes. Formula setup maintains a separate variant cache and repairs from the included model.

The PDF engine lazily loads mixed-precision GLM-OCR and exits after each job. Recognition and reconstruction remain separate, allowing text and geometry changes to be checked against cached page results. [Models and references](recognition.md) records the selected engines, source revisions and validation.

The builder creates an engine archive and pinned descriptor, tests extraction and compares PDF output. Follow the [PDF distribution procedure](https://github.com/PentagonToy/Baker/blob/main/others/builder/PDF-DISTRIBUTION.md) when changing its payload.

## Formula measurements

An M1 Pro comparison processed 31 formula images in fresh subprocesses with two worker threads per variant.

| Measurement | Original FP32 | MLP INT8 and sequential sessions |
| --- | ---: | ---: |
| Encoder file | 83.5 MiB | 43.2 MiB |
| Median worker peak RSS | 259.4 MiB | 179.7 MiB |
| Median end-to-end worker time | 1.32 s | 1.19 s |

LaTeX matched in 28 cases; the other three had reviewed formatting differences. A separate 15-crop comparison found one spacing difference. These samples establish neither general OCR accuracy nor whole-app memory usage.

## Code ownership

Workbench forwards UI commands to capture, recognition, document, clipboard, storage and export coordinators. CaptureLibrary bounds its thumbnail cache to six images and serialises formula writes. WorkspaceWindows retains workspace content; ordinary Settings reopening preserves its page, while recovery actions select their destination. Shutdown cancels and awaits active work.

`PreferenceKeys` declares persisted names, types and defaults. `BakerPreferences` receives an explicit `UserDefaults` domain shared with SwiftUI bindings. Migrations preserve existing selections. `BakerError` codes determine recovery guidance; UI alerts omit bounded technical diagnostics and cancellation.

CaptureStore serialises archive access. Imports preserve the source on failure. PNG/SVG format replacement retains capture identity and uses a recovery journal. Recordings use a separate index and bounded first-frame previews. Recognition workers run per job rather than remaining resident.

ProcessCompletion observes termination before launch and wakes waiting callers. A 100 ms watchdog checks cancellation and output limits; PDF progress reads occur at most every 250 ms and read up to 16 KiB. Monotonic deadlines allow two seconds for termination before killing and reaping a child. Failure diagnostics retain at most 500 characters from the final 2 KiB of a log.

## Focused checks

Run each tool with `--output /absolute/path/outside/the/repository`. Checks interpret Swift without building or installing the app.

| Tool | Coverage |
| --- | --- |
| `tools/test_preferences.py` | Preference compatibility, migration, errors and recovery |
| `tools/test_workflows.py` | Ownership, cancellation, cache bounds and clipboard precedence |
| `tools/test_lifecycles.py` | Retained windows, settings state and PDF process protocol |
| `tools/test_capture_editor.py` | Drawing, masking, palette and repeat-area geometry |
| `tools/test_history_retention.py` | Retention, missing-file reconciliation and recoverable removal |
| `tools/test_image_tools.py` | Tracing, transparency, Undo, PNG/SVG replacement and SVG clipboard |
| `tools/test_background_removal.py` | Smooth light/dark backgrounds, filled figures and foreground preservation |
| `tools/test_updates.py` | Stable app release selection, daily opt-in scheduling, offline failures and cancellation |
| `tools/test_permissions.py` | Permission refresh and safe reopen arguments without modifying macOS settings |

`tools/test_recording_history.py` additionally needs `--fixtures` containing authored `synthetic.mp4` and `synthetic.gif`. Source checks supplement installed-app tests for recording, window focus, cancellation and clean-machine compatibility.
