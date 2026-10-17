# Settings

Settings uses a sidebar. Choose a category, then adjust its controls.

| Category | Controls |
| --- | --- |
| General | Appearance, automatic copying, text result editor, save folder and portable presets |
| Capture | Sounds, desktop-icon visibility and visible previews |
| Shortcuts | Capture and recording key combinations |
| Menu | Section order, command order and visible commands in the menu-bar menu |
| Formula | Model preparation/repair, maths font and history controls |
| Advanced | Text OCR languages and optional developer overrides |

Formula output format is chosen in the Formula Workspace. It always copies after recognition.

See [Save folder](storage.md), [model setup](getting-started.md#capture-a-formula) and [Unicode maths](unicode-maths.md).

Advanced offers English, German, Korean, Swedish, Danish and Finnish. Select 1–3 languages used in the capture. The fourth choice is disabled until one is deselected. The limit keeps choices focused; it does not guarantee better recognition.

Text captures and fallback PDF text OCR use Apple Vision unless Finnish is selected. With Finnish, Tesseract reads the selected languages using the included models. The complete app includes Tesseract and its runtime libraries; no separate installation is needed. Formula OCR uses its separate model.

Capture files and formula records use the folder chosen in General, initially `~/Documents/Baker`. Finnish appears as **Suomi**, independently of English; enable English separately when needed.

An ellipsis (`…`) marks a file chooser or settings dialog. Capture actions and workspace commands use plain labels.

## Menu layout

Open **Settings → Menu** to arrange the menu that appears beneath Baker’s menu-bar icon. Move sections and commands with the up/down buttons, and uncheck commands to hide them. **Apply** saves the layout for the next menu opening; no restart is needed. **Revert** discards unapplied changes. **Restore Defaults** prepares the original layout; choose Apply to save it.

Settings, Quit and active Stop/Cancel controls remain available. Hiding a command does not remove its assigned global shortcut. The layout stays in this Mac’s preferences and is separate from portable presets.

## Standard keyboard commands

When a Baker window has focus, **⌘Q** quits through Baker’s normal shutdown, **⌘W** closes the window, and **⌘,** opens Settings. Text fields support ordinary cut, copy, paste, select-all and undo commands through the macOS responder chain. Closing Settings leaves Baker running in the menu bar.
