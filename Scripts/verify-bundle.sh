#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/dist/Photo Viewer.app"
plutil -lint "$app/Contents/Info.plist" "$app/Contents/Resources/PrivacyInfo.xcprivacy"
codesign --verify --deep --strict --verbose=2 "$app"
lipo "$app/Contents/MacOS/PhotoViewer" -verify_arch arm64 x86_64
test -s "$app/Contents/Resources/AppIcon.icns"
# A distributable bundle must not depend on Homebrew or a developer's home directory.
if otool -L "$app/Contents/MacOS/PhotoViewer" | /usr/bin/grep -E '/opt/homebrew|/usr/local|/Users/.*\.dylib'; then
    echo "Unexpected local library dependency" >&2; exit 1
fi
echo "Universal app metadata, signature, icon, and dependencies verified."
