#!/usr/bin/env bash
set -euo pipefail

HOST_BINARY="${1:-$PWD/.build/arm64-apple-macosx/debug/SwiftGetXNativeHost}"
CHROME_EXTENSION_ID="${SWIFTGETX_CHROME_EXTENSION_ID:-${2:-}}"
HOST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
HOST_FILE="$HOST_DIR/com.swiftgetx.native.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -x "$HOST_BINARY" ]]; then
  echo "Native host binary not found or not executable: $HOST_BINARY" >&2
  echo "Run: swift build" >&2
  exit 1
fi

read_existing_extension_ids() {
  if [[ ! -f "$HOST_FILE" ]]; then
    return
  fi

  node - "$HOST_FILE" <<'NODE'
const { readFileSync } = require("node:fs");
const file = process.argv[2];
const manifest = JSON.parse(readFileSync(file, "utf8"));
const origins = Array.isArray(manifest.allowed_origins) ? manifest.allowed_origins : [];
for (const origin of origins) {
  const match = /^chrome-extension:\/\/([a-p]{32})\/$/.exec(origin);
  if (match) {
    console.log(match[1]);
  }
}
NODE
}

discover_extension_ids() {
  node "$SCRIPT_DIR/find-chrome-extension-id.mjs"
}

normalize_extension_ids() {
  tr ',[:space:]' '\n' \
    | sed '/^$/d' \
    | while read -r id; do
        if [[ "$id" =~ ^[a-p]{32}$ ]]; then
          printf '%s\n' "$id"
        else
          printf 'Ignoring invalid Chrome extension ID: %s\n' "$id" >&2
        fi
      done \
    | awk '!seen[$0]++'
}

RESOLVED_EXTENSION_IDS="$(
  {
    if [[ -n "$CHROME_EXTENSION_ID" ]]; then
      printf '%s\n' "$CHROME_EXTENSION_ID"
    else
      read_existing_extension_ids || true
      discover_extension_ids || true
    fi
  } | normalize_extension_ids
)"

if [[ -z "$RESOLVED_EXTENSION_IDS" ]]; then
  echo "Could not find a SwiftGetX Chrome extension ID." >&2
  echo "Install or enable the SwiftGetX Chrome extension, then run this script again." >&2
  echo "You can also pass an ID explicitly or set SWIFTGETX_CHROME_EXTENSION_ID." >&2
  exit 1
fi

mkdir -p "$HOST_DIR"
HOST_BINARY="$HOST_BINARY" HOST_FILE="$HOST_FILE" RESOLVED_EXTENSION_IDS="$RESOLVED_EXTENSION_IDS" node <<'NODE'
const { writeFileSync } = require("node:fs");

const allowedOrigins = process.env.RESOLVED_EXTENSION_IDS
  .split(/\s+/)
  .filter(Boolean)
  .map((id) => `chrome-extension://${id}/`);

const manifest = {
  name: "com.swiftgetx.native",
  description: "SwiftGetX Native Messaging host",
  path: process.env.HOST_BINARY,
  type: "stdio",
  allowed_origins: allowedOrigins
};

writeFileSync(process.env.HOST_FILE, `${JSON.stringify(manifest, null, 2)}\n`);
NODE

echo "Installed Chrome Native Messaging host:"
echo "$HOST_FILE"
echo "Allowed Chrome extension IDs:"
printf '%s\n' "$RESOLVED_EXTENSION_IDS"
