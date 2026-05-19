#!/usr/bin/env bash
set -euo pipefail

EXTENSION_DIR="${1:-Sources/SwiftGetX/Resources/ChromeExtension}"
OUTPUT_DIR="${2:-dist/chrome}"
ZIP_NAME="SwiftGetX-Chrome.zip"
CRX_NAME="SwiftGetX-Chrome.crx"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
CRX_PATH="$OUTPUT_DIR/$CRX_NAME"

if [[ ! -d "$EXTENSION_DIR" ]]; then
    printf 'Missing Chrome extension directory: %s\n' "$EXTENSION_DIR" >&2
    exit 66
fi

if [[ ! -f "$EXTENSION_DIR/manifest.json" ]]; then
    printf 'Missing manifest.json in %s\n' "$EXTENSION_DIR" >&2
    exit 66
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$ZIP_PATH" "$CRX_PATH"

ABS_ZIP_PATH="$(cd "$(dirname "$ZIP_PATH")" && pwd)/$(basename "$ZIP_PATH")"
ABS_CRX_PATH="$(cd "$(dirname "$CRX_PATH")" && pwd)/$(basename "$CRX_PATH")"
EXTENSION_ROOT="$(cd "$EXTENSION_DIR" && pwd)"

(
    cd "$EXTENSION_ROOT"
    find . \
        -name '.DS_Store' -prune -o \
        -type f -print \
        | LC_ALL=C sort \
        | zip -X -q "$ABS_ZIP_PATH" -@
)

node "$(dirname "$0")/make-crx.mjs" "$ABS_ZIP_PATH" "$ABS_CRX_PATH"

printf 'Packaged %s\n' "$ZIP_PATH"
printf 'Packaged %s\n' "$CRX_PATH"
