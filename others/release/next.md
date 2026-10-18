# Distribution

## Homebrew

[Baker’s tap](https://github.com/PentagonToy/homebrew-tap) provides `baker` using the same versioned DMG and SHA-256 as the direct download:

```sh
brew install --cask pentagontoy/tap/baker
```

For each app release, update the tap’s `Casks/baker.rb` version and checksum after publishing and verifying the DMG. Check Homebrew’s parsed metadata and test installation and removal before documenting the new version. The cask contains no permission resets, quarantine overrides or user-data removal hooks.

This developer-maintained tap is separate from the official Homebrew cask collection. Official inclusion requires its acceptance and Gatekeeper checks. Baker is currently ad-hoc signed and not notarised; retain accurate first-launch guidance.
