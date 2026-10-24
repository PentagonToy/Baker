# Prepare a release

[Baker 0.0.5](0.0.5.md) is the current app release. Formula and PDF model releases use separate tags and do not update the app. [Distribution](next.md) covers Homebrew maintenance.

Build the candidate with the [local builder](../builder/README.md), then audit the prepared app:

```sh
python tools/release_check.py --app /Applications/Baker.app --output /external/release/readiness.json
```

Resolve reported blockers before packaging. Verify a fresh installation, capture permission and recognition on a clean Mac. Retain dependency notices, model provenance and Baker’s AGPL-3.0-only corresponding source. Local self-signing provides neither Developer ID nor notarisation.

Create the DMG with `tools/package_dmg.sh`, mount it and test the copied app. The arranged installer derives from remile. and retains its [MIT notice](../../tools/remile-LICENSE.txt). Prepare checksums, concise release notes and the corresponding source with the disk image.

Commit the tested source before tagging. Match `VERSION`, the app version, source commit and release assets. Record the app and DMG hashes, minimum macOS version and signing status. Publication and tag creation are explicit release actions; a local build does not publish them.
