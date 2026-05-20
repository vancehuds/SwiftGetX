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
STAGED_FRAMEWORKS_DIR="$STAGED_APP_BUNDLE/Contents/Frameworks"
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

remove_packaging_xattrs() {
    local bundle_path="$1"
    local attribute
    local path

    xattr -cr "$bundle_path" 2>/dev/null || true
    for attribute in com.apple.FinderInfo com.apple.ResourceFork 'com.apple.fileprovider.fpfs#P'; do
        while IFS= read -r -d '' path; do
            xattr -d "$attribute" "$path" 2>/dev/null || true
        done < <(find "$bundle_path" -xattrname "$attribute" -print0)
    done
}

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
SPARKLE_FRAMEWORK="$BUILD_DIR/Sparkle.framework"

if [[ ! -x "$EXECUTABLE" ]]; then
    printf 'Missing executable: %s\n' "$EXECUTABLE" >&2
    exit 66
fi
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    printf 'Missing Sparkle framework: %s\n' "$SPARKLE_FRAMEWORK" >&2
    exit 66
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$STAGED_APP_BUNDLE/Contents/MacOS" "$STAGED_APP_BUNDLE/Contents/Resources" "$STAGED_FRAMEWORKS_DIR"

cp "$EXECUTABLE" "$STAGED_APP_BUNDLE/Contents/MacOS/$APP_NAME"
if [[ -x "$NATIVE_HOST" ]]; then
    cp "$NATIVE_HOST" "$STAGED_APP_BUNDLE/Contents/MacOS/SwiftGetXNativeHost"
fi
ditto --noextattr --noqtn "$SPARKLE_FRAMEWORK" "$STAGED_FRAMEWORKS_DIR/Sparkle.framework"
if ! otool -l "$STAGED_APP_BUNDLE/Contents/MacOS/$APP_NAME" | grep -Fq "path @executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$STAGED_APP_BUNDLE/Contents/MacOS/$APP_NAME"
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

remove_packaging_xattrs "$STAGED_APP_BUNDLE"
codesign --force --deep --sign - "$STAGED_APP_BUNDLE"
codesign --verify --deep "$STAGED_APP_BUNDLE"
mkdir -p "$OUTPUT_DIR"
ditto --noextattr --noqtn "$STAGED_APP_BUNDLE" "$APP_BUNDLE"
remove_packaging_xattrs "$APP_BUNDLE"
codesign --verify --deep "$APP_BUNDLE"

if [[ "$CREATE_DMG" == "--dmg" ]]; then
    rm -rf "$DMG_ROOT" "$OUTPUT_DIR/$APP_NAME.dmg"
    mkdir -p "$DMG_ROOT"
    ditto --noextattr --noqtn "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
    remove_packaging_xattrs "$DMG_ROOT/$APP_NAME.app"
    codesign --verify --deep "$DMG_ROOT/$APP_NAME.app"
    ln -s /Applications "$DMG_ROOT/Applications"
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_ROOT" \
        -ov \
        -format UDZO \
        "$OUTPUT_DIR/$APP_NAME.dmg"
fi

printf 'Packaged %s\n' "$APP_BUNDLE"
