#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Apple Developer credentials stay in Keychain, never in this repository.
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool Keychain profile}"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then echo "A Developer ID identity is required for distribution." >&2; exit 1; fi
Scripts/check.sh
Scripts/build.sh
app="$PWD/dist/Photo Viewer.app"
archive="$PWD/dist/PhotoViewer-notarization.zip"
ditto -c -k --keepParent "$app" "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
spctl --assess --type execute --verbose=2 "$app"
rm -f "$archive"
ditto -c -k --keepParent "$app" "$PWD/dist/PhotoViewer-1.0.0-macOS.zip"
shasum -a 256 "$PWD/dist/PhotoViewer-1.0.0-macOS.zip" > "$PWD/dist/PhotoViewer-1.0.0-macOS.zip.sha256"
echo "Notarized release ready in dist/"
