# Privacy policy

Effective date: 16 October 2026.

This policy covers Baker, the macOS capture and recognition app developed by Hanseul Kang, and its documentation website. Contact [kanghanseul96@gmail.com](mailto:kanghanseul96@gmail.com) for privacy questions. Baker can be used locally without connecting a cloud account.

## Capture and recognition

Baker processes screen regions, imported images, PDFs and clipboard content selected by the user. These may contain personal information. Text and formula recognition run on the Mac using Apple Vision or included local recognition tools and prepared models. Baker does not send this content to an external OCR service, the developer or a Baker-operated server.

Baker stores capture images, capture dates, dimensions and filenames locally, normally under `~/Documents/Baker`. Saved formula records can include original and edited LaTeX, Unicode, copy preferences, the recognition model identifier, confidence and token-level diagnostics. Settings are stored in local application preferences. Selected copy actions place content on the macOS clipboard, where other applications and clipboard managers may access it.

Closing a thumbnail keeps its saved file. Done in the capture editor overwrites the local capture and removes its previous OCR metadata. Previously exported, uploaded or backed-up copies remain unchanged. Recording and conversion create local outputs; temporary files can remain while a job or workspace is open, and a failed capture may retain an original for recovery. Capture images do not expire automatically. Formula metadata defaults to the latest 50 results; users can change the limit and select 10-day or 30-day retention. Clear Formula History removes this metadata; Clear Preview Cache releases in-memory previews without deleting images or saved formula records.

## Model preparation

When the user chooses Download Model or Repair Model, Baker downloads pinned model files from Hugging Face over HTTPS. The provider receives ordinary connection information such as the requesting IP address. No captures, recognised text or account tokens are included in these requests. Baker verifies the file sizes and SHA-256 hashes before installation. Models are stored under `~/Library/Application Support/Baker/Models`; Remove Model deletes the prepared formula model without deleting captures.

## Optional Google Drive access

Google sign-in runs in the browser. Baker requests the `drive.file` permission to create and access files used by Baker, rather than read the whole Drive. It does not request Gmail, contacts or calendar access.

When the user chooses Upload, Baker sends the selected capture image and any saved formula record directly to Google Drive. It creates a `Baker` folder and `.baker` metadata folder. Refresh reads Baker file names, identifiers, sizes and application properties such as capture identifiers and image hashes. Import downloads the chosen image and associated formula metadata into local history. These details support listing, integrity checks and recognition-result restoration. Transfers are manual and use HTTPS.

Baker does not operate a service that receives these files or makes their contents available to the developer. It does not sell Google user data, use it for advertising, train general-purpose models with it or permit developer review of the contents. Baker's use and transfer of information received from Google APIs adheres to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including its Limited Use requirements.

## Optional Dropbox access

Dropbox sign-in runs in the browser using OAuth and PKCE. Baker requests file metadata read, file content read and file content write permissions. With the App Folder registration, access is limited to the app's folder.

Upload sends selected images and saved formula metadata directly to Dropbox. Refresh lists Baker captures, and Import downloads the chosen image and metadata. Image hashes and local import mappings support integrity checks and duplicate prevention. Baker does not automatically synchronise or delete Dropbox files.

## Tokens and local settings

Access and refresh tokens are stored in macOS Keychain, separately for each provider. An imported Google desktop-client secret, if required, is stored with that login. Public client identifiers, model paths, language preferences and remote-to-local file mappings are stored in local preferences. Baker does not ask for or store a Google or Dropbox password. Login uses a temporary callback on the Mac's loopback interface.

Keychain and local files are subject to the security and backup settings of the Mac. A cloud provider processes account authorisation, network information and transferred files under its own policies: [Google Privacy Policy](https://policies.google.com/privacy) and [Dropbox Privacy Policy](https://www.dropbox.com/privacy).

## Disconnecting and deleting data

Use Settings → Cloud → Disconnect to remove the provider's login tokens from Baker's Keychain entry. This does not delete uploaded files, local captures or the provider-side authorisation grant. Remove cloud files through Google Drive or Dropbox, and revoke access in the account's connected-app settings if desired. Copies and versions previously uploaded remain until removed there.

Use Open Capture Folder to locate local captures and their hidden history/formula metadata. Quit Baker before removing archive files. Local preferences include settings and import mappings; uninstalling the app alone may leave these, the capture folder and Keychain entries behind. Disconnect before uninstalling to remove the stored login. Cloud imports are separate local copies.

## Website and support

The documentation is hosted by GitHub Pages. GitHub receives network information when the site is visited, under its [privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement). Baker adds no advertising, analytics or third-party tracking scripts to the site. Documentation search may remember preferences in the browser; these stay in the browser.

If the user contacts the developer, the message, reply address and any voluntarily supplied material are used to respond. Avoid sending private captures, passwords or tokens in public GitHub issues. The developer cannot retrieve local captures or cloud files merely from a support request.

## Changes

Material changes to data handling will be reflected here with an updated effective date. Questions about access, correction or removal of information sent directly to the developer can be addressed to [kanghanseul96@gmail.com](mailto:kanghanseul96@gmail.com).
