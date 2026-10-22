# Prepare a release

Version `0.0.4` is the current Apple Silicon preview. [Release notes](0.0.4.md) describe its behaviour and limits. The [distribution plan](next.md) describes Homebrew maintenance. This directory prepares reviewable material; it does not publish a release or create a tag.

## Current gates

| Check | Status |
| --- | --- |
| Version and installed app | 0.0.4; macOS 26.0 capture / 26.2 PDF minimum |
| Formula Workspace and Menu settings | Built and installed; source hashes verified; menu and keyboard behaviour confirmed by the user |
| PDF acceptance | Research Markdown and complex-table comparison pass |
| Native signature | Persistent self-signed identity verified; not notarised |
| Dependency provenance | Corrected checkpoint lineage and retained model cards included; installed audit passes |
| Baker source licence | AGPL-3.0-only selected; LICENSE and dependency notices included in the installed app |
| Clean-machine installation | Pending; prepared agent environments are not sufficient evidence |
| DMG, checksums and source package | Verify the assets and release manifest attached to the matching GitHub release |
| GitHub release and version tag | See the matching v0.0.4 GitHub release and manifest |

PyMuPDF ships under its AGPL option in this build. Retain the dependency notices and include Baker’s AGPL-3.0-only source and its corresponding-source distribution before uploading a binary. The third-party notices do not grant a licence to Baker’s own code. See [PyMuPDF's licence statement](https://pymupdf.readthedocs.io/en/latest/about.html#license-and-copyright).

## Check the candidate

Run this read-only audit from the prepared Python environment. It checks versions, app identity, signature, selected model hashes, provenance, notices and the project licence; it does not rebuild or install anything:

```sh
python tools/release_check.py --app /Applications/Baker.app --output /external/release/readiness.json
```

Read the reported blockers. A passing local audit does not replace a clean-machine launch, capture-permission and OCR test.

## Package after the gates are resolved

Use the [builder](../builder/README.md) to produce an app from the final source, including the corrected provenance and model cards. Verify its builder report and source hashes. Create a versioned `Baker-<version>-arm64.dmg` with `tools/package_dmg.sh`, mount it, copy the app to a fresh location and test it without developer runtime overrides or a pre-existing model cache. Preserve existing user captures and preferences during the test.

The DMG packaging tool arranges Baker and Applications on a generated background. Its layout helpers derive from remile. and retain the MIT notice in `tools/remile-LICENSE.txt`.

Prepare SHA-256 checksums, the release notes, corresponding source and dependency notices with the disk image. Record the exact source commit, app hash, disk-image hash, minimum macOS version, model manifest and signing status. Retest the packaged copy after signing; do not alter it afterwards.

Commit the final tested source before tagging; local candidate changes must not remain uncommitted. Only then create the matching version tag at the tested source commit and upload a GitHub release. Public publication and tag creation are separate final actions. Keep `VERSION`, the app, source tag and release assets consistent. Do not advertise notarisation or older macOS support without checking the actual package.
