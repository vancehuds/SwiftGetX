# 🤝 Contributing to SwiftGetX

First off, thank you for considering contributing to SwiftGetX! It is people like you who make the open-source community such an amazing place to learn, inspire, and create.

This guide outlines the development workflow, coding standards, and testing practices to ensure your contributions can be merged smoothly.

---

## 📂 Repository Boundaries

To maintain a clean and scalable codebase, please respect the established project boundaries:

*   **UI Layer** (`Sources/SwiftGetX/UI`): Pure SwiftUI views, responsive grids, menus, popovers, and liquid glass styles.
*   **Orchestration / Coordinator** (`Sources/SwiftGetX/Services`): Download coordinators, metadata controllers, clipboard suggestions, and system menus.
*   **Persistence & SwiftData Models** (`Sources/SwiftGetX/Models`): Core models for task schedules, browser origins, and download records. Keep these decoupled from visual frames.
*   **Browser & Native Bridge** (`Sources/SwiftGetXCore`, `Sources/SwiftGetXNativeHost`): IPC protocols, deep-link routing schemes, and Native Messaging message framing.
*   **BitTorrent Adapter** (`Sources/CSwiftGetXLibtorrent`, `Sources/SwiftGetX/Services/LibtorrentAdapter.swift`): Native C++ bridge and the adapter implementation.

---

## 🛠️ Local Development Setup

To compile SwiftGetX locally, ensure you have macOS 14+ and the Swift 6.0 Toolchain (Xcode 15+).

### 1. Minimal Development Mode (No Libtorrent Build)
By default, the project compiles using a lightweight, fast-compiling mock Torrent adapter, which works without external libraries:

```sh
swift build
swift test
```

### 2. Complete BitTorrent Integration
To develop or test features touching the native C++ torrent bridge:

1.  **Install Homebrew Dependencies**:
    ```sh
    brew install cmake boost openssl
    ```
2.  **Pull Libtorrent Submodules**:
    ```sh
    git -C Vendor/libtorrent submodule update --init deps/try_signal deps/asio-gnutls
    ```
3.  **Compile Static Libtorrent Library**:
    ```sh
    Scripts/build-libtorrent.sh
    ```
4.  **Build with Native Flag**:
    ```sh
    SWIFTGETX_ENABLE_LIBTORRENT=1 swift build
    SWIFTGETX_ENABLE_LIBTORRENT=1 swift test
    ```

---

## 🎨 Coding Style & Guidelines

We do not enforce strict linter checkers (like SwiftLint) in the repository, but we request that you match the local layout and patterns:

*   **Indentation**: Use 4-space indentation across all Swift, C++, JavaScript, and configuration files.
*   **Access Control**: Provide explicit access control (`private`, `internal`, `public`) where helpful to prevent API leakage.
*   **Strict Concurrency**: We target Swift 6 strict concurrency. Ensure classes involved in cross-actor message handling are marked `@Sendable` or isolated.
*   **Coordinating Threading**: Annotate all UI components, state controllers, and persistent database actors with `@MainActor` to avoid SwiftData state collisions.
*   **Naming Conventions**:
    *   Type names, structs, and protocols in `UpperCamelCase`.
    *   Variables, properties, functions, and parameters in `lowerCamelCase`.
    *   Test methods should be readable behavior phrases, e.g. `testSegmentedDownloadSuccessfullyAssemblesFile`.

---

## 🧪 Testing Guidelines

Every new feature or bug fix must be covered by appropriate unit or integration tests:

*   **Test Framework**: Use Swift's modern `Testing` framework with `@Suite`, `@Test`, and `#expect`.
*   **Location**: Place test files under `Tests/SwiftGetXTests` following the target file name, e.g. `DownloadEngineTests.swift` or `SegmentPlanTests.swift`.
*   **Isolation**: Prefer temporary directories (`FileManager.default.temporaryDirectory`) and mock HTTP/TCP servers rather than issuing actual outgoing external network requests.
*   **All-Test Verify**: Run the full suite before opening a PR:
    ```sh
    swift test
    SWIFTGETX_ENABLE_LIBTORRENT=1 swift test
    ```

---

## 🔒 Security & Privacy

*   **Never Commit Secrets**: Do not check in personal browser profiles, Apple developer signing identifiers, API keys, notarization profiles, or local download paths.
*   **Chrome Key Safety**: The Chrome Extension packing script automatically handles key generation if none is provided. Never commit a `.pem` private extension signing key.
*   **Excluded Directories**: Double check that your Git index ignores `.build/`, `DerivedData/`, and `dist/` outputs.

---

## 🚀 Pull Request Checklist

When submitting a Pull Request, please ensure the following details are documented:

1.  **Objective**: What problem does this change solve, and what is the technical approach?
2.  **Visual Proof (UI changes)**: Attach screenshots or screen recordings showing dark/light mode appearance.
3.  **Verification**: Document what testing command was run (e.g. `swift test`) and confirm they passed.
4.  **Dependencies**: Mention if the changes introduce a new Brew library, package, or CMake requirement.

---
Thank you for helping build the best native download engine for macOS!
