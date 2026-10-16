#!/bin/zsh
# Explicit build entry point. Run only when a local build is wanted.
set -euo pipefail
source_dir="${0:A:h:h}"
output_root="${BAKER_BUILD_DIRECTORY:-/Volumes/PentagonToy/Workspace/Agents/Repository/baker/local-build}"
build_system="${BAKER_BUILD_SYSTEM:-swiftbuild}"
mkdir -p "$output_root"
cd "$source_dir"
swift build --build-system "$build_system" --scratch-path "$output_root/swift-build" -c debug --arch arm64 --product Baker
binary_dir="$(swift build --build-system "$build_system" --scratch-path "$output_root/swift-build" -c debug --arch arm64 --show-bin-path)"
app="$output_root/Baker.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Baker" "$app/Contents/MacOS/Baker"
# Keep the worker in standard application resources. SwiftPM's native build
# engine emits a flat .bundle that cannot be signed as a nested macOS bundle.
old_resource="$app/Contents/MacOS/Baker_Baker.bundle"
if [[ -d "$old_resource" ]]; then rm -rf -- "$old_resource"; fi
cp "$source_dir/Sources/Baker/Resources/formula_worker.py" "$app/Contents/Resources/"
mkdir -p "$app/Contents/Resources/BakerIcons" "$app/Contents/Resources/BakerSymbols"
for asset in "$source_dir"/others/assests/icons/*.svg(N); do cp "$asset" "$app/Contents/Resources/BakerIcons/"; done
for asset in "$source_dir"/others/assests/symbols/*.svg(N); do cp "$asset" "$app/Contents/Resources/BakerSymbols/"; done
icon_source="$source_dir/others/assests/icons/baker_icon_light.svg"
icon_output="$output_root/Baker.iconset"
if [[ ! -f "$output_root/Baker.icns" || "$icon_source" -nt "$output_root/Baker.icns" || "$source_dir/tools/render_icons.swift" -nt "$output_root/Baker.icns" ]]; then
    swift "$source_dir/tools/render_icons.swift" "$icon_source" "$icon_output"
    iconutil -c icns "$icon_output" -o "$output_root/Baker.icns"
fi
cp "$output_root/Baker.icns" "$app/Contents/Resources/Baker.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.baker.app</string>
<key>CFBundleName</key><string>Baker</string>
<key>CFBundleIconFile</key><string>Baker.icns</string>
<key>CFBundleExecutable</key><string>Baker</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
# A persistent signing identity gives privacy permissions a stable app identity.
# Ad-hoc signing is local-build fallback; rebuilding can require renewed consent.
signing_identity="${BAKER_SIGN_IDENTITY:--}"
codesign --force --sign "$signing_identity" "$app"
print "Prepared: $app"
