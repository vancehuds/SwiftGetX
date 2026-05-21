#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="debug"
RUN_TESTS=1
ENABLE_NATIVE_LIBTORRENT=0
PACKAGE_APP=0
CREATE_DMG=0
PACKAGE_CHROME=0
INSTALL_NATIVE_HOST=0
CHROME_EXTENSION_ID=""
CLEAN_BUILD=0
RUN_APP=0
INSTALL_DEPS=0

usage() {
  cat <<'EOF'
Usage/用法: Scripts/local-build.sh [options/选项]

Build and test SwiftGetX locally with one command.
一键在本地编译并测试 SwiftGetX。

Options/选项:
  --debug                       Build the debug configuration. This is the default.
                                编译 Debug 配置（默认）。
  --release                     Build the release configuration.
                                编译 Release 配置。
  --native-libtorrent           Build and enable the optional native libtorrent engine.
                                编译并启用可选的 native libtorrent 引擎。
  --skip-tests                  Build only; do not run swift test.
                                仅编译，跳过 swift 单元测试。
  --package                     Assemble dist/SwiftGetX.app and dist/chrome/*.crx/*.zip.
                                组装 dist/SwiftGetX.app 与 dist/chrome/*.crx/*.zip 扩展。
  --dmg                         Assemble dist/SwiftGetX.app, dist/SwiftGetX.dmg and Chrome extension.
                                组装 macOS 应用、生成 .dmg 镜像并打包 Chrome 扩展。
  --chrome, --chrome-extension  Package only the Chrome extension under dist/chrome.
                                仅打包 Chrome 扩展至 dist/chrome 目录。
  --install-native-host [id]    Install the Chrome Native Messaging host after build.
                                If id is omitted, the installer tries auto-discovery.
                                编译后安装 Chrome 原生消息宿主。若未指定扩展 ID 则尝试自动发现。
  --extension-id <id>           Chrome extension ID for --install-native-host.
                                用于 --install-native-host 的 Chrome 扩展 ID。
  --install-deps                Install Homebrew packaging dependencies (cmake boost openssl).
                                自动安装 Homebrew 编译与打包依赖（cmake boost openssl）。
  --clean                       Run swift package clean before building.
                                编译前清理 SwiftPM 缓存。
  --run                         Run SwiftGetX after build/test/package steps complete.
                                编译/测试/打包完成后运行 SwiftGetX。
  -h, --help                    Show this help message.
                                显示此帮助信息。

Examples/示例:
  Scripts/local-build.sh
  Scripts/local-build.sh --release --skip-tests
  Scripts/local-build.sh --native-libtorrent
  Scripts/local-build.sh --release --dmg
  Scripts/local-build.sh --install-deps
  Scripts/local-build.sh --install-native-host abcdefghijklmnopabcdefghijklmnop

Native libtorrent builds require Homebrew dependencies/使用 native libtorrent 需安装以下 Homebrew 依赖:
  brew install cmake boost openssl

If Homebrew is installed outside /opt/homebrew, set/若 Homebrew 安装在非默认目录，请设置 SWIFTGETX_HOMEBREW_PREFIX:
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
      PACKAGE_CHROME=1
      shift
      ;;
    --dmg)
      PACKAGE_APP=1
      CREATE_DMG=1
      PACKAGE_CHROME=1
      shift
      ;;
    --chrome|--chrome-extension)
      PACKAGE_CHROME=1
      shift
      ;;
    --install-deps)
      INSTALL_DEPS=1
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

if [[ "$INSTALL_DEPS" == "1" ]]; then
  need_command brew
  log "Installing/checking Homebrew dependencies"
  for formula in cmake boost openssl; do
    brew list "$formula" &>/dev/null || brew list "${formula}@3" &>/dev/null || brew install "$formula"
  done
fi

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

if [[ "$PACKAGE_CHROME" == "1" ]]; then
  need_command node
  need_command zip
  log "Packaging Chrome extension"
  run Scripts/package-chrome-extension.sh Sources/SwiftGetX/Resources/ChromeExtension dist/chrome
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

log "Completed successfully! Artifacts built:"
if [[ "$PACKAGE_APP" == "1" ]]; then
  printf '  - App Bundle: dist/SwiftGetX.app\n'
fi
if [[ "$CREATE_DMG" == "1" ]]; then
  printf '  - DMG Archive: dist/SwiftGetX.dmg\n'
fi
if [[ "$PACKAGE_CHROME" == "1" ]]; then
  printf '  - Chrome Extension (.crx): dist/chrome/SwiftGetX-Chrome.crx\n'
  printf '  - Chrome Extension (.zip): dist/chrome/SwiftGetX-Chrome.zip\n'
fi

log "Done"
