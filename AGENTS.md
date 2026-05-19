# Repository Guidelines

## Project Structure & Module Organization

SwiftGetX is a Swift Package for macOS 14+. Main app code lives in `Sources/SwiftGetX`, split into `Models`, `Services`, `UI`, `Utilities`, and bundled `Resources` for Safari, Chrome, and Native Messaging integration. Shared non-UI types live in `Sources/SwiftGetXCore`; the browser handoff executable is `Sources/SwiftGetXNativeHost`. Optional native torrent bindings live in `Sources/CSwiftGetXLibtorrent`, with CMake support under `Native/CSwiftGetXLibtorrent` and vendored libtorrent under `Vendor/libtorrent`. Tests are in `Tests/SwiftGetXTests`; design notes are in `Docs`.

## Build, Test, and Development Commands

- `swift build`: build default SwiftPM targets without native libtorrent.
- `swift test`: run the Swift Testing suite.
- `Scripts/install-native-host.sh .build/arm64-apple-macosx/debug/SwiftGetXNativeHost <chrome-extension-id>`: install the Chrome Native Messaging host.
- `brew install cmake boost openssl`: install native torrent prerequisites.
- `git -C Vendor/libtorrent submodule update --init deps/try_signal deps/asio-gnutls`: initialize required libtorrent submodules.
- `Scripts/build-libtorrent.sh`: build the optional native C++ bridge.
- `SWIFTGETX_ENABLE_LIBTORRENT=1 swift build` / `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test`: build and test with native libtorrent.

## Coding Style & Naming Conventions

Use idiomatic Swift with 4-space indentation, explicit access control where useful, and `@MainActor` for UI/model coordination that touches SwiftData or observable state. Keep type names in `UpperCamelCase`, properties and methods in `lowerCamelCase`, and test methods as readable behavior phrases such as `downloadsSegmentedContent`. Preserve current boundaries: UI in `UI`, orchestration in `Services`, persistence in `Models`, and shared message code in `SwiftGetXCore`. No SwiftFormat or SwiftLint config is present; match nearby files.

## Testing Guidelines

Tests use the `Testing` framework with `@Suite`, `@Test`, and `#expect`. Add tests under `Tests/SwiftGetXTests`, naming files after the unit or behavior, for example `SourceParserTests.swift` or `SegmentPlanTests.swift`. Prefer temporary directories and local test servers over external network dependencies. Run `swift test` before submitting; run the `SWIFTGETX_ENABLE_LIBTORRENT=1` variant when touching torrent adapter or C wrapper code.

## Commit & Pull Request Guidelines

This repository has no committed history yet, so no project-specific convention is established. Use concise imperative subjects, for example `Add native host install docs`, and keep unrelated work in separate commits. Pull requests should summarize the user-visible change, list test commands run, link issues or docs, and include screenshots or recordings for UI changes. Note any libtorrent, Homebrew, signing, or Native Messaging setup requirements.

## Security & Configuration Tips

Do not commit local build products from `.build`, `DerivedData`, or `dist`. Keep browser extension IDs, signing identities, notarization profiles, and local download paths out of source-controlled configuration.
