# OCR plugins

Available in Baker 0.0.9 and later.

Baker recognises formulas and converts PDFs locally by default. Add one optional plugin in **Settings → Advanced → Plugin → Add Plugin ZIP…**, review the code-access prompt, then choose **Baker** or **Plugin first** separately for **Formula OCR**, **PDF → Markdown** and **PDF → LaTeX**. **Baker** processes jobs locally; **Plugin first** tries the adapter before local fallback. The plugin handles its supported operations; text capture stays local. One installed plugin keeps provider selection, credentials and usage unambiguous. Remove it to register a replacement.

A plugin is executable code, with your user permissions. It can read files and use the network; Baker does not sandbox it. Install only code you trust and review the provider’s privacy policy, costs and terms. Use documented APIs or integrations you are authorised to use. You are responsible for your use of third-party plugins and services, including permissions and charges; installing a plugin does not grant additional rights under a provider’s terms.

## API keys and usage

After adding an API-key plugin, enter its key if required and choose **Save Key**. Plugins that supply interactive setup show **Configure…** instead; choosing it opens the plugin’s own setup window or browser. Baker stores the key in macOS Keychain and supplies it only to that plugin’s invocation. **Clear Key** removes it. A key alone does not identify an OCR service: the plugin defines the destination, authentication and response handling. Never include credentials in a ZIP, source file or diagnostic output.

**Test Connection** runs a `probe` without a capture or PDF. Plugin usage counts successful image jobs, PDFs and pages completed through Baker, rather than the provider’s billing balance. **Reset…** clears these counts after confirmation and updates the tracking date. The separate **Baker · Local** counts include jobs completed by local fallback.

If a plugin fails, Baker tries the installed local model once. Cancelled jobs stay cancelled. Baker never retries against another remote service; a failed request may nevertheless have reached the provider and incurred a charge. Install a formula model and the optional Offline Model to make both fallbacks available. The formula popover, workspace and PDF result show the provider that actually completed the job. A local fallback is labelled Baker even when the plugin was preferred. PDF output preferences apply to document conversion, not to copying a recognised formula in another text format.

## Make a plugin

Copy the [adapter example](../../examples/ocr-plugin/), implement its formula and/or PDF functions, and update `plugin.json`. The example deliberately returns failure until implemented. ZIP the manifest and program together, either at the archive root or inside one enclosing folder. Only advertise operations you implement. From the example folder, create the ZIP with `python3 -m zipfile -c ~/Desktop/my-ocr.zip plugin.json plugin.py setup.py`.

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

`baker-python` uses Baker’s included interpreter with isolated mode and bytecode writes disabled. Python’s standard library is available; do not assume extra packages are installed. An absolute executable path or `{plugin}/program` can use another installed runtime. The approval dialog identifies the runtime; **Execution Details…** shows the full executable and arguments, which are passed directly without a shell. `{plugin}` expands to the installed package directory. Keep credentials, downloaded models and mutable state outside the code package; `BAKER_PLUGIN_DATA` supplies a private state directory and `BAKER_PLUGIN_DIR` identifies the package. If needed, `BAKER_PLUGIN_API_KEY` contains the saved key. Processes receive a fixed command search path, home and temporary directories, a UTF-8 locale and these plugin variables; unrelated parent environment variables are not inherited.

Packages are limited to 16 MB and 256 entries, without symbolic links or special files. Baker copies approved code into its Application Support folder and checks its digest before each launch. Code changes require removal and reimport. External runtimes and dependencies are outside this digest; manage them as trusted software. Removal forgets the registration, deletes Baker’s saved API key and returns to Local; package files, usage and other private settings remain on the Mac. If Keychain refuses deletion, the plugin remains registered so you can unlock it and retry. Keys or other settings written independently by the plugin remain its responsibility.

## Interactive setup

An optional `"configuration": true` manifest field enables **Configure…**. It is off when omitted, so existing adapters retain their API-key field. Clicking Configure explicitly starts one `configure` invocation, without an input image, document, output format or saved key. It can open a plugin-owned setup window and must return `{"schema":1,"id":"request-id","ok":true}` when finished. Use the same request identifier. Write only the JSON response to stdout; keep credentials out of responses and logs.

Setup has a six-minute limit, can be cancelled in Baker, and does not count towards OCR usage. It must own and stop any local listener rather than detach a background service. Use the operating system’s credential store for login state. Baker does not implement or endorse a provider’s authentication flow; the adapter owns it and its terms. For a credential shared with Baker, the Keychain generic-password service is `Baker.OCRPlugin`, the account is the manifest ID, and the value is an opaque UTF-8 string. Restrict read access to Baker. The saved value is passed to that adapter’s OCR and probe invocations through `BAKER_PLUGIN_API_KEY`; setup does not receive it. Clear Credentials and removal delete this shared record. Private state stored elsewhere remains the adapter’s responsibility.

## JSON protocol, version 1

Each invocation reads one UTF-8 JSON request from stdin and writes one JSON response to stdout, then exits. Echo `schema` and `id`; return `ok: false` on failure. Keep logs off stdout and never print credentials. Baker intentionally hides provider error bodies. Requests contain only the selected input path, job output location and operation, with no capture history.

```json
{"schema":1,"id":"request-id","operation":"formula","input":{"path":"/path/to/image.png"}}
```

```json
{"schema":1,"id":"request-id","ok":true,"latex":"x^2+1=0"}
```

`probe` carries neither input nor output paths. Return `ok: true` only when ready; use a non-billable check. Formula output must be non-empty and at most 8,000 characters / 32 KB. A formula job has a maximum timeout of 120 seconds; `probe` has 10 seconds and `configure` has 360 seconds. PDF jobs can set `timeout_seconds` up to 7,200. Both stdout and stderr are limited to 256 KB. Stop promptly when terminated and do not leave background workers running; Baker manages its direct child process rather than a container or arbitrary descendant process tree.

A PDF request adds `output: {"directory":"/private/job/output","format":"markdown"}` or `"latex"`. Write `result.md` or `result.tex` and return `output: "result.md"` or `"result.tex"`. Keep accompanying figures under `assets/` and reference them relatively. Baker validates and copies the export and owned figures to its normal save location. Input PDFs are limited to 256 MB and 2,000 pages; output text to 64 MB and the complete output folder to 512 MB / 1,000 entries. Links and special files are rejected. Temporary output is removed after the job.

## Agent access

`baker plugins` lists approved plugin metadata without keys. `baker plugin-use --text example.ocr` selects an approved plugin for all supported jobs; add `--format formula`, `--format markdown` or `--format latex` to change one job. Use `--text local` to return a job, or all jobs when no format is supplied, to Baker. `baker plugins` reports each job’s effective priority; `selected: "mixed"` indicates different choices. `baker plugin-probe --text example.ocr` explicitly tests one. Adding code still requires the native ZIP approval prompt. Live `import` and `pdf` commands use the selected provider; the headless `formula` command remains local.

During `configure`, Baker supplies `BAKER_PLUGIN_SETUP_FILE`, a temporary descriptor path. To show an in-app setup window, atomically write `{ "url": "http://127.0.0.1:PORT/random-path" }` there after starting a foreground loopback server. Use an unprivileged port and a unique path, validate Host and Origin, and serve a restrictive content security policy. Baker accepts only that loopback origin, blocks remote web resources and uses an ephemeral web session. Closing the window cancels setup; the process must own its server and exit after completion. The descriptor must contain no credentials. Plugins that do not use this optional window can retain their existing setup flow.

The SDK includes `examples/ocr-plugin/setup.py`, a reusable email/password popup helper. Supply only your authorised authentication and secure-storage callbacks. The popup includes Passwords… for opening Apple Passwords; it does not read saved passwords. HTML AutoFill hints are present, but automatic website-password suggestions require an appropriate site identity and are not promised for a loopback page.
