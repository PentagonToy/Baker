# Baker demos

Short, silent clips for feature guides and the project website. Each MP4 runs for 8.5–9.6 seconds at 1280 × 800, 30 fps, with H.264 video and streaming metadata at the start. Matching JPG files provide poster images. Looping GIF previews use a shared palette at 10 fps for GitHub README playback; select a preview to open its MP4.

| Clip | Shows |
| --- | --- |
| [Formula formats](formula-formats.mp4) | LaTeX, Markdown and Unicode in the formula popover. |
| [PDF to Markdown or LaTeX](pdf-to-markdown.mp4) | A heading, body text and equation beside actual offline Markdown and LaTeX exports; waiting time omitted. |
| [Remove background](remove-background.mp4) | Paper & Slides background removal, Undo and Redo. |
| [Vectorise](vectorise-svg.mp4) | Colour tracing to SVG, Undo and Redo. |

The formula, background-removal and vector clips render Baker 0.0.4's actual interface components with isolated, synthetic fixtures. Background removal and vector tracing use Baker's production operations. The formula starts from prepared LaTeX; this clip demonstrates output formats rather than OCR accuracy. Captions and transitions are edited, so the clips do not measure processing speed.

The PDF clip is an authored comparison using text and an equation crop from [Vaswani et al., *Attention Is All You Need* (2017), page 4](https://arxiv.org/abs/1706.03762), and separate fresh offline Markdown and LaTeX exports from installed Baker 0.0.4. The source excerpt is reflowed to keep its heading, body text and original equation legible; output line breaks are also adjusted for display. The full conversion is not instantaneous: the waiting interval is explicitly omitted. The clip demonstrates this excerpt rather than claiming perfect document recognition.

No desktop recording, personal files, capture history, accounts or microphone audio are included. The presentation fixture uses a separate clipboard. Raw frames and production helpers remain outside the repository.
