# Clipboard & Files

Choose **Open Files** for images and PDFs. The workspace stays open when you switch apps and during capture. Drop images and PDFs into it, or choose **Choose Files…** to select several files.

1. Add up to 50 files.
2. For PDFs, choose **Markdown** (initial format) or **LaTeX** under **PDF output**.
3. Choose **Process Files**. Baker processes one file at a time.
4. Save each PDF result before clearing the list or quitting.

Images are copied into capture history. Choose **Formula** beside an imported image to recognise it. Original files stay in place.

## Formula images

Choose **Formula Workspace** for image drops, **Image…** for a file chooser and **New** for an empty input. **History** and the arrows reopen saved equations. See [Formula Workspace](../help/formula.md#formula-workspace).

To remove surrounding text before recognition, double-click a capture thumbnail, cover it with an opaque white filled rectangle, then choose **Done**. Drag the updated thumbnail into Formula Workspace. The edit overwrites that capture; keep a separate copy if you need the original.

## Actions

| Action | Use |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/files-open-dark.svg"><img src="../../others/assests/symbols/files-open.svg" width="22" alt="Open Files"></picture> **Open Files** | Drop files or browse for several files |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/clipboard-image-dark.svg"><img src="../../others/assests/symbols/clipboard-image.svg" width="22" alt="Clipboard Image"></picture> **Clipboard Image** | Import the current clipboard image |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/clipboard-text-dark.svg"><img src="../../others/assests/symbols/clipboard-text.svg" width="22" alt="Read Clipboard Text"></picture> **Read Clipboard Text** | Recognise text in the current clipboard image |

## PDF conversion

In Baker mode, the first PDF conversion requests a one-time engine download and continues after verification. The installed engine works offline; captures and formula recognition need no PDF download. Manage it in **Settings → Advanced → Offline Model**.

The prepared PDF engine recognises layout, text, equations and tables locally, using available PDF characters to recover text and scripts. Figure files are saved in a companion folder; keep it beside the document when moving the export. No online account is needed for Baker mode. Unreleased builds also offer [Mathpix account conversion](../help/settings.md#mathpix-and-usage-unreleased); online LaTeX results are saved as `.tex.zip` projects.

Each PDF shows its current stage, completed pages, percentage and elapsed time. Approximate remaining time appears after two completed pages. Model preparation is excluded from that estimate; later complex pages can take longer. Progress stays below 100% until export is ready.

Review the result against the source, especially mathematical symbols and complex layouts. See [PDF limits](../help/limits.md#pdf-conversion).
