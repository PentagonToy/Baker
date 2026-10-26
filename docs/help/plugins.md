# OCR plugins

Baker recognises formulas and converts PDFs locally by default. Add one optional plugin in **Settings → Advanced → Plugin → Add Plugin ZIP…**, review the code-access prompt, then enable its switch. The plugin handles its supported operations; text capture stays local. Remove the plugin to register a replacement.

A plugin is executable code, with your user permissions. It can read files and use the network; Baker does not sandbox it. Install only code you trust and review the provider’s privacy policy, costs and terms. Use documented APIs or integrations you are authorised to use. You are responsible for your use of third-party plugins and services, including permissions and charges; installing a plugin does not grant additional rights under a provider’s terms.

## API keys and usage

After adding a plugin, enter its API key if required and choose **Save Key**. Baker stores the key in macOS Keychain and supplies it only to that plugin’s invocation. **Clear Key** removes it. A key alone does not identify an OCR service: the plugin defines the destination, authentication and response handling. Never include credentials in a ZIP, source file or diagnostic output.

**Test Connection** runs a `probe` without a capture or PDF. Plugin usage counts successful image jobs, PDFs and pages completed through Baker, rather than the provider’s billing balance. **Reset…** clears these counts after confirmation and updates the tracking date. The separate **Baker · Local** counts include jobs completed by local fallback.

If a plugin fails, Baker tries the installed local model once. Cancelled jobs stay cancelled. Baker never retries against another remote service; a failed request may nevertheless have reached the provider and incurred a charge. Install a formula model and the optional Offline Model to make both fallbacks available. Results show the provider that actually completed the job.

## Make a plugin

Download the [adapter template ZIP](https://github.com/PentagonToy/Baker/releases/download/v0.0.8/Baker-OCR-Plugin-Template.zip) or copy the [adapter example](../../examples/ocr-plugin/), implement its formula and/or PDF functions, and update `plugin.json`. The example deliberately returns failure until implemented. ZIP the manifest and program together, either at the archive root or inside one enclosing folder. Only advertise operations you implement. From the example folder, create the ZIP with `python3 -m zipfile -c ~/Desktop/my-ocr.zip plugin.json plugin.py`.

```json
{
  "schema": 1,
  "id": "example.ocr",
  "name": "My OCR",
  "version": "1.0.0",
  "executable": "baker-python",
  "arguments": ["{plugin}/plugin.py"],
  "operations": ["formula", "pdf"],
  "timeout_seconds": 120
}
```

`baker-python` uses Baker’s included interpreter with isolated mode and bytecode writes disabled. Python’s standard library is available; do not assume extra packages are installed. An absolute executable path or `{plugin}/program` can use another installed runtime. Arguments are passed directly, without a shell. `{plugin}` expands to the installed package directory. Keep credentials, downloaded models and mutable state outside the code package; `BAKER_PLUGIN_DATA` supplies a private state directory and `BAKER_PLUGIN_DIR` identifies the package. If needed, `BAKER_PLUGIN_API_KEY` contains the saved key.

Packages are limited to 16 MB and 256 entries, without symbolic links or special files. Baker copies approved code into its Application Support folder and checks its digest before each launch. Code changes require removal and reimport. External runtimes and dependencies are outside this digest; manage them as trusted software. Removal forgets the registration and returns to Local; package files, usage and private settings remain on the Mac. Clear the key separately before removing if you no longer need it.

## JSON protocol, version 1

Each invocation reads one UTF-8 JSON request from stdin and writes one JSON response to stdout, then exits. Echo `schema` and `id`; return `ok: false` on failure. Keep logs off stdout and never print credentials. Baker intentionally hides provider error bodies. Requests contain only the selected input path, job output location and operation, with no capture history.

```json
{"schema":1,"id":"request-id","operation":"formula","input":{"path":"/path/to/image.png"}}
```

```json
{"schema":1,"id":"request-id","ok":true,"latex":"x^2+1=0"}
```

`probe` carries neither input nor output paths. Return `ok: true` only when ready; use a non-billable check. Formula output must be non-empty and at most 8,000 characters / 32 KB. A formula job has a maximum timeout of 120 seconds; `probe` has 10 seconds. PDF jobs can set `timeout_seconds` up to 7,200. Both stdout and stderr are limited to 256 KB. Stop promptly when terminated and do not leave background workers running; Baker manages its direct child process rather than a container or arbitrary descendant process tree.

A PDF request adds `output: {"directory":"/private/job/output","format":"markdown"}` or `"latex"`. Write `result.md` or `result.tex` and return `output: "result.md"` or `"result.tex"`. Keep accompanying figures under `assets/` and reference them relatively. Baker validates and copies the export and owned figures to its normal save location. Input PDFs are limited to 256 MB and 2,000 pages; output text to 64 MB and the complete output folder to 512 MB / 1,000 entries. Links and special files are rejected. Temporary output is removed after the job.

## Agent access

`baker plugins` lists approved plugin metadata without keys. `baker plugin-use --text example.ocr` selects an approved plugin; use `--text local` to return to Local. `baker plugin-probe --text example.ocr` explicitly tests one. Adding code still requires the native ZIP approval prompt. Live `import` and `pdf` commands use the selected provider; the headless `formula` command remains local.
