#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="debug"
RUN_TESTS=1
ENABLE_NATIVE_LIBTORRENT=0
PACKAGE_APP=0
CREATE_DMG=0
INSTALL_NATIVE_HOST=0
CHROME_EXTENSION_ID=""
CLEAN_BUILD=0
RUN_APP=0

usage() {
  cat <<'EOF'
Usage: Scripts/local-build.sh [options]

Build and test SwiftGetX locally with one command.

Options:
  --debug                       Build the debug configuration. This is the default.
  --release                     Build the release configuration.
  --native-libtorrent           Build and enable the optional native libtorrent engine.
  --skip-tests                  Build only; do not run swift test.
  --package                     Assemble dist/SwiftGetX.app after the SwiftPM build.
  --dmg                         Assemble dist/SwiftGetX.app and dist/SwiftGetX.dmg.
  --install-native-host [id]    Install the Chrome Native Messaging host after build.
                                If id is omitted, the installer tries auto-discovery.
  --extension-id <id>           Chrome extension ID for --install-native-host.
  --clean                       Run swift package clean before building.
  --run                         Run SwiftGetX after build/test/package steps complete.
  -h, --help                    Show this help.

Examples:
  Scripts/local-build.sh
  Scripts/local-build.sh --release --skip-tests
  Scripts/local-build.sh --native-libtorrent
  Scripts/local-build.sh --release --dmg
  Scripts/local-build.sh --install-native-host abcdefghijklmnopabcdefghijklmnop

Native libtorrent builds require Homebrew dependencies:
  brew install cmake boost openssl

If Homebrew is installed outside /opt/homebrew, set:
  SWIFTGETX_HOMEBREW_PREFIX=/usr/local Scripts/local-build.sh --native-libtorrent
EOF
}

log() {
  printf '\n==> %s\n' "$*"
}

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 127
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      CONFIGURATION="debug"
      shift
      ;;
    --release)
      CONFIGURATION="release"
      shift
      ;;
    --native-libtorrent)
      ENABLE_NATIVE_LIBTORRENT=1
      shift
      ;;
    --skip-tests)
      RUN_TESTS=0
      shift
      ;;
    --package)
      PACKAGE_APP=1
      shift
      ;;
    --dmg)
      PACKAGE_APP=1
      CREATE_DMG=1
      shift
      ;;
    --install-native-host)
      INSTALL_NATIVE_HOST=1
      shift
      if [[ $# -gt 0 && "$1" != --* ]]; then
        CHROME_EXTENSION_ID="$1"
        shift
      fi
      ;;
    --install-native-host=*)
      INSTALL_NATIVE_HOST=1
      CHROME_EXTENSION_ID="${1#*=}"
      shift
      ;;
    --extension-id)
      shift
      if [[ $# -eq 0 ]]; then
        printf '--extension-id requires a Chrome extension ID.\n' >&2
        exit 64
      fi
      CHROME_EXTENSION_ID="$1"
      shift
      ;;
    --extension-id=*)
      CHROME_EXTENSION_ID="${1#*=}"
      shift
      ;;
    --clean)
      CLEAN_BUILD=1
      shift
      ;;
    --run)
      RUN_APP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

cd "$ROOT_DIR"
need_command swift

if [[ "$ENABLE_NATIVE_LIBTORRENT" == "1" ]]; then
  unset SWIFTGETX_DISABLE_LIBTORRENT
  export SWIFTGETX_ENABLE_LIBTORRENT=1
else
  unset SWIFTGETX_ENABLE_LIBTORRENT
  export SWIFTGETX_DISABLE_LIBTORRENT=1
fi

log "SwiftGetX local build"
printf 'Configuration: %s\n' "$CONFIGURATION"
if [[ "$ENABLE_NATIVE_LIBTORRENT" == "1" ]]; then
  printf 'Torrent engine: native libtorrent\n'
else
  printf 'Torrent engine: lightweight fallback\n'
fi

if [[ "$CLEAN_BUILD" == "1" ]]; then
  log "Cleaning SwiftPM build artifacts"
  run swift package clean
fi

if [[ "$ENABLE_NATIVE_LIBTORRENT" == "1" ]]; then
  log "Building native libtorrent bridge"
  run Scripts/build-libtorrent.sh
fi

BUILD_ARGS=(swift build)
SHOW_BIN_ARGS=(swift build --show-bin-path)
TEST_ARGS=(swift test)
if [[ "$CONFIGURATION" == "release" ]]; then
  BUILD_ARGS+=(--configuration release)
  SHOW_BIN_ARGS=(swift build --configuration release --show-bin-path)
  TEST_ARGS+=(--configuration release)
fi

log "Building Swift package"
run "${BUILD_ARGS[@]}"
BUILD_BIN_PATH="$("${SHOW_BIN_ARGS[@]}")"
printf 'Build products: %s\n' "$BUILD_BIN_PATH"

if [[ "$RUN_TESTS" == "1" ]]; then
  log "Running tests"
  run "${TEST_ARGS[@]}"
fi

if [[ "$PACKAGE_APP" == "1" ]]; then
  PACKAGE_ARGS=(Scripts/package-dmg.sh "$CONFIGURATION" dist)
  if [[ "$CREATE_DMG" == "1" ]]; then
    PACKAGE_ARGS+=(--dmg)
  fi

  log "Packaging app bundle"
  run "${PACKAGE_ARGS[@]}"
fi

if [[ "$INSTALL_NATIVE_HOST" == "1" ]]; then
  HOST_BINARY="$BUILD_BIN_PATH/SwiftGetXNativeHost"
  INSTALL_ARGS=(Scripts/install-native-host.sh "$HOST_BINARY")
  if [[ -n "$CHROME_EXTENSION_ID" ]]; then
    INSTALL_ARGS+=("$CHROME_EXTENSION_ID")
  fi

  log "Installing Chrome Native Messaging host"
  run "${INSTALL_ARGS[@]}"
fi

if [[ "$RUN_APP" == "1" ]]; then
  APP_BINARY="$BUILD_BIN_PATH/SwiftGetX"
  log "Running SwiftGetX"
  run "$APP_BINARY"
fi

log "Done"
