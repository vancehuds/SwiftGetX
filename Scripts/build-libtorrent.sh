#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/libtorrent"
INSTALL_DIR="$ROOT_DIR/.build/libtorrent-install"

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required to build libtorrent." >&2
  echo "Install it first, for example: brew install cmake boost openssl" >&2
  exit 127
fi

if [[ ! -f "$ROOT_DIR/Vendor/libtorrent/deps/try_signal/try_signal.cpp" ]]; then
  echo "libtorrent submodules are missing." >&2
  echo "Run: git -C Vendor/libtorrent submodule update --init deps/try_signal deps/asio-gnutls" >&2
  exit 128
fi

cmake -S "$ROOT_DIR/Native/CSwiftGetXLibtorrent" \
  -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DBUILD_SHARED_LIBS=OFF

cmake --build "$BUILD_DIR" --target CSwiftGetXLibtorrent --config Release

echo "Built CSwiftGetXLibtorrent in $BUILD_DIR"
