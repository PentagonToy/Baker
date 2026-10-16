# Settings

Open **Settings…** from Baker's menu-bar icon.

| Setting | Effect |
| --- | --- |
| Copy captured images automatically | Copies successful ordinary area captures |
| Copy recognised text automatically | Copies successful ordinary text OCR output; formula results always copy their selected format |
| Open result editor after recognition | Opens the editor when OCR completes |
| Capture sounds | Plays Tink on success and Funk on failure; cancellation is silent |
| Visible captures | Shows one to five recent previews; older captures remain saved in history |
| Open Capture Folder | Opens `~/Pictures/Baker` in Finder |
| Unicode maths font | Selects STIX Two Math, STIX or Latin Modern Math for preview and formatted copying |
| Python executable | Absolute path to the prepared formula runtime |
| Model configuration JSON | Absolute path to the local model configuration |

The image and ordinary text copy preferences are independent. Formula output and LaTeX style are selected directly in the Formula Workspace and remembered. Baker does not monitor the clipboard in the background. Clipboard image input is an explicit menu action.

The interface currently supports English. Text OCR may recognise other supported input languages; formula recognition is intended for cropped mathematical expressions.

See [model setup](getting-started.md#prepare-formula-recognition), [Unicode pasting](unicode-maths.md), and [troubleshooting](troubleshooting.md).
