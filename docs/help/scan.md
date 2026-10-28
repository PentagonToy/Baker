# Scan

Collect pages from a reader window and save them as one PDF.

1. Choose **Scan…** from Baker’s menu, then choose the reader from the window previews. Search by app or window title.
2. Select **Window** or **Area**. Area lets you mark a rectangle on a preview of that window.
3. Choose **→**, **↓** or **Click**, enter a **Delay** in seconds, then **Start Scan**. The arrows send Right Arrow or Down Arrow. For clicking, select the next-page button on the window preview.
4. When the page stops changing, Baker waits once more and opens the review. The unchanged trailing capture is not added.

In review, select a thumbnail to retake, remove or move a page. Save one PDF to your chosen location; enable **Searchable text** to add local OCR during export. Check recognised text before relying on it. Markdown and LaTeX conversion remain separate PDF operations.

**Manual** collects pages without automatic input or Accessibility access. Turn pages yourself and choose **Add Page**; the **Scan / Add Page** shortcut works without moving the pointer.

Closing review keeps a working draft. Choose Scan again to resume it. Saving the PDF removes its working images; **Discard Scan…** removes an unwanted draft. Previously saved files are kept.

## Timing and limits

Baker offers capture and control permissions together on first launch. On macOS 27, control access is called **Device Control and Data Access**; earlier systems call it **Accessibility**. Manual capture needs only Screen Recording.

Capture stays attached to the selected window, even when covered. Input goes only to the reader app without moving the pointer. Background input depends on the reader; moving the window or switching windows within that app pauses the scan.

Delay accepts 0.1–60 seconds. Allow time for the reader to load: an unchanged loading screen or repeated blank page can look like the end. Review the result and add any missing pages manually.

There is no continuous screen-sampling stream or OCR during capture. Originals are saved to the draft; previews use reduced images. A draft is limited to 500 pages and 2 GB. Auto scan pauses after 20 minutes. Save a section before continuing a longer book.


Agents can pause, resume, inspect and save a prepared session through the [CLI](cli.md#scan).

Choose **Cancel Processing** from Baker’s menu to stop the scan and close its windows. Captured pages stay in the draft for next time.
