# Clipboard & Files

Choose **Open Files** from the Baker menu. Drop images and PDFs into the workspace or use **Add Sources → Choose Files…**. You can also import a web link or use the clipboard from **Add Sources**.

1. Add up to 50 items.
2. For documents, choose **PDF**, **Markdown** (initial format) or **LaTeX** under **Source output**.
3. Choose **Convert Files**, or **Import Images** for an image-only queue. Baker processes one file at a time.
4. Document exports save automatically to your save folder. Choose **Open** to view a result or **Save As…** for another copy.

Images are copied into capture history. Choose **Formula** beside an imported image to recognise it. Original files stay in place.

## Web content

1. Choose **Add Sources → Import Web Content…**, paste a link and choose **Open**.
2. Choose **Add** to queue the page. If the site needs sign-in or a security check, choose **Continue Here…** and complete it in the web view. Choose **Add Page** or **Add PDF** once the content is ready.
3. Choose a format under **Source output**, then choose **Convert Files**.

**PDF** creates a searchable reading copy of a web page or saves the downloaded PDF unchanged. **Markdown** and **LaTeX** use the PDF conversion engine. If a plugin is selected, Baker asks before giving it a web PDF and lets you choose local conversion instead.

If a site cannot open in the web view, choose **Open in Browser**, download the PDF and add it to **Clipboard & Files**. Closing the web view ends its sign-in session.

## Formula images

Drop an image into **Formula Workspace** or choose **New → Open Image…**. The history grid and arrows reopen saved equations. See [Formula Workspace](../help/formula.md#formula-workspace).

To remove surrounding text before recognition, double-click a capture thumbnail, cover it with an opaque white filled rectangle, then choose **Done**. Drag the updated thumbnail into Formula Workspace. The edit overwrites that capture; keep a separate copy if you need the original.

## Actions

| Action | Use |
| --- | --- |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/files-open-dark.svg"><img src="../../others/assests/symbols/files-open.svg" width="22" alt="Open Files"></picture> **Open Files** | Drop files or browse for several files |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/clipboard-image-dark.svg"><img src="../../others/assests/symbols/clipboard-image.svg" width="22" alt="Open Clipboard Image"></picture> **Open Clipboard Image** | Import the current clipboard image |
| <picture><source media="(prefers-color-scheme: dark)" srcset="../assets/symbols/clipboard-text-dark.svg"><img src="../../others/assests/symbols/clipboard-text.svg" width="22" alt="Read Clipboard Text"></picture> **Read Clipboard Text** | Recognise text in the current clipboard image |

## PDF conversion

Baker’s local Markdown and LaTeX conversion requires a one-time engine download. Saving to PDF needs no model. Manage it in **Settings → Advanced → Offline Model**.

The prepared PDF engine recognises layout, text, equations and tables locally, using available PDF characters to recover text and scripts. Figure files are saved in a companion folder; keep it beside the document when moving the export. Automatic saves use a new filename if one already exists. If saving fails, Baker keeps a temporary result and asks you to save it before clearing the list or quitting. Closing the window alone does not discard completed results or cancel processing. No online account is needed.

During conversion, each PDF shows the provider, current stage, completed pages, percentage and elapsed time. Approximate remaining time appears after two completed pages. Model preparation is excluded from that estimate; later complex pages can take longer. Progress stays below 100% until export is ready.

Review the result against the source, especially mathematical symbols and complex layouts. See [PDF limits](../help/limits.md#pdf-conversion).
