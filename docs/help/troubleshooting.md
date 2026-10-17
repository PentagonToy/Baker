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

## Screen Recording permission after an update

Ad-hoc signed builds can require permission again after replacement. Keep one installed copy in Applications and quit the old process before reopening an update. A persistent signing identity can stabilise development builds; see [Development builds](development.md).

## Capture history cannot be saved

Check the reported error. Baker preserves existing images and names any temporary capture retained for recovery. If an index was changed externally, reopen Baker to reload it. Close Baker before manually changing history files.

## A thumbnail remains after dragging

The destination must accept the drop before Baker closes its thumbnail. Cancelled or rejected drops leave it available. Its image remains in the save folder.
