#!/usr/bin/env bash
set -euo pipefail

HOST_BINARY="${1:-$PWD/.build/arm64-apple-macosx/debug/SwiftGetXNativeHost}"
CHROME_EXTENSION_ID="${2:-REPLACE_WITH_CHROME_EXTENSION_ID}"
HOST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
HOST_FILE="$HOST_DIR/com.swiftgetx.native.json"

if [[ ! -x "$HOST_BINARY" ]]; then
  echo "Native host binary not found or not executable: $HOST_BINARY" >&2
  echo "Run: swift build" >&2
  exit 1
fi

mkdir -p "$HOST_DIR"
cat > "$HOST_FILE" <<JSON
{
  "name": "com.swiftgetx.native",
  "description": "SwiftGetX Native Messaging host",
  "path": "$HOST_BINARY",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$CHROME_EXTENSION_ID/"
  ]
}
JSON

echo "Installed Chrome Native Messaging host:"
echo "$HOST_FILE"
