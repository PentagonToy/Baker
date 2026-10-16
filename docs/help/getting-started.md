# Getting started

Open the supplied **Baker.dmg**, drag **Baker.app** to Applications and double-click it. If you received the app directly, move it to Applications first. Baker appears in the menu bar. You do not need Python, Homebrew or a model configuration file.

The current complete local build supports Apple Silicon and macOS 26 or later because its included Tesseract libraries target macOS 26. Baker is intended for GitHub distribution rather than the Mac App Store. An older-macOS runtime build is not yet available. Developers can build from source using the [development guide](development.md).

## Allow screen capture

The first capture needs permission in **System Settings → Privacy & Security → Screen Recording**. Enable Baker and reopen it if macOS requests a restart. Image files and clipboard images can be used without starting a screen capture.

## Prepare formula recognition

Open **Settings → Formula** and choose **Download Model · 120 MB**. Baker downloads the pinned model from Hugging Face, checks every file and prepares its configuration automatically. **Cancel** stops the download; **Repair Model** downloads a replacement if needed. **Remove Model** frees its storage without deleting capture history.

The engine is included in the app. Model files live under `~/Library/Application Support/Baker/Models/mfr-1.5`. Preparation needs an internet connection; recognition then runs locally without an account. Text OCR, including Finnish, needs no model download.

Choose **Formula**, drag around one clear equation and release. Compare the original and rendered result, then choose **LaTeX**, **Markdown**, **Keynote** or **Unicode** to copy. The selected output is copied automatically.

## Daily use

Click Baker’s menu-bar icon to capture, record or open files. **Settings** controls fonts, clipboard behaviour and history. **Quit Baker** closes the app; double-clicking an already running Baker opens the Formula Workspace.
