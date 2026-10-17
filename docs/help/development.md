# Development builds

User setup and development configuration are separate. Normal use needs no Python path or JSON configuration. **Settings → Advanced → Developer overrides → Use external OCR runtimes** lets developers select their own Python, model configuration and Tesseract executable. Existing path preferences are retained, but are inactive until this override is enabled.

## Automatic local build

On a prepared Workspace Mac, double-click `others/builder/Build.command`. It checks the configured runtime and models, builds the app, validates PDF output, backs up the installed app and replaces it safely. It does not install packages or download models. See the [builder guide](https://github.com/PentagonToy/Baker/blob/main/others/builder/README.md) for preparation and build-only checks.

The published 0.0.1 app contains both runtimes. New development builds keep the formula runtime and its MFR model in the app and package the structured-PDF engine separately. The PDF pipeline combines layout, formula and table recognition with native PDF characters. Recognition and reconstruction are separate so geometry or text corrections can be checked against cached page results without rerunning every model.

The validated bundled MFR `mlp-int8-v1` variant is prepared with `tools/optimize_document_models.py`: feed-forward encoder matrices use INT8; attention and decoder weights remain FP32. The tool verifies the pinned upstream files and records the recipe, source revision and output hashes. Models are generated outside the checkout. Formula setup uses a separate variant cache and repairs from the included model; it does not request the upstream FP32 file under an INT8 checksum.

The selected PDF engine uses native-text reuse, ONNX layout detection and mixed-precision GLM-OCR with the corrected Baker adapter. MLX model loading is lazy and the worker exits after each job. The standalone runtime excludes PyTorch, Transformers and the general MLX-VLM launcher. See [models and references](recognition.md) for source revisions, provenance and measured limits.

`VERSION` supplies the app's short version. Update it with `CHANGELOG.md`; the builder checks that the packaged version matches.

## Formula runtime packaging

Use a standalone arm64 CPython 3.12 build environment with the pinned `tools/formula-requirements.txt` packages, plus a local Tesseract installation. Run the packaging tool from that environment and keep generated files outside the checkout:

```sh
python tools/bundle_runtime.py --destination /external/build/runtime --tesseract /absolute/path/to/tesseract
BAKER_RUNTIME_DIRECTORY=/external/build/runtime BAKER_FORMULA_MODELS_DIRECTORY=/external/build/prepared-engine BAKER_BUILD_DIRECTORY=/external/build/app ./tools/prepare_app.sh
```

The runtime tool copies the standalone interpreter and the required package distributions, preserves their notices, relocates non-system Tesseract libraries and tests imports. It does not copy a virtual environment or change the user's Python installation. The app build signs nested native binaries and sets its minimum macOS version from the runtime manifest. Use an appropriate `BAKER_SIGN_IDENTITY` for distribution; ad-hoc signing supports local development and does not provide notarisation.

Current local Tesseract dependencies require macOS 26; the selected document engine raises the complete build requirement to macOS 26.2. Building the source app for macOS 14 does not make those binary libraries compatible with macOS 14. Prepare and test an older-target runtime before advertising that compatibility.

After building, `tools/package_dmg.sh /path/to/Baker.app /external/build/Baker.dmg` creates a drag-to-Applications disk image and verifies it. This does not notarise the app.

## Development without bundled engines

```sh
BAKER_BUILD_CONFIGURATION=debug BAKER_BUILD_DIRECTORY=/external/build/debug ./tools/prepare_app.sh
```

Enable Developer overrides for an unbundled build. Set Python to an environment containing the pinned formula requirements, and prepare a model with `tools/provision_formula_model.py`. The generated `baker-config.json` remains available for experiments with decoding limits. Builds using an affected Swift toolchain can select `BAKER_BUILD_SYSTEM=native`; that engine is a temporary workaround.

## 0.0.1 measurements

On an M1 Pro with two worker threads, 31 formula images were processed in fresh subprocesses for each variant.

| Measurement | Original FP32 | MLP INT8 and sequential sessions |
| --- | ---: | ---: |
| Encoder file | 83.5 MiB | 43.2 MiB |
| Median worker peak RSS | 259.4 MiB | 179.7 MiB |
| Median end-to-end worker time | 1.32 s | 1.19 s |

These are single-batch worker measurements, not whole-app or PDF memory guarantees. LaTeX matched exactly in 28 of 31 cases; three formatting differences were reviewed. A separate 15-crop comparison had one spacing difference. No new symbol or numeric change was found in these comparisons; this is not a general accuracy score. PDF measurements and limitations are recorded in [models and references](recognition.md).

## Optional PDF distribution

The builder creates a separate PDF engine archive and pinned descriptor, tests extraction through the base app’s Python runtime, and compares the installed engine’s PDF output. No download service or Python package installation is required on the user’s Mac. See the [PDF distribution procedure](https://github.com/PentagonToy/Baker/blob/main/others/builder/PDF-DISTRIBUTION.md) in the source repository for local packaging, acceptance and later upload steps. PDF Engine 1.0.0 is published and its public download/install path has passed acceptance. The current descriptor enables that pinned asset. The current base runtime requires macOS 26.0; the optional MLX PDF engine requires 26.2. This is a binary-library requirement, not a change to the source deployment target.
