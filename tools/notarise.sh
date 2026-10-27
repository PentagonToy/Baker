#!/bin/zsh
# Explicit submission only. Credentials stay in an owner-configured Keychain profile.
set -euo pipefail
if [[ $# != 4 ]]; then
    print -u2 'Usage: notarise.sh /path/Baker.app /external/Baker.dmg KEYCHAIN_PROFILE SIGNING_IDENTITY'; exit 1
fi
app="${1:A}"; disk="${2:A}"; profile="$3"; identity="$4"
root="${0:A:h:h}"
work="${disk:h}/notarisation-${disk:t:r}"
mkdir -p "$work"
codesign --verify --deep --strict "$app"
codesign -dvv "$app" 2>&1 | grep '^Authority=Developer ID Application:' >/dev/null
notarise() {
    local file="$1" phase="$2" record="$work/$2-submit.json" submission notary_status
    if [[ ! -s "$record" ]]; then
        xcrun notarytool submit "$file" --keychain-profile "$profile" --output-format json > "$record"
    fi
    submission="$(plutil -extract id raw -o - "$record")"
    # Resuming always waits on the existing ID; a timeout never uploads another copy.
    xcrun notarytool info "$submission" --keychain-profile "$profile" --output-format json > "$work/$phase-info.json"
    notary_status="$(plutil -extract status raw -o - "$work/$phase-info.json")"
    if [[ "$notary_status" == 'In Progress' ]]; then
        xcrun notarytool wait "$submission" --keychain-profile "$profile" --timeout 2m --output-format json > "$work/$phase-wait.json"
        notary_status="$(plutil -extract status raw -o - "$work/$phase-wait.json")"
    fi
    xcrun notarytool log "$submission" --keychain-profile "$profile" "$work/$phase-log.json"
    [[ "$notary_status" == Accepted ]] || { print -u2 "Apple returned $notary_status; inspect $work/$phase-log.json"; return 1; }
}
if ! xcrun stapler validate "$app" >/dev/null 2>&1; then
    if [[ ! -f "$work/app.zip" ]]; then ditto -c -k --keepParent "$app" "$work/app.zip"; fi
    notarise "$work/app.zip" app
    xcrun stapler staple "$app"
fi
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
if [[ ! -f "$disk" ]]; then
    "$root/tools/package_dmg.sh" "$app" "$disk"
    codesign --force --timestamp --sign "$identity" "$disk"
fi
codesign --verify --strict "$disk"
if ! xcrun stapler validate "$disk" >/dev/null 2>&1; then
    notarise "$disk" dmg
    xcrun stapler staple "$disk"
fi
xcrun stapler validate "$disk"
spctl --assess --type open --context context:primary-signature --verbose=2 "$disk"
shasum -a 256 "$disk" > "$work/final-sha256.txt"
print "Accepted and stapled: $disk"
