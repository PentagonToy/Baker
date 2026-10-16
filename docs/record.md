# Record

Choose **Video…** or **GIF…** from the **Record** menu category to record a selected screen region.

## Record a video or GIF

Choose **Video…** or **GIF…** and select a screen region. The floating controls show elapsed time; use **Stop** to finish or **Cancel** to discard. Baker excludes its own windows from the capture. Screen Recording permission is required.

| Output | Duration | Frame rate | Longest side |
| --- | ---: | ---: | ---: |
| Silent MP4 | 60 seconds | Up to 30 fps | 1920px |
| Animated GIF | 15 seconds | Up to 10 fps | 960px |

The recording does not upscale the selected region. Video dimensions are rounded down to even pixels; frames may be skipped when the encoder cannot keep up. GIFs loop continuously. Audio, trimming and recording effects are not available yet.

Live screen recording still needs end-to-end verification. Synthetic media tests establish file encoding and decoding, not permission handling or correctness in every desktop application.

## Save an export

Recordings finish in an Export panel. **Save…** keeps a file; **Save & Copy…** saves it and copies the saved file for pasting into another app. Unsaved exports are temporary and are replaced by the next export or removed on normal quit.

See [Recent](recent.md) to reopen the current export, or [Settings](settings.md) for capture preferences.
