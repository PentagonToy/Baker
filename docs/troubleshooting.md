# Troubleshooting

| Problem | What to check |
| --- | --- |
| Baker has no main window | This is expected. Open its menu-bar icon. |
| Screen capture cannot start | Check macOS Screen Recording permission and reopen Baker if required. |
| Formula recognition asks for a runtime or model | Complete [formula setup](getting-started.md#prepare-formula-recognition) and use absolute paths in Settings. |
| Model is incomplete or configuration is unsupported | Run the provisioning helper for the pinned model and use its generated `baker-config.json`. Recognition does not download missing files. |
| Formula times out or exceeds the token limit | Capture a smaller, clearer single equation. A truncated result is not copied. |
| Unicode shows source commands or warns about scripts | Some notation has no plain Unicode representation. Use LaTeX for exact layout. |
| Selected maths font is unavailable | Install that font yourself or choose an available font. Settings names the fallback. |
| Pasted font changes | Use ordinary Paste to request source formatting. The receiving app controls which clipboard representation it accepts. |
| Scrolling capture rejects a frame | Pause animation, use smaller downward steps and exclude fixed UI. Return to the last accepted position. |
| PDF output loses layout or mathematical structure | The current converter extracts text. Review it or retain the original PDF. |
| Export is missing after quitting | Unsaved exports are temporary. Use Save or Save & Copy before quitting or creating another export. Captured images remain in the capture archive. |

Cancellation discards recognition results. Normal quitting waits for active jobs to stop and then cleans up owned temporary files. A crash or force quit can leave temporary files behind.

## Permission appears enabled but a new build asks again

Local builds use ad-hoc signing by default. Their designated requirement is tied to that particular code version, so replacing the app with a rebuilt version can invalidate an earlier privacy authorisation even when the app name and path stay the same. This is distinct from a computer-use tool timing out. Keep one installed copy, quit the old process before reopening an updated app and follow macOS's permission instructions for that installed copy. Baker does not reset the system privacy database.

For development with an available persistent code-signing certificate, set `BAKER_SIGN_IDENTITY` to that identity when running `tools/prepare_app.sh`. An invalid identity fails signing rather than silently falling back. Keep the signing identity and bundle identifier consistent between updates. An Apple Development or Developer ID identity must be provisioned separately; the build script does not create certificates. [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) explains ad-hoc requirements and privacy-resource identity. Stable signing still requires an initial permission grant and has not been tested on this host, which currently reports no valid code-signing identities.
