#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${1:-debug}"
OUTPUT_DIR="${2:-dist}"
CREATE_DMG="${3:-}"
APP_NAME="SwiftGetX"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/swiftgetx-package.XXXXXX")"
DMG_ROOT="$STAGING_DIR/dmg-root"
STAGED_APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
INFO_PLIST="Sources/SwiftGetX/Resources/AppInfo.plist"
ICON_FILE="Sources/SwiftGetX/Resources/Assets/AppIcon.icns"

# Derive version from git tag (e.g. v1.2.3 → 1.2.3), fallback to 0.1.0-dev
GIT_TAG="$(git describe --tags --exact-match 2>/dev/null || echo "")"
if [[ -n "$GIT_TAG" ]]; then
    APP_VERSION="${GIT_TAG#v}"
else
    APP_VERSION="${SWIFTGETX_VERSION:-0.1.0-dev}"
fi
printf 'App version: %s\n' "$APP_VERSION"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

case "$CONFIGURATION" in
    debug|release)
        ;;
    *)
        printf 'Usage: %s [debug|release] [output-dir] [--dmg]\n' "$0" >&2
        exit 64
        ;;
esac

if [[ "${SWIFTGETX_DISABLE_LIBTORRENT:-}" != "1" ]]; then
    Scripts/build-libtorrent.sh
    export SWIFTGETX_ENABLE_LIBTORRENT=1
fi

if [[ "$CONFIGURATION" == "release" ]]; then
    swift build --configuration release
    BUILD_DIR="$(swift build --configuration release --show-bin-path)"
else
    swift build
    BUILD_DIR="$(swift build --show-bin-path)"
fi
EXECUTABLE="$BUILD_DIR/$APP_NAME"
NATIVE_HOST="$BUILD_DIR/SwiftGetXNativeHost"
RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"

if [[ ! -x "$EXECUTABLE" ]]; then
    printf 'Missing executable: %s\n' "$EXECUTABLE" >&2
    exit 66
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$STAGED_APP_BUNDLE/Contents/MacOS" "$STAGED_APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE" "$STAGED_APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [[ -x "$NATIVE_HOST" ]]; then
    cp "$NATIVE_HOST" "$STAGED_APP_BUNDLE/Contents/MacOS/SwiftGetXNativeHost"
fi

cp "$INFO_PLIST" "$STAGED_APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$STAGED_APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$STAGED_APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" "$STAGED_APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$STAGED_APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$STAGED_APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$STAGED_APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$STAGED_APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $APP_VERSION" "$STAGED_APP_BUNDLE/Contents/Info.plist"

cp "$ICON_FILE" "$STAGED_APP_BUNDLE/Contents/Resources/AppIcon.icns"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$STAGED_APP_BUNDLE/Contents/Resources/"
fi

xattr -cr "$STAGED_APP_BUNDLE" 2>/dev/null || true
codesign --force --deep --sign - "$STAGED_APP_BUNDLE"
mkdir -p "$OUTPUT_DIR"
ditto --noextattr --noqtn "$STAGED_APP_BUNDLE" "$APP_BUNDLE"

if [[ "$CREATE_DMG" == "--dmg" ]]; then
    rm -rf "$DMG_ROOT" "$OUTPUT_DIR/$APP_NAME.dmg"
    mkdir -p "$DMG_ROOT"
    cp -R "$APP_BUNDLE" "$DMG_ROOT/"
    ln -s /Applications "$DMG_ROOT/Applications"
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_ROOT" \
        -ov \
        -format UDZO \
        "$OUTPUT_DIR/$APP_NAME.dmg"
fi

printf 'Packaged %s\n' "$APP_BUNDLE"
