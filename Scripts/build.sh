#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
mkdir -p .build/module-cache dist
configuration="${CONFIGURATION:-release}"
architectures="${ARCHS:-arm64 x86_64}"
app="$PWD/dist/Glance.app"
# Stage separately so an interrupted build cannot corrupt the last working app.
staging="$PWD/dist/.Glance.staging.app"
rm -rf "$staging"
mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources"
binaries=()
for architecture in $architectures; do
    swift build --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" \
        --security-path "$PWD/.build/security" --scratch-path "$PWD/.build/$architecture" \
        --triple "$architecture-apple-macosx14.0" -c "$configuration" --product Glance
    binary_path=$(swift build --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" \
        --security-path "$PWD/.build/security" --scratch-path "$PWD/.build/$architecture" \
        --triple "$architecture-apple-macosx14.0" -c "$configuration" --show-bin-path)
    binaries+=("$binary_path/Glance")
done
lipo -create "${binaries[@]}" -output "$staging/Contents/MacOS/Glance"
cp Resources/Info.plist "$staging/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$staging/Contents/Resources/PrivacyInfo.xcprivacy"
swift Scripts/make-icon.swift "$PWD/.build/AppIcon.iconset"
iconutil -c icns "$PWD/.build/AppIcon.iconset" -o "$staging/Contents/Resources/AppIcon.icns"
plutil -lint "$staging/Contents/Info.plist" "$staging/Contents/Resources/PrivacyInfo.xcprivacy"
identity="${SIGNING_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
    codesign --force --sign - --options runtime "$staging"
else
    codesign --force --sign "$identity" --options runtime --timestamp "$staging"
fi
codesign --verify --deep --strict --verbose=2 "$staging"
rm -rf "$app"
mv "$staging" "$app"
echo "Built: $app"
