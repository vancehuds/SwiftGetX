#!/usr/bin/env bash
# generate-appcast.sh — Generate or update a Sparkle appcast.xml for a release.
#
# Usage:
#   Scripts/generate-appcast.sh <dmg-path> <version> <download-url>
#
# Environment:
#   SPARKLE_EDDSA_PRIVATE_KEY  — Base64-encoded EdDSA private key for signing
#
# Output:
#   dist/appcast/appcast.xml
set -euo pipefail

DMG_PATH="${1:?Usage: $0 <dmg-path> <version> <download-url>}"
VERSION="${2:?Missing version argument}"
DOWNLOAD_URL="${3:?Missing download URL argument}"
OUTPUT_DIR="${4:-dist/appcast}"

if [[ -z "${SPARKLE_EDDSA_PRIVATE_KEY:-}" ]]; then
    printf 'Error: SPARKLE_EDDSA_PRIVATE_KEY environment variable is required.\n' >&2
    exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
    printf 'Error: DMG not found at %s\n' "$DMG_PATH" >&2
    exit 66
fi

# Compute file length
FILE_LENGTH="$(stat -f%z "$DMG_PATH" 2>/dev/null || stat --printf='%s' "$DMG_PATH" 2>/dev/null)"

# Sign the update using Sparkle's sign_update tool.
# The tool is shipped as a binary artifact in the Sparkle SPM package.
SIGN_UPDATE=""
for candidate in \
    .build/artifacts/sparkle/Sparkle/bin/sign_update \
    .build/artifacts/Sparkle/bin/sign_update \
    "$(find .build -name sign_update -type f 2>/dev/null | head -1)"; do
    if [[ -x "$candidate" ]]; then
        SIGN_UPDATE="$candidate"
        break
    fi
done

if [[ -z "$SIGN_UPDATE" ]]; then
    printf 'Error: Could not find Sparkle sign_update tool. Run swift build first.\n' >&2
    exit 69
fi

# sign_update reads the private key from the environment variable
ED_SIGNATURE="$(echo "$SPARKLE_EDDSA_PRIVATE_KEY" | "$SIGN_UPDATE" "$DMG_PATH" --ed-key-file -)"

# Extract just the signature value (sign_update outputs sparkle:edSignature="..." length="...")
# Parse the edSignature attribute
SIG_VALUE="$(echo "$ED_SIGNATURE" | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"$//' || echo "")"

# If the output is just the raw signature (newer versions), use it directly
if [[ -z "$SIG_VALUE" ]]; then
    SIG_VALUE="$ED_SIGNATURE"
fi

PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S %z')"

mkdir -p "$OUTPUT_DIR"

cat > "$OUTPUT_DIR/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>SwiftGetX Updates</title>
        <link>https://github.com/vancehudson/SwiftGetX</link>
        <description>Most recent changes with links to updates.</description>
        <language>en</language>
        <item>
            <title>Version ${VERSION}</title>
            <link>https://github.com/vancehudson/SwiftGetX/releases/tag/v${VERSION}</link>
            <sparkle:version>${VERSION}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <pubDate>${PUB_DATE}</pubDate>
            <enclosure url="${DOWNLOAD_URL}"
                       sparkle:edSignature="${SIG_VALUE}"
                       length="${FILE_LENGTH}"
                       type="application/octet-stream" />
        </item>
    </channel>
</rss>
EOF

printf 'Appcast generated at %s/appcast.xml (version %s)\n' "$OUTPUT_DIR" "$VERSION"
