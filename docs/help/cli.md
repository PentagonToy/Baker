# Agent CLI

Baker 0.0.4 and later include `/Applications/Baker.app/Contents/Resources/CLI/baker`. `tools/baker` calls the installed app. Run `baker help` for JSON command discovery. This interface uses the same macOS user as Baker and exposes fixed operations, not arbitrary shell execution. It never returns login credentials.

| Command | Result |
| --- | --- |
| `version` | Installed app version |
| `status` | Busy state, storage, capture count and last status |
| `diagnostics` | App memory, caches, preview queues and Scan/OCR/PDF work; no captured content or file paths |
| `history --limit 20 --offset 0` | Capture metadata and saved formula source |
| `formulas --text softmax --format markdown --limit 20` | Search saved formulas and read formatted output without OCR or clipboard changes |
| `copy-formula --text UUID --format latex` | Copy a saved formula without opening it or changing the selected format |
| `result` | Current text, LaTeX, Unicode and export path |
| `capture --format all` | Capture the pointer’s display |
| `capture --format area` | Interactive area selection |
| `capture --format window` | Interactive window selection |
| `capture --format repeat` | Repeat the saved area |
| `capture --format formula` | Interactive formula capture |
| `record --format video` | Interactive recording setup; GIF is also supported |
| `stop` | Stop recording |
| `cancel` | Cancel work; Scan keeps its draft for review |
| `scan --format status --limit 20 --offset 0` | Read Scan state and a page of draft metadata |
| `import /absolute/image.png` | Add an image to capture history |
| `open-formula --text UUID` | Open a saved equation |
| `copy` | Copy the current result |
| `clear-cache` | Clear preview caches and reconcile history |
| `settings --text Advanced` | Open a settings category |
| `pdf /absolute/input.pdf --output /absolute/new.md --format markdown --timeout 7200` | Offline PDF export; LaTeX is also supported |
| `formula /absolute/image.png` | Headless recognition without clipboard or history changes |
| `unicode --text '\mathbf{x}+1'` | Headless plain Unicode approximation |

Live commands require Baker running. There is no extra worker or server port. Requests use an owner-only mailbox awakened by filesystem events. Responses must be regular files owned by the current user, at most 8 MiB, and match the request ID. Invalid responses fail without returning their contents. Capture and recording commands return acceptance rather than completed output. Poll `status` and `result` afterwards. The normal Screen Recording permission and interactive selection still apply. Model downloads remain explicit app actions.

`clipboard.preparingImage` reports pending image encoding. `diagnostics` is read-only and remains available during conversion. `process.residentBytes` and `physicalFootprintBytes` describe the app process, excluding OCR workers and WebKit services. Compare repeated samples under the same workload; one reading cannot establish a leak. Cache limits are budgets, not the total memory retained by visible views.

For structured input, pipe a JSON object to `baker request`, for example `{"operation":"history","limit":5}`. The CLI supplies a fresh request identity and timestamp. Unhandled operations return `ok: false`. Nonzero exit status indicates failure. Output paths must be new absolute paths. No existing file is intentionally overwritten.

To expose the bundled launcher on PATH, create a link in your own command directory without replacing an existing command:

```sh
mkdir -p "$HOME/.local/bin"
ln -s /Applications/Baker.app/Contents/Resources/CLI/baker "$HOME/.local/bin/baker"
```

The link is optional. Existing `--adapter` and `--adapter-info` remain available.


Formula and PDF commands process inputs on this Mac. Download the required local model first; no online fallback or account login is available.

## OCR plugins

See [OCR plugins](plugins.md) for ZIP registration and the `plugins`, `plugin-use` and `plugin-probe` commands. Registration requires native approval; keys are never returned by the CLI.

## Scan

Choose the reader window and any crop or next-page button in Baker. The CLI does not grant permissions or choose a target on your behalf.

| `scan --format` | Action |
| --- | --- |
| `start` | Open or resume the draft; repeat calls leave an active scan unchanged |
| `status --limit 20 --offset 0` | Read state, settings, readiness and page UUIDs with image paths; at most 100 items per call |
| `configure --text '{"delay":2.5,"searchable":true}'` | Set delay or searchable PDF text while paused; delay accepts 0.1–60 seconds |
| `add` | Add one page from a prepared manual scan |
| `pause` / `resume` | Pause or resume a prepared automatic scan |
| `review` | Stop turning pages and review the draft |
| `continue` | Return from review to manual capture; a restored draft needs its reader selected again |
| `select` / `retake` / `remove --text UUID` | Select, retake or remove a reviewed page |
| `move --text UUID --offset -1` | Move a reviewed page earlier; use `1` for later |
| `save --output /absolute/book.pdf` | Save a reviewed draft to a new PDF |
| `close` | Stop the session and close its windows, keeping the draft |

Changes return `accepted` with a small state summary. Poll `status` until `working` is false; `captureReady` indicates that a manual page can be added. Successful saving closes the session; read `result.export` for the output path. Failed or cancelled saves keep the draft. Removing a page is destructive; `close` is the safe way to leave a draft for later.

`diagnostics.scan` contains counts and resource state. Detailed page paths are returned only by `scan --format status`, not by general diagnostics. Scan is available in Baker 0.1.1 and later.
