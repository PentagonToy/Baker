# Distribution plan

## Homebrew

Keep the app and cask name **Baker** (`baker`). Prepare a maintained tap using the same versioned DMG and SHA-256 as the direct download. Add an installation command to README after the tap is published and installation is verified. No Homebrew package is currently offered.

Official Homebrew inclusion additionally requires its acceptance and Gatekeeper checks. The current ad-hoc, unnotarised app has not passed those distribution gates. Keep the download and signing guidance accurate; do not disable macOS protections in an installer.
