# Troubleshooting

| Problem | Try this |
| --- | --- |
| No main window | Open Baker’s menu-bar icon |
| Capture permission is missing | Allow the installed Baker in macOS Screen Recording settings, then reopen it |
| Formula runtime or model is missing | Follow [setup](getting-started.md#prepare-formula-recognition) |
| Recognition times out | Capture one smaller, clearer equation |
| Unicode shows a warning | Read the warning; choose LaTeX or Keynote for exact layout |
| Maths font changes after pasting | Use ordinary Paste; Paste and Match Style follows the destination |
| Scrolling rejects content | Use smaller downward steps and exclude fixed or animated areas |
| PDF layout looks wrong | Compare it with the original; current conversion extracts text |
| Formula history cannot be saved | Check the reported error; existing images and metadata are preserved |
| Export disappears | Save before clearing files, replacing an export or quitting |

## Permission returns after an update

Local preview builds use ad-hoc signing, which ties permission identity to a particular build. Replacing Baker can require permission again even when its name and location stay the same. Keep one installed copy and quit the old process before reopening an update.

A persistent signing certificate is the development fix. Set `BAKER_SIGN_IDENTITY` when building with an available certificate; see [Apple’s signing explanation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements). The build script does not create certificates.

## Capture history changed

Baker reloads valid additions from another running instance before saving. If a history file was removed, damaged or edited externally, restart Baker to reload it. Existing images remain on disk; an error names any temporary original retained for recovery.

## Google testing access denied

Add the signing-in account under Google Auth Platform → Audience → Test users in the app owner’s Cloud project. See [cloud setup](cloud.md).

## A thumbnail remains after dragging

Baker closes it after the destination reports an accepted drop. Cancelled drags and destinations that reject the file keep the thumbnail. The original image remains in the capture folder.

## Finnish OCR needs Tesseract

Use the complete Baker app, which includes the Finnish engine and six language models. Developers using an unbundled build can choose an executable under Developer overrides.
