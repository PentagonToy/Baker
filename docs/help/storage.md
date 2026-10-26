# Save folder and presets

Choose **Settings → Storage → Save location → Choose Folder**. Baker saves images, recordings and formula history directly in this folder. The default is `~/Documents/Baker`.

You can select an iCloud Drive, Dropbox or Google Drive folder already available in Finder. The provider’s desktop software handles synchronisation. Baker has no account login, upload or import service.

Changing the location opens the selected folder’s Baker history. Existing files stay in the previous folder; select that folder again to reopen them. Baker checks the new folder before switching. Close image editors and finish active work first.

New captures use `baker_<type>_yyyy-MM-dd_HH-mm-ss-SSS`, for example `baker_formula_2026-10-24_16-30-00-123.png`. Types are `formula`, `image`, `video` and `gif`; the timestamp uses local time. A numbered suffix prevents collisions. Existing filenames stay unchanged, and edits retain the filename stem.

Capture edits replace the archived image; previously exported copies remain unchanged. See [editing and SVG conversion](../guide/capture.md#edit-a-capture).

The folder contains capture images, the hidden `.baker-history.json` capture index, `.baker-formulas.json` formula records and `.baker-recordings.json` recording records. Keep the indexes with their associated files. Formula records contain recognised text, edits and recognition details; they are available through Capture History and Formula Workspace.

## Presets

**Save Preset** starts in the save folder’s `Presets` subfolder. **Load Preset** restores the selected preset after checking its format.

Presets include OCR languages, maths font, formula copy style, clipboard preferences, capture sounds, desktop-icon visibility, preview count and formula-history limits. They exclude the save location, shortcuts, Python paths, models and credentials. Loading a preset can apply its formula-history limits.

Models remain in the app or `~/Library/Application Support/Baker/Models`. They are not copied into the save folder.

## Synced folders

Let the provider finish downloading the folder before opening it. Use one Baker instance at a time for each shared folder. Baker detects some outside changes to its indexes, but does not merge simultaneous edits from different Macs. Provider-side sharing, retention and deletion are managed through that provider.

## History

Storage → History groups image and formula retention. Capture images default to **No limit** and **No age limit**. Choose a count or age, then use **Review & Apply** to inspect the number and total size before moving affected images to Trash. Linked formula results are removed with their images. The approved policy applies to future captures in that folder; review it again after choosing another save folder. Videos, GIFs and unindexed files are unaffected. No limit means no automatic retention removal; archive safety caps still apply.

**Clear Image Cache** discards cached thumbnails and reconciles missing files. Opening Capture History also refreshes its records. Images already deleted in Finder, and their linked formula metadata, disappear from history; unreadable files that still exist are retained. An unavailable folder is reported rather than treated as an empty history.

Formula limits remove recognised text and diagnostics while preserving existing images. The default keeps 50 results with no age limit. **Clear Formula Cache** lives in Storage settings and also reconciles deleted files. Image removal policies and their folder approval are local settings excluded from portable presets.
