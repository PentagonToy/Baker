# Privacy policy

Effective date: 17 October 2026.

This policy covers Baker, the macOS capture and recognition app developed by Hanseul Kang, and its documentation website. Contact [kanghanseul96@gmail.com](mailto:kanghanseul96@gmail.com) for privacy questions. Baker works locally and has no cloud-account login.

## Capture and recognition

Baker processes screen regions, imported images, PDFs and clipboard content selected by the user. These may contain personal information. Text and formula recognition run on the Mac using Apple Vision or included local recognition tools and prepared models. Baker does not send this content to an external OCR service, the developer or a Baker-operated server.

Baker stores capture images, capture dates, dimensions and filenames locally, normally under `~/Documents/Baker`. Saved formula records can include original and edited LaTeX, Unicode, copy preferences, the recognition model identifier, confidence and token-level diagnostics. Settings are stored in local application preferences. Selected copy actions place content on the macOS clipboard, where other applications and clipboard managers may access it.

Closing a thumbnail keeps its saved file. Done in the capture editor overwrites the local capture and removes its previous OCR metadata. Previously exported or backed-up copies remain unchanged. Recording and conversion create local outputs; temporary files can remain while a job or workspace is open, and a failed capture may retain an original for recovery. Capture images do not expire automatically. Formula metadata defaults to the latest 50 results; users can change the limit and select 10-day or 30-day retention. Clear Formula History removes this metadata; Clear Preview Cache releases in-memory previews without deleting images or saved formula records.

## Model preparation

The complete app prepares an included formula model locally when available. Model repair restores the included files when available. For builds that require a download, Baker downloads pinned model files from Hugging Face over HTTPS. The provider receives ordinary connection information such as the requesting IP address. No captures, recognised text or account tokens are included in these requests. Baker verifies the file sizes and SHA-256 hashes before installation. Models are stored under `~/Library/Application Support/Baker/Models`; Remove Model deletes the prepared formula model without deleting captures.

Development builds can download an optional PDF engine from Baker’s GitHub Releases over HTTPS. GitHub receives ordinary connection information, including the requesting IP address; the request does not contain documents or recognised content. Baker checks the archive size, SHA-256 and file inventory before installation under `~/Library/Application Support/Baker/Engines`. Settings → PDF Conversion removes the downloaded engine without deleting user files. PDF Engine 1.0.0 is distributed through Baker’s GitHub Releases.

## Save folders and synchronisation

The user chooses one save folder for capture images and formula records. Baker stores its capture and formula indexes beside those images and saves exported settings presets in the `Presets` subfolder. Presets contain selected preferences, not captures, credentials, model files or the save path. Models stay in the app or its Application Support folder.

If the chosen folder is synced or shared through iCloud Drive, Dropbox, Google Drive or another provider, that provider’s software may upload, download, retain or share its contents under the user’s account settings and the provider’s policies. Baker does not authenticate with these providers or perform its own cloud transfers. Choosing an ordinary local folder avoids provider synchronisation of new captures.

## Deletion

Use Open Folder in Settings → General to locate captures and their hidden indexes. Changing the save folder keeps the previous files in place. Formula-history limits and Clear Formula History remove recognised text and diagnostics from the index while keeping capture images. Clear Preview Cache releases in-memory previews. Uninstalling Baker does not remove the save folder, model cache, preferences or provider backups. Close Baker before manually changing its history files.

## Website and support

The documentation is hosted by GitHub Pages. GitHub receives network information when the site is visited, under its [privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). Baker adds no advertising, analytics or third-party tracking scripts to the site. Documentation search may remember preferences in the browser; these stay in the browser.

If the user contacts the developer, the message, reply address and any voluntarily supplied material are used to respond. Avoid sending private captures, passwords or tokens in public GitHub issues. The developer cannot retrieve local captures or cloud files merely from a support request.

## Changes

Material changes to data handling will be reflected here with an updated effective date. Questions about access, correction or removal of information sent directly to the developer can be addressed to [kanghanseul96@gmail.com](mailto:kanghanseul96@gmail.com).
