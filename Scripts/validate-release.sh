#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
TARGET_PATH="${2:-}"
APP_INFO_PLIST="${SWIFTGETX_APP_INFO_PLIST:-Sources/SwiftGetX/Resources/AppInfo.plist}"

fail() {
    printf 'Release validation failed: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat >&2 <<USAGE
Usage:
  Scripts/validate-release.sh environment
  Scripts/validate-release.sh sparkle
  Scripts/validate-release.sh app <SwiftGetX.app>
  Scripts/validate-release.sh dmg <SwiftGetX.dmg>
  Scripts/validate-release.sh appcast <appcast.xml>
USAGE
    exit 64
}

require_env() {
    local name="$1"
    if [[ -z "${!name:-}" ]]; then
        fail "Missing required environment variable: $name"
    fi
}

has_any_env() {
    local name
    for name in "$@"; do
        if [[ -n "${!name:-}" ]]; then
            return 0
        fi
    done
    return 1
}

require_any_env() {
    local description="$1"
    shift
    local name
    for name in "$@"; do
        if [[ -n "${!name:-}" ]]; then
            return 0
        fi
    done
    fail "Missing required environment variable for $description: $*"
}

read_plist_value() {
    local key="$1"
    [[ -f "$APP_INFO_PLIST" ]] || fail "Missing AppInfo.plist at $APP_INFO_PLIST"
    /usr/libexec/PlistBuddy -c "Print :$key" "$APP_INFO_PLIST" 2>/dev/null || true
}

base64_decoded_length() {
    local value="$1"
    local length
    if length="$(printf '%s' "$value" | base64 -D 2>/dev/null | wc -c | tr -d '[:space:]')"; then
        printf '%s\n' "$length"
        return 0
    fi
    if length="$(printf '%s' "$value" | base64 --decode 2>/dev/null | wc -c | tr -d '[:space:]')"; then
        printf '%s\n' "$length"
        return 0
    fi
    printf '0\n'
}

validate_sparkle_config() {
    local public_key
    local feed_url
    local decoded_length

    public_key="$(read_plist_value SUPublicEDKey)"
    feed_url="$(read_plist_value SUFeedURL)"

    [[ -n "$public_key" ]] || fail "AppInfo.plist is missing SUPublicEDKey"
    [[ "$public_key" != "REPLACE_WITH_YOUR_EDDSA_PUBLIC_KEY" ]] || fail "SUPublicEDKey is still the placeholder value"
    [[ "$public_key" != "YOUR_EDDSA_PUBLIC_KEY" ]] || fail "SUPublicEDKey is still a placeholder value"
    [[ "$public_key" != "TODO" ]] || fail "SUPublicEDKey is still a placeholder value"
    [[ "$public_key" != "CHANGEME" ]] || fail "SUPublicEDKey is still a placeholder value"

    decoded_length="$(base64_decoded_length "$public_key")"
    [[ "$decoded_length" == "32" ]] || fail "SUPublicEDKey must be a base64 Ed25519 public key that decodes to 32 bytes"

    [[ "$feed_url" == https://* ]] || fail "SUFeedURL must use https"
    [[ "$feed_url" == *appcast.xml ]] || fail "SUFeedURL must point to appcast.xml"

    printf 'Sparkle configuration validation passed.\n'
}

validate_environment() {
    case "${SWIFTGETX_RELEASE_STRICT:-0}" in
        1)
            require_env APPLE_DEVELOPER_ID_CERTIFICATE_BASE64
            require_env APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD
            require_env APPLE_DEVELOPER_ID_APPLICATION_IDENTITY
            require_env APPLE_NOTARY_KEY_ID
            require_env APPLE_NOTARY_ISSUER_ID
            require_any_env "Apple notary API key" APPLE_NOTARY_KEY_PATH APPLE_NOTARY_KEY APPLE_NOTARY_KEY_BASE64
            ;;
        0|"")
            printf 'Developer ID signing and notarization validation skipped; SWIFTGETX_RELEASE_STRICT is not enabled.\n'
            ;;
        *)
            fail "SWIFTGETX_RELEASE_STRICT must be 0 or 1"
            ;;
    esac

    require_env SPARKLE_EDDSA_PRIVATE_KEY

    if [[ "${SWIFTGETX_RELEASE_STRICT:-0}" == "1" ]] \
        || has_any_env CHROME_EXTENSION_KEY_BASE64 SWIFTGETX_CHROME_EXTENSION_KEY_BASE64 SWIFTGETX_CHROME_EXTENSION_KEY_PATH \
        || has_any_env CHROME_EXTENSION_ID SWIFTGETX_EXPECTED_CHROME_EXTENSION_ID; then
        require_any_env "Chrome extension signing key" CHROME_EXTENSION_KEY_BASE64 SWIFTGETX_CHROME_EXTENSION_KEY_BASE64 SWIFTGETX_CHROME_EXTENSION_KEY_PATH
        require_any_env "Chrome extension fixed ID" CHROME_EXTENSION_ID SWIFTGETX_EXPECTED_CHROME_EXTENSION_ID
    else
        printf 'Chrome extension fixed ID validation skipped; no release key or expected ID was provided.\n'
    fi

    validate_sparkle_config
    printf 'Release environment validation passed.\n'
}

validate_app() {
    local app_path="$1"
    [[ -n "$app_path" ]] || usage
    [[ -d "$app_path" ]] || fail "Missing app bundle: $app_path"
    [[ -x "$app_path/Contents/MacOS/SwiftGetX" ]] || fail "Missing main executable in app bundle: $app_path"

    local source_app_info_plist="$APP_INFO_PLIST"
    APP_INFO_PLIST="$app_path/Contents/Info.plist"
    validate_sparkle_config
    APP_INFO_PLIST="$source_app_info_plist"

    codesign --verify --deep --strict --verbose=2 "$app_path"

    local native_host="$app_path/Contents/MacOS/SwiftGetXNativeHost"
    if [[ "${SWIFTGETX_RELEASE_STRICT:-}" == "1" && ! -x "$native_host" ]]; then
        fail "Strict release app bundle is missing SwiftGetXNativeHost"
    fi
    if [[ -e "$native_host" ]]; then
        codesign --verify --strict --verbose=2 "$native_host"
    fi

    local sparkle_framework="$app_path/Contents/Frameworks/Sparkle.framework"
    if [[ "${SWIFTGETX_RELEASE_STRICT:-}" == "1" && ! -d "$sparkle_framework" ]]; then
        fail "Strict release app bundle is missing Sparkle.framework"
    fi
    if [[ -d "$sparkle_framework" ]]; then
        codesign --verify --strict --verbose=2 "$sparkle_framework"
    fi

    if [[ "${SWIFTGETX_RELEASE_STRICT:-}" == "1" && "${SWIFTGETX_REQUIRE_APP_GATEKEEPER:-0}" == "1" ]]; then
        spctl --assess --type execute --verbose=2 "$app_path"
    fi

    printf 'App signing validation passed: %s\n' "$app_path"
}

validate_dmg() {
    local dmg_path="$1"
    [[ -n "$dmg_path" ]] || usage
    [[ -f "$dmg_path" ]] || fail "Missing DMG: $dmg_path"

    if codesign -dv "$dmg_path" >/dev/null 2>&1; then
        codesign --verify --verbose=2 "$dmg_path"
    elif [[ "${SWIFTGETX_RELEASE_STRICT:-}" == "1" ]]; then
        fail "DMG is not signed: $dmg_path"
    else
        printf 'DMG is unsigned; skipping codesign verification for local artifact: %s\n' "$dmg_path"
    fi

    if [[ "${SWIFTGETX_RELEASE_STRICT:-}" == "1" ]]; then
        spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
        xcrun stapler validate "$dmg_path"
    fi

    printf 'DMG release validation passed: %s\n' "$dmg_path"
}

validate_appcast() {
    local appcast_path="$1"
    [[ -n "$appcast_path" ]] || usage
    [[ -f "$appcast_path" ]] || fail "Missing appcast: $appcast_path"

    LC_ALL=C grep -Eq '<enclosure[^>]+url="https://[^"]+"' "$appcast_path" \
        || fail "Appcast enclosure must use an https download URL"
    LC_ALL=C grep -Eq 'sparkle:edSignature="[^"]+"' "$appcast_path" \
        || fail "Appcast is missing sparkle:edSignature"
    LC_ALL=C grep -Eq 'length="[1-9][0-9]*"' "$appcast_path" \
        || fail "Appcast enclosure is missing a positive length"
    LC_ALL=C grep -Eq '<sparkle:releaseNotesLink>https://[^<]+</sparkle:releaseNotesLink>' "$appcast_path" \
        || fail "Appcast is missing an https sparkle:releaseNotesLink"
    LC_ALL=C grep -Eq '<description>[^<]+</description>' "$appcast_path" \
        || fail "Appcast is missing release-note description text"

    printf 'Appcast validation passed: %s\n' "$appcast_path"
}

case "$MODE" in
    environment)
        validate_environment
        ;;
    sparkle)
        validate_sparkle_config
        ;;
    app)
        validate_app "$TARGET_PATH"
        ;;
    dmg)
        validate_dmg "$TARGET_PATH"
        ;;
    appcast)
        validate_appcast "$TARGET_PATH"
        ;;
    *)
        usage
        ;;
esac
