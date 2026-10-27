#!/bin/zsh
set -euo pipefail
if [[ $# != 2 || ! -d "$1/Contents/MacOS" || -e "$2" ]]; then
    print -u2 "Usage: package_dmg.sh /path/to/Baker.app /external/new/Baker.dmg"
    exit 1
fi
app="${1:A}"
output="${2:A}"
source_directory="${0:A:h}"
codesign --verify --deep --strict "$app"
work="$(mktemp -d "${output:h}/.baker-installer.XXXXXX")"
mount=""
cleanup() {
    if [[ -n "$mount" ]] && ! hdiutil detach "$mount" >/dev/null 2>&1; then
        print -u2 "Installer remains mounted at $mount. Temporary files retained at $work."
        return
    fi
    rm -rf -- "$work"
}
trap cleanup EXIT
mkdir -p "$work/staging" "$work/module-cache"
ditto "$app" "$work/staging/Baker.app"
ln -s /Applications "$work/staging/Applications"
swift -module-cache-path "$work/module-cache" "$source_directory/dmg_layout.swift" background "$work/staging/.background.tiff"
# HFS+ Finder presentation needs explicit invisibility, not only a dot-prefixed name.
chflags hidden "$work/staging/.background.tiff"
xcrun SetFile -a V "$work/staging/.background.tiff"
hdiutil create -volname Baker -srcfolder "$work/staging" -fs HFS+ -format UDRW "$work/working.dmg"
hdiutil attach -nobrowse -noautoopen -noverify -readwrite -plist "$work/working.dmg" > "$work/attach.plist"
for index in {0..8}; do
    if volume=$(/usr/libexec/PlistBuddy -c "Print :system-entities:$index:mount-point" "$work/attach.plist" 2>/dev/null); then
        mount="$volume"
        break
    fi
done
[[ -n "$mount" ]] || { print -u2 'Could not locate the installer volume.'; exit 1; }
chflags hidden "$mount/.background.tiff"
xcrun SetFile -a V "$mount/.background.tiff"
clang -Wno-deprecated-declarations -framework CoreServices "$source_directory/dmg_alias.c" -o "$work/dmg-alias"
"$work/dmg-alias" "$mount/.background.tiff" "$work/background-alias"
swift -module-cache-path "$work/module-cache" "$source_directory/dmg_layout.swift" layout "$mount" "$work/background-alias"
hdiutil detach "$mount"
mount=""
hdiutil convert "$work/working.dmg" -format UDZO -o "$output"
hdiutil verify "$output"
