# Settings

Settings uses a sidebar. Choose a category, then adjust its controls.

| Category | Controls |
| --- | --- |
| General | Automatic image/text copying and the text result editor |
| Capture | Sounds, visible previews and the capture folder |
| Formula | Model download/repair, maths font and history controls |
| Cloud | Google Drive/Dropbox login, manual capture uploads and imports |
| Advanced | Text OCR languages and optional developer overrides |

Formula output format is chosen in the Formula Workspace. It always copies after recognition.

See [Google Drive](cloud.md), [model setup](getting-started.md#prepare-formula-recognition) and [Unicode maths](unicode-maths.md).

Advanced offers English, German, Korean, Swedish, Danish and Finnish. Select 1–3 languages used in the capture. The fourth choice is disabled until one is deselected. The limit keeps choices focused; it does not guarantee better recognition.

Text captures and scanned PDF pages use Apple Vision unless Finnish is selected. With Finnish, Tesseract reads the selected languages using the included models. The complete app includes Tesseract and its runtime libraries; no separate installation is needed. Formula OCR uses its separate model.

Capture files are stored in `~/Documents/Baker`. The previous Pictures archive moves there on the next launch if the destination is absent. Finnish appears as **Suomi**, independently of English; enable English separately when needed.
