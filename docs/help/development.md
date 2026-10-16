# Development builds

User setup and development configuration are separate. Normal use needs no Python path or JSON configuration. **Settings → Advanced → Developer overrides → Use external OCR runtimes** lets developers select their own Python, model configuration and Tesseract executable. Existing path preferences are retained, but are inactive until this override is enabled.

## Complete application

Use a standalone arm64 CPython 3.12 build environment with the pinned `tools/formula-requirements.txt` packages, plus a local Tesseract installation. Run the packaging tool from that environment and keep generated files outside the checkout:

```sh
python tools/bundle_runtime.py --destination /external/build/runtime --tesseract /absolute/path/to/tesseract
BAKER_RUNTIME_DIRECTORY=/external/build/runtime BAKER_BUILD_DIRECTORY=/external/build/app ./tools/prepare_app.sh
```

The runtime tool copies the standalone interpreter and the required package distributions, preserves their notices, relocates non-system Tesseract libraries and tests imports. It does not copy a virtual environment or change the user's Python installation. The app build signs nested native binaries and sets its minimum macOS version from the runtime manifest. Use an appropriate `BAKER_SIGN_IDENTITY` for distribution; ad-hoc signing supports local development and does not provide notarisation.

Current local Tesseract dependencies require macOS 26. Building the source app for macOS 14 does not make those binary libraries compatible with macOS 14. Prepare and test an older-target runtime before advertising that compatibility.

After building, `tools/package_dmg.sh /path/to/Baker.app /external/build/Baker.dmg` creates a drag-to-Applications disk image and verifies it. This does not notarise the app.

## Development without bundled engines

```sh
BAKER_BUILD_CONFIGURATION=debug BAKER_BUILD_DIRECTORY=/external/build/debug ./tools/prepare_app.sh
```

Enable Developer overrides for an unbundled build. Set Python to an environment containing the pinned formula requirements, and prepare a model with `tools/provision_formula_model.py`. The generated `baker-config.json` remains available for experiments with decoding limits. Builds using an affected Swift toolchain can select `BAKER_BUILD_SYSTEM=native`; that engine is a temporary workaround.
