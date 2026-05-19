#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-.build/arm64-apple-macosx/debug/SwiftGetX}"
OUTPUT_DIR="${2:-dist}"
DMG_NAME="SwiftGetX.dmg"

mkdir -p "$OUTPUT_DIR"

cat <<'MSG'
SwiftGetX package placeholder

This Swift Package currently builds a command-style macOS executable target.
For a production DMG:

1. Generate or maintain an Xcode app project with bundle identifier com.swiftgetx.app.
2. Use Sources/SwiftGetX/Resources/AppInfo.plist as the app Info.plist baseline.
3. Archive with Developer ID Application signing.
4. Export SwiftGetX.app and SwiftGetXNativeHost into dist/.
5. Run:
   hdiutil create -volname SwiftGetX -srcfolder dist/SwiftGetX.app -ov -format UDZO dist/SwiftGetX.dmg
6. Notarize:
   xcrun notarytool submit dist/SwiftGetX.dmg --keychain-profile <profile> --wait
7. Staple:
   xcrun stapler staple dist/SwiftGetX.dmg

The current build artifact is:
MSG

printf '%s\n' "$APP_PATH"
printf 'Planned output: %s/%s\n' "$OUTPUT_DIR" "$DMG_NAME"
