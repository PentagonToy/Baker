# Privacy policy

Effective date: 27 October 2026.

This policy covers Baker, developed by PentagonToy, and its documentation website. Contact [kanghanseul96@gmail.com](mailto:kanghanseul96@gmail.com) for privacy questions.

## Local processing and storage

Baker processes screen regions, images, PDFs and clipboard content selected by the user. Built-in capture, recognition, background removal and vector tracing run locally. Baker sends none of this content to the developer or a Baker-operated server. An explicitly installed and selected OCR plugin can process selected formula images and PDFs externally.

The save folder, normally `~/Documents/Baker`, contains captures, recordings and hidden history indexes. Records include dates, dimensions and filenames. Formula records can also contain original and edited LaTeX, Unicode, copy preferences, model identifiers, confidence and token diagnostics. Exported settings presets occupy the `Presets` subfolder and exclude captures, credentials, models and the save path.

Retired online connections are removed from Baker’s local Keychain item and preferences on launch, without reading credentials or contacting the provider. If Keychain is unavailable, Baker retries on a later launch.

Settings stay in local macOS preferences. Repeat Area stores the display identifier, display size and selection rectangle there; these values are excluded from presets. Selected copy actions place content on the macOS clipboard, where other apps and clipboard managers may access it.

Closing a thumbnail retains its file. Done in the editor replaces the capture and removes its old OCR metadata. Vectorisation replaces the previous image with one SVG; subsequent image editing can replace that SVG with PNG. Previously exported or backed-up copies remain unchanged. Temporary outputs can remain while a job or workspace is open; failed operations may retain an original for recovery.

## Downloads

Formula models download only when requested in Settings, using pinned archives from Baker’s GitHub releases over HTTPS. Baker verifies sizes and SHA-256 hashes before installation under `~/Library/Application Support/Baker/Models`. Remove Model deletes the selected model while preserving captures and other models.

PDF conversion downloads its optional engine from Baker’s GitHub Releases over HTTPS. Baker verifies the archive size, SHA-256 and file inventory before installation under `~/Library/Application Support/Baker/Engines`. Settings → Advanced → Offline Model removes the engine while preserving user files.

Download providers receive ordinary connection information, including the requesting IP address. These requests contain no captures, documents, recognised text or account credentials.

## Optional OCR plugins

Users can approve one external code package in Advanced and choose Plugin first for supported formula and PDF jobs. Plugins run with user permissions and may read files or transfer data under their own policies. Baker passes the selected input rather than capture history. Failed jobs can fall back to an installed local model; cancellation does not retry. No OCR provider is bundled or endorsed. A plugin can declare an explicit Configure action that opens its own setup interface. Baker supplies no capture, document or saved credential to this action; the plugin handles user-entered login details and stores credentials through the operating system. Setup is cancellable and time-limited.

Approved packages and private state live under `~/Library/Application Support/Baker/Plugins` and `PluginData`. Optional API keys are stored in macOS Keychain and provided to the selected process. Local preferences retain registration, selection, successful-job counts and their tracking dates, without keys. Removing a plugin deletes Baker’s saved API key and forgets registration, while retaining files, counts and other private state. Key deletion must succeed before removal completes; Clear Key can also remove it separately. See [OCR plugins](../help/plugins.md).

## Update checks

A manual check, or an optional daily automatic check, requests public release metadata from GitHub over HTTPS. Automatic checks are off initially. GitHub receives ordinary connection information; the request includes no captures, recognised text, device identifier or account token. Check preferences and timestamps stay on this Mac. Choosing Download DMG opens the release asset in the default browser; Baker does not replace itself.

## Synchronisation

Baker uses the selected local or Finder-accessible folder and has no cloud-account login. Changing the save folder leaves previous files in place.

For iCloud Drive, Dropbox, Google Drive or another synced folder, the provider’s software may transfer, retain or share its contents under the user’s settings and the provider’s policies. Baker performs no separate cloud transfers. An ordinary local folder avoids provider synchronisation of new captures.

## Scan drafts

Baker keeps one recoverable scan under `~/Library/Application Support/Baker/ScanDraft`. Closing Scan keeps its pages; saving the PDF or choosing Discard Scan removes the working draft. Window-selection previews remain in memory only while needed. Automatic page turning uses macOS control access and targets the selected reader app. No additional model or network service is used for capture or searchable Scan PDFs.

## Retention and deletion

Capture images default to no count or age limit. Applying a retention policy requires review, moves expired images to Trash and removes linked formula metadata. The approved policy then applies to future captures in that folder. Recordings do not expire automatically.

Formula metadata defaults to the latest 50 results with no age limit. Users can change the count, select 7-, 10-, 30- or 90-day expiry, or clear formula history. These actions preserve capture images.

Clear Image Cache releases thumbnails; Clear Formula Cache releases rendered equations. Both reconcile files deleted in Finder and remove their linked metadata while preserving existing files. Opening Capture History also reconciles missing files. Use **Settings → Storage → Open Folder** to locate captures and indexes; close Baker before manually editing indexes.

Uninstalling Baker leaves the save folder, model cache, preferences and provider backups in place.

## Website and support

GitHub Pages hosts the documentation and receives connection information under its [privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). Baker adds no advertising, analytics or third-party tracking scripts. Documentation search preferences stay in the browser.

Support messages, reply addresses and voluntarily supplied material are used to respond. Avoid private captures, passwords or tokens in public GitHub issues. The developer cannot retrieve local captures or cloud files from a support request.

## Changes

Material changes to data handling will receive an updated effective date. Contact the developer for access, correction or removal of information supplied directly for support.
