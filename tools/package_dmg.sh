#!/bin/zsh
set -euo pipefail
if [[ $# != 2 || ! -d "$1/Contents/MacOS" || -e "$2" ]]; then
    print -u2 "Usage: package_dmg.sh /path/to/Baker.app /external/new/Baker.dmg"
    exit 1
fi
app="${1:A}"
output="${2:A}"
codesign --verify --deep --strict "$app"
staging="$(mktemp -d "${output:h}/.baker-installer.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
cp -R "$app" "$staging/Baker.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Baker -srcfolder "$staging" -format UDZO -o "$output"
hdiutil verify "$output"
