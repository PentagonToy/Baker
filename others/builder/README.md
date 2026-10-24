# Build Baker

Double-click **[Build.command](Build.command)** to build, check and replace the local app. The builder preserves the previous app and opens Baker after installation succeeds. Captures, downloaded models and settings remain outside the app bundle.

## Configuration

Copy `builder.example.json` to the ignored `builder.local.json` and select the prepared runtime, document payload and reference PDF. The builder selects the Workspace Python environment after checking the Mac’s hardware. It checks dependencies without installing packages or downloading models.

The base app includes the formula runtime, download descriptors and workers. Pix2Text, Texo and plus-S weights download separately through Settings. Include `ftfy` and `wcwidth` from `tools/formula-requirements.txt` when preparing the runtime. The optional PDF engine uses its own archive and descriptor; `include_pdf_engine` produces a complete offline build instead.

Use `pdf_distribution` to reuse a verified PDF package. The builder refuses to install an app whose optional PDF download is unavailable. See [PDF distribution](PDF-DISTRIBUTION.md) for packaging and [model packages](../../docs/models/README.md) for formula weights and licences.

## Build and install

```sh
python others/builder/build.py --check
python others/builder/build.py --build-only
python others/builder/build.py
```

The builder checks tools, disk space and app identity, then builds and signs the app. It verifies the PDF archive, compares converted Markdown and configured table fixtures, and checks the signature before replacement. Build outputs and backups stay in the configured external build directory. A failed check preserves the installed app; a failed replacement restores it.

The builder allows one build at a time and asks Baker to quit normally. Check the recorded process before removing an interrupted build lock. Use the configured persistent [signing identity](../../docs/help/development.md#signing) to retain app identity across local rebuilds. See [third-party notices](../../docs/legal/third-party.md) before distribution.
