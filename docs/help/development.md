# Development builds

Normal use needs no Python path or JSON configuration. Developers can enable **Settings → Advanced → Developer overrides → Use external OCR runtimes** to select Python, model configuration and Tesseract paths.

## Local build

On a prepared Workspace Mac, run `others/builder/Build.command`. It checks runtimes, builds the app, validates PDF output, backs up the installed app and replaces it. It installs no packages and downloads no models. The [builder guide](https://github.com/PentagonToy/Baker/blob/main/others/builder/README.md) covers preparation and build-only checks.

The app contains the formula runtime; formula weights and the structured-PDF engine download separately. `VERSION` supplies the app version. Update it with `CHANGELOG.md` before packaging a release.

## Runtime packaging

Prepare standalone arm64 CPython 3.12 with `tools/formula-requirements.txt` and a local Tesseract installation. Keep generated files outside the checkout:

```sh
python tools/bundle_runtime.py --destination /external/build/runtime --tesseract /absolute/path/to/tesseract
BAKER_RUNTIME_DIRECTORY=/external/build/runtime BAKER_BUILD_DIRECTORY=/external/build/app ./tools/prepare_app.sh
```

The runtime tool copies the standalone interpreter and dependencies, retains notices, relocates non-system libraries and checks imports. The app build stages pinned image tools offline, relocates Potrace’s private library and signs nested native binaries. See [image-tool packaging](https://github.com/PentagonToy/Baker/tree/main/others/image-tools).

Current packaged libraries require macOS 26.0 for capture and 26.2 for PDF conversion. The Swift source target of macOS 14 does not establish compatibility with those older systems. The runtime manifests determine the packaged minimum.

Use `BAKER_SIGN_IDENTITY` for a distribution signing identity. Ad-hoc signing supports local development; it provides no notarisation. After building, `tools/package_dmg.sh /path/to/Baker.app /external/build/Baker.dmg` creates and verifies the disk image. See [release preparation](https://github.com/PentagonToy/Baker/blob/main/others/release/README.md) for final checks.

## Signing

The builder and `tools/prepare_app.sh` select signing in this order:

1. `BAKER_SIGN_IDENTITY`.
2. `signing_identity` in the ignored `others/builder/builder.local.json`.
3. An opt-in certificate fingerprint in `~/Library/Application Support/PentagonToy/Development/signing-identity`, also supported by remile.
4. Ad-hoc signing when none is configured.

A configured identity that cannot sign fails the build. The fingerprint file contains no private key. Keep the certificate and private key in Keychain.

Ad-hoc identity changes can invalidate privacy permissions after rebuilding. A fixed self-signed identity preserved Screen Recording permission across a tested rebuild and replacement on one development Mac. Other systems still require validation. Switching from an existing ad-hoc build can need one fresh approval.

Local signing provides neither Developer ID nor notarisation. Public Developer ID distribution requires [Apple Developer Program membership](https://developer.apple.com/programs/whats-included/). Creating or trusting a certificate requires the owner’s consent. See [Apple’s code-signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

## Unbundled development

```sh
BAKER_BUILD_CONFIGURATION=debug BAKER_BUILD_DIRECTORY=/external/build/debug ./tools/prepare_app.sh
```

Enable developer overrides, select Python with the pinned formula requirements and prepare a model with `tools/provision_formula_model.py`. Its `baker-config.json` supports decoding experiments. `BAKER_BUILD_SYSTEM=native` remains available for affected Swift toolchains.

## Models and PDF distribution

`tools/optimize_document_models.py` prepares MFR `mlp-int8-v1`: encoder feed-forward matrices use INT8; attention and decoder remain FP32. It checks pinned inputs and records the recipe and output hashes. Existing variant caches remain usable. New installs and repairs download the verified optimised model from GitHub Releases. Base-app packaging strips formula weights from reused runtimes and retains only pinned descriptors and workers.

Use `tools/optimise_plus_s.py` and `tools/package_plus_s.py` for the optional plus-S FP32 CPU model. The [model package guide](../models/README.md) records export repairs, licence notices, validation and versioned release assets. Formula runtime requirements also include the small `ftfy` and `wcwidth` text-repair dependencies; regenerate the relocatable runtime when adding plus-S to an older build.

The PDF engine lazily loads mixed-precision GLM-OCR and exits after each job. Recognition and reconstruction remain separate, allowing text and geometry changes to be checked against cached page results. [Models and references](recognition.md) records the selected engines, source revisions and validation.

The builder creates an engine archive and pinned descriptor, tests extraction and compares PDF output. Follow the [PDF distribution procedure](https://github.com/PentagonToy/Baker/blob/main/others/builder/PDF-DISTRIBUTION.md) when changing its payload.

## Code ownership

Workbench forwards UI commands to capture, recognition, document, clipboard, storage and export coordinators. CaptureLibrary bounds its thumbnail cache to six images and serialises formula writes. WorkspaceWindows retains workspace content; ordinary Settings reopening preserves its page, while recovery actions select their destination. Shutdown cancels and awaits active work.

`PreferenceKeys` declares persisted names, types and defaults. `BakerPreferences` receives an explicit `UserDefaults` domain shared with SwiftUI bindings. Migrations preserve existing selections. `BakerError` codes determine recovery guidance; UI alerts omit bounded technical diagnostics and cancellation.

CaptureStore serialises archive access. Imports preserve the source on failure. PNG/SVG format replacement retains capture identity and uses a recovery journal. Recordings use a separate index and bounded first-frame previews. Recognition workers run per job rather than remaining resident.

Formula Workspace decodes the original only in Original or Both mode, limiting its display copy to 2,048 pixels on the longest side. Recognition, copying and exports retain the saved file. The formula renderer accepts up to 16 waiting requests; clearing its cache cancels pending work and releases the app’s WebKit view. Use the [CLI diagnostics](cli.md) to inspect app memory and work queues without loading models or clearing data.

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

## Interface conventions

Keep Baker's warm accent for the current selection and primary action. Shared action buttons use 32-point hit areas, visible neutral borders and a keyboard-focus outline; menus and segmented controls retain native behaviour. Toolbar labels use equal icon slots and compact automatically when space is limited. Supporting text stays at least 13 points. Use the shared surfaces and short state transitions, and honour Reduce Motion.

Check narrow windows, keyboard focus, light and dark appearances, empty states, downloads and failures before shipping an interface change. Type checks and colour calculations do not replace inspection of the running app.
