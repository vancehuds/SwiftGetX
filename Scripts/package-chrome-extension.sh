#!/usr/bin/env bash
set -euo pipefail

EXTENSION_DIR="${1:-Sources/SwiftGetX/Resources/ChromeExtension}"
OUTPUT_DIR="${2:-dist/chrome}"
ZIP_NAME="SwiftGetX-Chrome.zip"
CRX_NAME="SwiftGetX-Chrome.crx"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
CRX_PATH="$OUTPUT_DIR/$CRX_NAME"
METADATA_PATH="$OUTPUT_DIR/SwiftGetX-Chrome.release.json"
ID_PATH="$OUTPUT_DIR/SwiftGetX-Chrome.id"
RELEASE_STRICT="${SWIFTGETX_RELEASE_STRICT:-0}"

fail() {
    printf 'Chrome extension packaging failed: %s\n' "$*" >&2
    exit 1
}

if [[ ! -d "$EXTENSION_DIR" ]]; then
    printf 'Missing Chrome extension directory: %s\n' "$EXTENSION_DIR" >&2
    exit 66
fi

if [[ ! -f "$EXTENSION_DIR/manifest.json" ]]; then
    printf 'Missing manifest.json in %s\n' "$EXTENSION_DIR" >&2
    exit 66
fi

if [[ "$RELEASE_STRICT" == "1" ]]; then
    if [[ -z "${SWIFTGETX_CHROME_EXTENSION_KEY_BASE64:-${CHROME_EXTENSION_KEY_BASE64:-}}" && -z "${SWIFTGETX_CHROME_EXTENSION_KEY_PATH:-}" ]]; then
        fail "SWIFTGETX_CHROME_EXTENSION_KEY_BASE64, CHROME_EXTENSION_KEY_BASE64, or SWIFTGETX_CHROME_EXTENSION_KEY_PATH is required when SWIFTGETX_RELEASE_STRICT=1"
    fi
    if [[ -z "${SWIFTGETX_EXPECTED_CHROME_EXTENSION_ID:-${CHROME_EXTENSION_ID:-}}" ]]; then
        fail "SWIFTGETX_EXPECTED_CHROME_EXTENSION_ID or CHROME_EXTENSION_ID is required when SWIFTGETX_RELEASE_STRICT=1"
    fi
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$ZIP_PATH" "$CRX_PATH" "$METADATA_PATH" "$ID_PATH"

ABS_ZIP_PATH="$(cd "$(dirname "$ZIP_PATH")" && pwd)/$(basename "$ZIP_PATH")"
ABS_CRX_PATH="$(cd "$(dirname "$CRX_PATH")" && pwd)/$(basename "$CRX_PATH")"
EXTENSION_ROOT="$(cd "$EXTENSION_DIR" && pwd)"
MANIFEST_VERSION="$(node -e 'const fs=require("fs"); const manifest=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); console.log(manifest.version || "");' "$EXTENSION_ROOT/manifest.json")"

(
    cd "$EXTENSION_ROOT"
    find . \
        -name '.DS_Store' -prune -o \
        -type f -print \
        | LC_ALL=C sort \
        | zip -X -q "$ABS_ZIP_PATH" -@
)

export SWIFTGETX_CHROME_EXTENSION_ID_FILE="$ID_PATH"
if [[ -z "${SWIFTGETX_CHROME_EXTENSION_KEY_BASE64:-}" && -n "${CHROME_EXTENSION_KEY_BASE64:-}" ]]; then
    export SWIFTGETX_CHROME_EXTENSION_KEY_BASE64="$CHROME_EXTENSION_KEY_BASE64"
fi
if [[ -z "${SWIFTGETX_EXPECTED_CHROME_EXTENSION_ID:-}" && -n "${CHROME_EXTENSION_ID:-}" ]]; then
    export SWIFTGETX_EXPECTED_CHROME_EXTENSION_ID="$CHROME_EXTENSION_ID"
fi

node "$(dirname "$0")/make-crx.mjs" "$ABS_ZIP_PATH" "$ABS_CRX_PATH"

EXTENSION_ID="$(tr -d '[:space:]' < "$ID_PATH")"
cat > "$METADATA_PATH" <<JSON
{
  "name": "SwiftGetX Chrome Extension",
  "version": "$MANIFEST_VERSION",
  "extensionID": "$EXTENSION_ID",
  "zip": "$ZIP_NAME",
  "crx": "$CRX_NAME",
  "releaseStrict": "$RELEASE_STRICT"
}
JSON

printf 'Packaged %s\n' "$ZIP_PATH"
printf 'Packaged %s\n' "$CRX_PATH"
printf 'Wrote %s\n' "$METADATA_PATH"
