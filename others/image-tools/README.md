# Local capture image tools

Baker removes plain or smoothly shaded backgrounds with a border-anchored illumination estimate and colour-to-alpha operation and offers Apple Vision foreground masks as a separate Photo Cutout action. Baker does not download an additional model for these actions. Paper & Slides estimates a smooth background from border samples and compatible interior colours; Photo Cutout can omit thin axes, labels or other material outside the detected subject.

Colour vectorisation uses [VTracer 0.6.15](https://github.com/visioncortex/vtracer). Black & White uses [Potrace 1.16](https://potrace.sourceforge.net/). Both trace the editor’s flattened pixels after masks and crops. Output contains paths rather than an embedded raster image. Background removal and tracing approximate the source; inspect faint details, small labels and fine lines before replacing the capture.

`manifest.json` pins every local input by SHA-256. `vendor` contains the arm64 CPython 3.12 VTracer wheel and the previously tested Homebrew Potrace binary with its private library and original recipe. `sources` retains the exact upstream source archives. VTracer is MIT-licensed; the Potrace command-line source declares GPL-2.0-or-later and includes its GPL v2 COPYING file. These dependencies retain their own terms alongside Baker’s AGPL-3.0-only source.

`tools/prepare_image_tools.py` verifies and extracts these payloads into a fresh directory outside the checkout. It does not install packages or access the network. During an authorised app build, `tools/prepare_app.sh` relocates Potrace’s private library and signs the native payloads. The app includes notices, source archives, build recipe and provenance under `Contents/Resources/ImageTools`. Native relocation and signing must be checked in the resulting app before release; source-only checks do not establish clean-machine portability.

The worker starts only for a conversion, using Baker’s existing Python and Pillow runtime. It exits when finished. Conversion is limited to four megapixels, 60 seconds and an 8 MB SVG with at most 50,000 paths; monochrome tracing has a separate 30-second child timeout. Background removal accepts up to eight megapixels. No resident worker or additional large model is used.

SVGcode informed workflow research; Baker does not include its browser application or Potrace-WASM build. AutoTrace’s centreline output was reviewed and deferred. withoutBG and StarVector were considered but are not included. Reference repositories remain separate from the app’s shipped dependencies.
