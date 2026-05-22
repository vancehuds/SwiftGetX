# SwiftGetX Plan Completion

## Completed In This Repository

- macOS 14+ SwiftUI app scaffold with liquid glass three-pane UI.
- SwiftData task model, settings persistence, queue coordination, filters, search, notifications, menu bar actions, and clipboard link suggestions.
- HTTP/HTTPS engine with metadata probing, `.part` files, Range resume, multi-segment downloads, real-time aggregate progress, retry, speed limiting, duplicate-file protection, pause/resume, remove, and recheck.
- BT task model surface with file-list persistence, connection summary display, interactive selected-file state, SwiftTorrent runtime support, and a replaceable `TorrentEngineAdapter`.
- Fetchable `arvidn/libtorrent` v2.0.12 source at `Vendor/libtorrent`, pinned in `Vendor/libtorrent.version`.
- `CSwiftGetXLibtorrent` C wrapper and CMake build project for libtorrent integration.
- Native `LibtorrentAdapter` isolated behind `canImport(CSwiftGetXLibtorrent)` and enabled with `SWIFTGETX_ENABLE_LIBTORRENT=1` as an optional development/reference path. Default builds and releases use SwiftTorrent and do not require libtorrent, Boost, OpenSSL, CMake, or Homebrew.
- Chrome and Safari Web Extension resources for explicit handoff, popup scanning, native-host diagnostics, and browser download takeover.
- `SwiftGetXNativeHost` executable for Chrome Native Messaging that opens `swiftgetx://download?url=...`.
- URL scheme Info.plist template, Native Messaging install script, and DMG/signing/notarization packaging checklist.
- Unit and integration tests, including a local HTTP Range server that validates segmented download output.

## External Inputs Still Required

- Apple Developer ID certificate and notarytool credentials for signing and notarization.
- Xcode app/extension targets for production Safari Web Extension packaging.
- Chrome Web Store credentials if automated store upload is added later. Release packaging already requires a fixed `CHROME_EXTENSION_ID` and fails when the CRX key computes a different ID.
- Deployment-target-aligned OpenSSL/libtorrent packaging only if a future release explicitly opts back into the optional native reference adapter.

## Verification

```sh
swift build
swift test
# Optional reference adapter only:
Scripts/build-libtorrent.sh
SWIFTGETX_ENABLE_LIBTORRENT=1 swift build
SWIFTGETX_ENABLE_LIBTORRENT=1 swift test
```

Current test coverage includes source parsing, native messaging framing, file-name collision handling, segment planning/progress, SwiftTorrent parser/protocol/runtime fixtures, BT file-list persistence, and segmented HTTP download correctness. The optional native libtorrent build path compiles and links on this machine; Homebrew OpenSSL currently emits macOS deployment target warnings during debug builds.
