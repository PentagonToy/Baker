#!/bin/zsh
# Explicit build entry point. Run only when a local build is wanted.
set -euo pipefail
source_dir="${0:A:h:h}"
app_version="$(<"$source_dir/VERSION")"
if [[ ! "$app_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    print -u2 "VERSION must contain a semantic version such as 0.0.1"; exit 1
fi
output_root="${BAKER_BUILD_DIRECTORY:-/Volumes/PentagonToy/Workspace/Agents/Repository/baker/local-build}"
build_system="${BAKER_BUILD_SYSTEM:-swiftbuild}"
build_configuration="${BAKER_BUILD_CONFIGURATION:-release}"
case "$build_configuration" in
    debug|release) ;;
    *) print -u2 "Choose BAKER_BUILD_CONFIGURATION=debug or release"; exit 1 ;;
esac
mkdir -p "$output_root"
cd "$source_dir"
swift build --build-system "$build_system" --scratch-path "$output_root/swift-build" -c "$build_configuration" --arch arm64 --product Baker
binary_dir="$(swift build --build-system "$build_system" --scratch-path "$output_root/swift-build" -c "$build_configuration" --arch arm64 --show-bin-path)"
app="$output_root/Baker.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Baker" "$app/Contents/MacOS/Baker"
# Keep the worker in standard application resources. SwiftPM's native build
# engine emits a flat .bundle that cannot be signed as a nested macOS bundle.
old_resource="$app/Contents/MacOS/Baker_Baker.bundle"
if [[ -d "$old_resource" ]]; then rm -rf -- "$old_resource"; fi
cp -R "$source_dir/Sources/BakerCore/Resources/Tessdata" "$app/Contents/Resources/"
cp -R "$source_dir/Sources/BakerCore/Resources/Fonts" "$app/Contents/Resources/"
# Replace the complete pinned renderer to avoid retaining stale vendor files.
if [[ -d "$app/Contents/Resources/FormulaPreview" ]]; then rm -rf -- "$app/Contents/Resources/FormulaPreview"; fi
cp -R "$source_dir/Sources/Baker/Resources/FormulaPreview" "$app/Contents/Resources/"
cp "$source_dir/Sources/Baker/Resources/plugin_unpack.py" "$app/Contents/Resources/"
cp "$source_dir/Sources/Baker/Resources/formula_model_install.py" "$app/Contents/Resources/"
cp "$source_dir/Sources/Baker/Resources/image_tools_worker.py" "$app/Contents/Resources/"
cp "$source_dir/Sources/Baker/Resources/formula_worker.py" "$source_dir/Sources/Baker/Resources/texo_worker.py" "$source_dir/Sources/Baker/Resources/texo-model.json" "$source_dir/Sources/Baker/Resources/plus_s_worker.py" "$source_dir/Sources/Baker/Resources/plus-s-model.json" "$app/Contents/Resources/"
cp -R "$source_dir/Sources/Baker/Resources/FormulaNotices" "$app/Contents/Resources/"
cp "$source_dir/Sources/Baker/Resources/document_worker.py" "$source_dir/Sources/Baker/Resources/document_reconstruction.py" "$app/Contents/Resources/"
cp "$source_dir/Sources/Baker/Resources/formula-model.json" "$source_dir/Sources/Baker/Resources/formula-model-canonical.json" "$app/Contents/Resources/"
cp "$source_dir/Sources/Baker/Resources/pdf_engine_install.py" "$app/Contents/Resources/"
cp "${BAKER_PDF_ENGINE_MANIFEST:-$source_dir/Sources/Baker/Resources/pdf-engine.json}" "$app/Contents/Resources/pdf-engine.json"
# A release contains a relocatable interpreter, OCR libraries and Tesseract.
# Build this separately with tools/bundle_runtime.py; never copy a virtualenv.
if [[ -n "${BAKER_RUNTIME_DIRECTORY:-}" ]]; then
    if [[ -d "$app/Contents/Resources/Runtime" ]]; then rm -rf -- "$app/Contents/Resources/Runtime"; fi
    cp -R "$BAKER_RUNTIME_DIRECTORY" "$app/Contents/Resources/Runtime"
    find "$app/Contents/Resources/Runtime" -type d -name __pycache__ -prune -exec rm -rf {} +
elif [[ "$build_configuration" == release && ! -d "$app/Contents/Resources/Runtime" ]]; then
    print -u2 "A complete release needs BAKER_RUNTIME_DIRECTORY; see tools/bundle_runtime.py"
    exit 1
fi
# A reused runtime must contain plus-S's small text-repair dependencies.
if [[ -x "$app/Contents/Resources/Runtime/python/bin/python3.12" ]]; then
    "$app/Contents/Resources/Runtime/python/bin/python3.12" -I -B -c 'import ftfy, wcwidth' || { print -u2 "Regenerate Runtime with tools/formula-requirements.txt before building this app."; exit 1; }
fi
# Image tracing uses the existing interpreter and pinned local payloads, never a download.
if [[ -x "$app/Contents/Resources/Runtime/python/bin/python3.12" ]]; then
    [[ -d "$app/Contents/Resources/ImageTools" ]] && rm -rf -- "$app/Contents/Resources/ImageTools"
    "$app/Contents/Resources/Runtime/python/bin/python3.12" -I -B "$source_dir/tools/prepare_image_tools.py" --destination "$app/Contents/Resources/ImageTools" --relocate
fi
if [[ -n "${BAKER_DOCUMENT_ENGINE_DIRECTORY:-}" ]]; then
    if [[ -d "$app/Contents/Resources/DocumentEngine" ]]; then rm -rf -- "$app/Contents/Resources/DocumentEngine"; fi
    cp -R "$BAKER_DOCUMENT_ENGINE_DIRECTORY" "$app/Contents/Resources/DocumentEngine"
    find "$app/Contents/Resources/DocumentEngine" -type d -name __pycache__ -prune -exec rm -rf {} +
elif [[ -d "$app/Contents/Resources/DocumentEngine" ]]; then
    # Reusing a build folder must not retain a previous full PDF engine.
    rm -rf -- "$app/Contents/Resources/DocumentEngine"
fi
# Formula weights are optional downloads. Also strip them from reused runtimes.
for model_folder in "$app/Contents/Resources/Runtime/mfr" "$app/Contents/Resources/Runtime/texo" "$app/Contents/Resources/Runtime/plus-s"; do
    [[ ! -d "$model_folder" ]] || rm -rf -- "$model_folder"
done
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
mkdir -p "$app/Contents/Resources/CLI"
cp "$source_dir/tools/bundled_cli" "$app/Contents/Resources/CLI/baker"
chmod +x "$app/Contents/Resources/CLI/baker"
mkdir -p "$app/Contents/Resources/Legal"
cp "$source_dir/LICENSE" "$app/Contents/Resources/Legal/LICENSE"
cp "$source_dir/docs/legal/third-party.md" "$app/Contents/Resources/Legal/THIRD-PARTY.md"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.baker.app</string>
<key>CFBundleName</key><string>Baker</string>
<key>CFBundleIconFile</key><string>Baker.icns</string>
<key>CFBundleExecutable</key><string>Baker</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$app_version</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
if [[ -f "$app/Contents/Resources/Runtime/manifest.json" ]]; then
    minimum_os="$(plutil -extract minimum_macos raw -o - "$app/Contents/Resources/Runtime/manifest.json")"
    /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $minimum_os" "$app/Contents/Info.plist"
fi
if [[ -f "$app/Contents/Resources/DocumentEngine/manifest.json" ]]; then
    document_minimum="$(plutil -extract minimum_macos raw -o - "$app/Contents/Resources/DocumentEngine/manifest.json")"
    current_minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")"
    if [[ "$(printf '%s\n' "$document_minimum" "$current_minimum" | sort -V | tail -1)" == "$document_minimum" ]]; then
        /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $document_minimum" "$app/Contents/Info.plist"
    fi
fi
# A persistent signing identity gives privacy permissions a stable app identity.
# Ad-hoc signing is local-build fallback; rebuilding can require renewed consent.
signing_identity="${BAKER_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" && -f "$source_dir/others/builder/builder.local.json" ]]; then
    signing_identity="$(plutil -extract signing_identity raw -o - "$source_dir/others/builder/builder.local.json" 2>/dev/null || true)"
fi
local_identity="$HOME/Library/Application Support/PentagonToy/Development/signing-identity"
if [[ -z "$signing_identity" && -f "$local_identity" ]]; then
    signing_identity="$(<"$local_identity")"
fi
signing_identity="${signing_identity:--}"
for runtime_folder in "$app/Contents/Resources/Runtime" "$app/Contents/Resources/DocumentEngine" "$app/Contents/Resources/ImageTools"; do
    [[ -d "$runtime_folder" ]] || continue
    while IFS= read -r -d '' native_file; do
        if file -b "$native_file" | grep -q 'Mach-O'; then codesign --force --sign "$signing_identity" "$native_file"; fi
    done < <(find "$runtime_folder" -type f \( -name '*.so' -o -name '*.dylib' -o -perm -111 \) -print0)
done
codesign --force --sign "$signing_identity" "$app"
print "Prepared: $app"
