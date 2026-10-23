# Agent CLI

Baker 0.0.4 and later include `/Applications/Baker.app/Contents/Resources/CLI/baker`. `tools/baker` calls the installed app. Run `baker help` for JSON command discovery. This interface uses the same macOS user as Baker and exposes fixed operations, not arbitrary shell execution. It never returns login credentials.

| Command | Result |
| --- | --- |
| `version` | Installed app version |
| `status` | Busy state, storage, capture count and last status |
| `diagnostics` | App memory, thumbnail cache, preview queue and active OCR/PDF work; no captured content or paths |
| `history --limit 20 --offset 0` | Capture metadata and saved formula source |
| `result` | Current text, LaTeX, Unicode and export path |
| `capture --format all` | Capture the pointer’s display |
| `capture --format area` | Interactive area selection |
| `capture --format window` | Interactive window selection |
| `capture --format repeat` | Repeat the saved area |
| `capture --format formula` | Interactive formula capture |
| `record --format video` | Interactive recording setup; GIF is also supported |
| `stop` | Stop recording |
| `cancel` | Cancel capture, recognition or PDF conversion |
| `import /absolute/image.png` | Add an image to capture history |
| `open-formula --text UUID` | Open a saved equation |
| `copy` | Copy the current result |
| `clear-cache` | Clear preview caches and reconcile history |
| `settings --text Advanced` | Open a settings category |
| `pdf /absolute/input.pdf --output /absolute/new.md --format markdown --timeout 7200` | Offline PDF export; LaTeX is also supported |
| `formula /absolute/image.png` | Headless recognition without clipboard or history changes |
| `unicode --text '\mathbf{x}+1'` | Headless plain Unicode approximation |

Live commands require Baker running. There is no extra worker or server port. Requests use an owner-only mailbox awakened by filesystem events. Capture and recording commands return acceptance rather than completed output. Poll `status` and `result` afterwards. The normal Screen Recording permission and interactive selection still apply. Model downloads remain explicit app actions.

`diagnostics` is read-only and remains available during conversion. `process.residentBytes` and `physicalFootprintBytes` describe the app process, excluding OCR workers and WebKit services. Compare repeated samples under the same workload; one reading cannot establish a leak. Cache limits are budgets, not the total memory retained by visible views.

For structured input, pipe a JSON object to `baker request`, for example `{"operation":"history","limit":5}`. The CLI supplies a fresh request identity and timestamp. Unhandled operations return `ok: false`. Nonzero exit status indicates failure. Output paths must be new absolute paths. No existing file is intentionally overwritten.

To expose the bundled launcher on PATH, create a link in your own command directory without replacing an existing command:

```sh
mkdir -p "$HOME/.local/bin"
ln -s /Applications/Baker.app/Contents/Resources/CLI/baker "$HOME/.local/bin/baker"
```

The link is optional. Existing `--adapter` and `--adapter-info` remain available.
