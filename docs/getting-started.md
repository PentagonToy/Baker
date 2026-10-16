# Getting started

Baker is currently distributed as source. It requires Apple Silicon, macOS 14 or later, and a compatible Swift toolchain. Minimum-version runtime testing is still pending.

## Build and open

From the repository root, choose an output directory and build the application:

```sh
export BAKER_BUILD_DIRECTORY="$HOME/Library/Caches/Baker/build"
./tools/prepare_app.sh
open "$BAKER_BUILD_DIRECTORY/Baker.app"
```

The script creates an ad-hoc-signed app in that directory. It does not install Baker into Applications. If your Command Line Tools reports `Unknown error parsing property list`, try the available alternative build engine:

```sh
BAKER_BUILD_SYSTEM=native ./tools/prepare_app.sh
```

The alternative engine is deprecated by Swift and is a workaround for the affected toolchain, not a new requirement for every Mac.

Baker opens in the menu bar without a main window. Click its viewfinder icon to choose a task. Use **Settings…** or **Quit Baker** from the same menu. Double-clicking an already running Baker opens the Formula Workspace.

## Allow screen capture

The first capture needs permission in **System Settings → Privacy & Security → Screen Recording**. Enable Baker and reopen it if macOS requests a restart. Image files and clipboard images can be used without starting a screen capture.

## Prepare formula recognition

Ordinary text OCR uses Apple Vision. Formula OCR additionally needs Python 3.12 with the [formula dependencies](../tools/formula-requirements.txt) and a local model. In your chosen Python environment, run:

```sh
python -m pip install -r tools/formula-requirements.txt
python tools/provision_formula_model.py --destination "$HOME/Library/Application Support/Baker/Models/mfr-1.5"
```

Preparation downloads the pinned MFR 1.5 model and verifies its file hashes. It writes `baker-config.json` in the selected directory. Model preparation needs an internet connection; subsequent recognition uses local files. Model files occupy about 120 MB, independently of runtime dependencies and working memory.

Open **Settings…** and set **Python executable** to that environment's absolute Python path and **Model configuration JSON** to the generated `baker-config.json` path. Use `python -c 'import sys; print(sys.executable)'` in the environment to find the executable. The [example configuration](../tools/formula-config.example.json) documents the available limits. Existing prototype configurations that contain Pix2Text constructor options must be replaced with this format.

Try **Formula** on a single clear equation. Its Formula Workspace shows the original and rendered equation; choose **LaTeX**, **Markdown**, **Keynote** or **Unicode** and the desired LaTeX style. Successful formula output is copied automatically. No account or online recognition service is needed.
