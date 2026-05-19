# SwiftGetX Plan Completion

## Completed In This Repository

- macOS 14+ SwiftUI app scaffold with liquid glass three-pane UI.
- SwiftData task model, settings persistence, queue coordination, filters, search, notifications, menu bar actions, and clipboard link suggestions.
- HTTP/HTTPS engine with metadata probing, `.part` files, Range resume, multi-segment downloads, real-time aggregate progress, retry, speed limiting, duplicate-file protection, pause/resume, remove, and recheck.
- BT task model surface with file-list persistence, connection summary display, interactive selected-file state, and a replaceable `TorrentEngineAdapter`.
- Vendored `arvidn/libtorrent` v2.0.12 source at `Vendor/libtorrent`, pinned in `Vendor/libtorrent.version`.
- `CSwiftGetXLibtorrent` C wrapper and CMake build project for libtorrent integration.
- Conditional native `LibtorrentAdapter` isolated behind `canImport(CSwiftGetXLibtorrent)` and enabled with `SWIFTGETX_ENABLE_LIBTORRENT=1`.
- Safari and Chrome extension resource placeholders for explicit handoff.
- `SwiftGetXNativeHost` executable for Chrome Native Messaging that opens `swiftgetx://download?url=...`.
- URL scheme Info.plist template, Native Messaging install script, and DMG/signing/notarization packaging checklist.
- Unit and integration tests, including a local HTTP Range server that validates segmented download output.

## External Inputs Still Required

- Apple Developer ID certificate and notarytool credentials for signing and notarization.
- Xcode app/extension targets for production Safari Web Extension packaging.
- Final Chrome extension id for the Native Messaging host manifest.
- Deployment-target-aligned OpenSSL/libtorrent packaging for release builds.

## Verification

```sh
swift build
swift test
Scripts/build-libtorrent.sh
SWIFTGETX_ENABLE_LIBTORRENT=1 swift build
SWIFTGETX_ENABLE_LIBTORRENT=1 swift test
```

Current test coverage includes source parsing, native messaging framing, file-name collision handling, segment planning/progress, BT file-list persistence, and segmented HTTP download correctness. The native libtorrent build path compiles and links on this machine; Homebrew OpenSSL currently emits macOS deployment target warnings during debug builds.
