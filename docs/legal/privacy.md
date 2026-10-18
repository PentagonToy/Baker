# Privacy policy

Effective date: 18 October 2026.

This policy covers Baker, developed by Hanseul Kang, and its documentation website. Contact [kanghanseul96@gmail.com](mailto:kanghanseul96@gmail.com) for privacy questions.

## Local processing and storage

Baker processes screen regions, images, PDFs and clipboard content selected by the user. Capture, recognition, background removal and vector tracing run locally. Baker sends none of this content to an external OCR service, the developer or a Baker-operated server.

The save folder, normally `~/Documents/Baker`, contains captures, recordings and hidden history indexes. Records include dates, dimensions and filenames. Formula records can also contain original and edited LaTeX, Unicode, copy preferences, model identifiers, confidence and token diagnostics. Exported settings presets occupy the `Presets` subfolder and exclude captures, credentials, models and the save path.

Settings stay in local macOS preferences. Repeat Area stores the display identifier, display size and selection rectangle there; these values are excluded from presets. Selected copy actions place content on the macOS clipboard, where other apps and clipboard managers may access it.

Closing a thumbnail retains its file. Done in the editor replaces the capture and removes its old OCR metadata. Vectorisation replaces the previous image with one SVG; subsequent image editing can replace that SVG with PNG. Previously exported or backed-up copies remain unchanged. Temporary outputs can remain while a job or workspace is open; failed operations may retain an original for recovery.

## Downloads

The complete app prepares and repairs its included formula model locally. Builds without that model download pinned files from Hugging Face over HTTPS. Baker verifies sizes and SHA-256 hashes before installation under `~/Library/Application Support/Baker/Models`. Remove Model deletes the prepared cache while preserving captures and any bundled model.

PDF conversion downloads its optional engine from Baker’s GitHub Releases over HTTPS. Baker verifies the archive size, SHA-256 and file inventory before installation under `~/Library/Application Support/Baker/Engines`. Settings → PDF removes the engine while preserving user files.

Download providers receive ordinary connection information, including the requesting IP address. These requests contain no captures, documents, recognised text or OCR account tokens.

## Synchronisation

Baker uses the selected local or Finder-accessible folder and has no cloud-account login. Changing the save folder leaves previous files in place.

For iCloud Drive, Dropbox, Google Drive or another synced folder, the provider’s software may transfer, retain or share its contents under the user’s settings and the provider’s policies. Baker performs no separate cloud transfers. An ordinary local folder avoids provider synchronisation of new captures.

## Retention and deletion

Capture images default to no count or age limit. Applying a retention policy requires review, moves expired images to Trash and removes linked formula metadata. The approved policy then applies to future captures in that folder. Recordings do not expire automatically.

Formula metadata defaults to the latest 50 results with no age limit. Users can change the count, select 10-day or 30-day expiry, or clear formula history. These actions preserve capture images.

Clear Image Cache releases thumbnails; Clear Preview Cache releases rendered equations. Both reconcile files deleted in Finder and remove their linked metadata while preserving existing files. Opening Capture History also reconciles missing files. Use **Settings → General → Open Folder** to locate captures and indexes; close Baker before manually editing indexes.

Uninstalling Baker leaves the save folder, model cache, preferences and provider backups in place.

## Website and support

GitHub Pages hosts the documentation and receives connection information under its [privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). Baker adds no advertising, analytics or third-party tracking scripts. Documentation search preferences stay in the browser.

Support messages, reply addresses and voluntarily supplied material are used to respond. Avoid private captures, passwords or tokens in public GitHub issues. The developer cannot retrieve local captures or cloud files from a support request.

## Changes

Material changes to data handling will receive an updated effective date. Contact the developer for access, correction or removal of information supplied directly for support.
