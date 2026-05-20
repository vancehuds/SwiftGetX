#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/libtorrent"
INSTALL_DIR="$ROOT_DIR/.build/libtorrent-install"
VENDOR_DIR="$ROOT_DIR/Vendor/libtorrent"
VERSION_FILE="$ROOT_DIR/Vendor/libtorrent.version"

version_value() {
  awk -F': ' -v key="$1" '$1 == key { print $2 }' "$VERSION_FILE"
}

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required to build libtorrent." >&2
  echo "Install it first, for example: brew install cmake boost openssl" >&2
  exit 127
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required to fetch and verify vendored libtorrent." >&2
  exit 127
fi

LIBTORRENT_URL="$(version_value url)"
LIBTORRENT_TAG="$(version_value tag)"
LIBTORRENT_COMMIT="$(version_value commit)"

if [[ -z "$LIBTORRENT_URL" || -z "$LIBTORRENT_COMMIT" ]]; then
  echo "Missing libtorrent url or commit in $VERSION_FILE." >&2
  exit 65
fi

if [[ ! -d "$VENDOR_DIR/.git" ]]; then
  rm -rf "$VENDOR_DIR"
  mkdir -p "$(dirname "$VENDOR_DIR")"
  git clone --branch "$LIBTORRENT_TAG" --single-branch "$LIBTORRENT_URL" "$VENDOR_DIR"
fi

git -C "$VENDOR_DIR" fetch --tags --force origin "$LIBTORRENT_COMMIT"
git -C "$VENDOR_DIR" checkout --detach "$LIBTORRENT_COMMIT"

CURRENT_COMMIT="$(git -C "$VENDOR_DIR" rev-parse HEAD)"
if [[ "$CURRENT_COMMIT" != "$LIBTORRENT_COMMIT" ]]; then
  echo "libtorrent checkout mismatch: expected $LIBTORRENT_COMMIT, got $CURRENT_COMMIT." >&2
  exit 65
fi

if [[ ! -f "$VENDOR_DIR/deps/try_signal/try_signal.cpp" ]]; then
  git -C "$VENDOR_DIR" submodule update --init deps/try_signal deps/asio-gnutls
fi

cmake -S "$ROOT_DIR/Native/CSwiftGetXLibtorrent" \
  -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DBUILD_SHARED_LIBS=OFF

cmake --build "$BUILD_DIR" --target CSwiftGetXLibtorrent --config Release

echo "Built CSwiftGetXLibtorrent in $BUILD_DIR"
