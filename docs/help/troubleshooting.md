# Troubleshooting

| Problem | Try this |
| --- | --- |
| No main window | Click Baker’s menu-bar icon and choose a workspace |
| Capture permission is missing | Allow the installed Baker in macOS Screen Recording settings, then reopen it |
| Formula model is unavailable | Check Settings → Formula; see [setup](getting-started.md#capture-a-formula) |
| Original formula looks small | It is shown without enlarging its source pixels; capture a larger on-screen equation for more detail |
| Recognition times out | Select one clear equation with little surrounding text |
| Unicode shows a warning | Read the warning; choose LaTeX or Keynote for two-dimensional layout |
| Maths font changes after pasting | Use ordinary Paste and install the selected font in the destination app |
| Scrolling rejects content | Use smaller downward steps and exclude fixed or animated areas |
| PDF layout looks wrong | Compare names, symbols and column order with the source; correct the exported text |
| PDF progress pauses | Model preparation and complex pages take time; ETA is approximate |
| Export disappears | Save before clearing files, replacing an export or quitting |
| Save folder is unavailable | Reconnect its drive or let the sync provider download it |

## Opening a downloaded app

The current preview is not notarised. If macOS blocks the first launch, check that the DMG came from Baker’s GitHub release, then open **System Settings → Privacy & Security** and choose **Open Anyway** for Baker. Approve only a download you trust. See [Apple’s guidance](https://support.apple.com/102445).

## Screen Recording permission after an update

Keep one installed copy in Applications. **Settings → Capture → Screen Recording** shows access status and opens the macOS permission pane. Returning to Baker checks access again; use **Reopen Baker** if macOS requires a restart. Finish work and close capture editors first.

Ad-hoc signed development builds can require permission again after replacement because their code identity changes. A persistent signing identity can help; see [signing](development.md#signing). Removing and re-adding Baker in System Settings is a recovery step for stale permissions, not the normal update procedure.

## Capture history cannot be saved

Check the reported error. Baker preserves existing images and names any temporary capture retained for recovery. If an index was changed externally, reopen Baker to reload it. Close Baker before manually changing history files.

## A thumbnail remains after dragging

The destination must accept the drop before Baker closes its thumbnail. Cancelled or rejected drops leave it available. Its image remains in the save folder.
