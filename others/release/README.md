# Release preparation

Update `VERSION`, `CHANGELOG.md` and the current release notes together. Build from a committed source revision using [the development guide](../../docs/help/development.md), with generated files outside the repository.

Run the checks for the changed behaviour, type-check the app and build its production bundle. Use `tools/release_check.py --app /path/to/Baker.app --output /external/check.json` to audit resources, licences and signing. Create the DMG with `tools/package_dmg.sh`, mount it and verify the packaged app’s version and signature. Check an installation with existing data and screen-recording permissions; distinguish that from clean-machine coverage.

Publish the matching Git tag, DMG, SHA-256 checksums and a concise validation report. State signing, notarisation and test limitations. Keep optional model and PDF-engine releases separate, with pinned hashes, licences, provenance and corresponding source. Update the Homebrew cask only after the app asset is public and its checksum is verified.
