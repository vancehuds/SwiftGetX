# SwiftGetX

SwiftGetX is a native macOS 14+ download manager prototype with a liquid glass SwiftUI interface.

## Current scope

- SwiftUI macOS app scaffold.
- SwiftData-backed download task model.
- Unified `DownloadCoordinator` with HTTP and BT engine boundaries.
- HTTP direct download with metadata probing, `.part` files, Range resume, multi-segment downloads, real-time aggregate progress, pause/resume, retry, speed limiting, and duplicate-file protection.
- SwiftData-backed settings for default directory, concurrency, retries, speed limits, notifications, and clipboard detection.
- Clipboard link detection with an in-app liquid glass suggestion bar.
- libtorrent integration boundary with a placeholder fallback and optional native adapter.
- Vendored `arvidn/libtorrent` v2.0.12 source plus `CSwiftGetXLibtorrent` C wrapper.
- Interactive BT file-list UI and selected-file synchronization to the torrent adapter boundary.
- Liquid glass three-pane UI, new-task sheet, settings, notifications, and menu bar entry.
- Safari and Chrome extension resource placeholders for explicit "send to SwiftGetX" downloads.
- Native Messaging length-prefixed JSON protocol helpers.
- Separate `SwiftGetXNativeHost` executable for Chrome Native Messaging handoff via `swiftgetx://download`.

## Build

```sh
swift build
swift test
```

Chrome host setup during development:

```sh
Scripts/install-native-host.sh .build/arm64-apple-macosx/debug/SwiftGetXNativeHost <chrome-extension-id>
```

Optional libtorrent native build:

```sh
brew install cmake boost openssl
git -C Vendor/libtorrent submodule update --init deps/try_signal deps/asio-gnutls
Scripts/build-libtorrent.sh
SWIFTGETX_ENABLE_LIBTORRENT=1 swift build
SWIFTGETX_ENABLE_LIBTORRENT=1 swift test
```

## Notes

The default SwiftPM build keeps libtorrent optional so the app remains easy to build on a clean machine. Set `SWIFTGETX_ENABLE_LIBTORRENT=1` after running `Scripts/build-libtorrent.sh` to compile the app with the native adapter.

Homebrew's current OpenSSL bottle may emit deployment target linker warnings when building for macOS 14. The debug build still links successfully; production packaging should use deployment-target-aligned OpenSSL artifacts or vendor a signed framework.

The HTTP engine streams files through `URLSession.AsyncBytes`, uses Range requests when available, downloads supported large files in multiple segments, and falls back to a single stream when Range metadata is missing.

See `Docs/BrowserIntegration.md` and `Docs/TorrentEngine.md` for the next integration points.
See `Docs/PlanCompletion.md` for the implementation completion status and external inputs required for production packaging.
