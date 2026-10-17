# Save folder and presets

Choose **Settings → General → Save location → Choose Folder**. Baker saves images and formula history directly in this folder. The default is `~/Documents/Baker`.

You can select an iCloud Drive, Dropbox or Google Drive folder already available in Finder. The provider’s desktop software handles synchronisation. Baker has no account login, upload or import service.

Changing the location opens the selected folder’s Baker history. Existing files stay in the previous folder; select that folder again to reopen them. Baker checks the new folder before switching. Close image editors and finish active work first.

The folder contains capture images, the hidden `.baker-history.json` capture index and `.baker-formulas.json` formula records. Keep the indexes with their images. Formula records contain recognised text, edits and recognition details; they are available through Capture History and Formula Workspace.

## Presets

**Save Preset** starts in the save folder’s `Presets` subfolder. **Load Preset** restores the selected preset after checking its format.

Presets include OCR languages, maths font, formula copy style, clipboard preferences, capture sounds, desktop-icon visibility, preview count and formula-history limits. They exclude the save location, shortcuts, Python paths, models and credentials. Loading a preset can apply its formula-history limits.

Models remain in the app or `~/Library/Application Support/Baker/Models`. They are not copied into the save folder.

## Synced folders

Let the provider finish downloading the folder before opening it. Use one Baker instance at a time for each shared folder. Baker detects some outside changes to its indexes, but does not merge simultaneous edits from different Macs. Provider-side sharing, retention and deletion are managed through that provider.
