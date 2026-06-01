<p align="center">
  <a href="https://github.com/vancehuds/SwiftGetX">
    <img src="Sources/SwiftGetX/Resources/Assets/AppIcon.png" alt="SwiftGetX Logo" width="128" height="128">
  </a>
</p>

<h1 align="center">SwiftGetX</h1>

<p align="center">
  <strong>Lightweight, Premium Native macOS Multi-threaded & BitTorrent Download Manager</strong>
</p>

<p align="center">
  <strong>English</strong> | <a href="README.md">简体中文</a>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-0066b2.svg?style=flat&logo=github" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-4ebd31.svg?style=flat&logo=apple" alt="Platform: macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.0-f05138.svg?style=flat&logo=swift" alt="Swift: 6.0">
  <img src="https://img.shields.io/badge/Xcode-15.0%2B-1572B6.svg?style=flat&logo=xcode" alt="Xcode: 15.0+">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/UI-SwiftUI-FF5A09.svg?style=flat&logo=swift" alt="UI: SwiftUI">
  <img src="https://img.shields.io/badge/Database-SwiftData-E34F26.svg?style=flat" alt="Database: SwiftData">
  <img src="https://img.shields.io/badge/Engine-HTTP%20%2F%20SwiftTorrent-darkviolet.svg?style=flat" alt="Engine: HTTP / SwiftTorrent">
  <img src="https://img.shields.io/badge/Extensions-Chrome%20%2F%20Safari-8A2BE2.svg?style=flat&logo=googlechrome" alt="Extensions: Chrome / Safari">
</p>



**SwiftGetX** is a lightweight, high-performance native download manager prototype designed for macOS 14+, built entirely using **SwiftUI**, **SwiftData**, and **Swift Package Manager**. It delivers a premium native macOS feel, frictionless browser takeover integration, and a highly pluggable BitTorrent engine abstraction.

---

## ✨ Features

### 🎨 Responsive Liquid Glass UI & Maintenance
*   **macOS Premium Aesthetics**: Sleek three-pane interface conforming to macOS human interface guidelines with full support for Light & Dark mode and polished micro-interactions.
*   **Polished Micro-Interactions**: Real-time inspector view, adjustable toolbar commands, user settings window, and a persistent Menu Bar status tray item.
*   **Dynamic Localization**: Full runtime language switching for System Default, English, and Simplified Chinese (`zh-Hans`). The interface updates instantly without requiring an app relaunch, powered by a customized `AppResources` asset manager for on-demand string and bundle discovery.
*   **Smart Clipboard Capture**: Monitors the clipboard for download links and presents them inside a gorgeous, interactive liquid-glass float banner.
*   **Sparkle Auto-Updates**: Seamless integration of the gold-standard [Sparkle](https://sparkle-project.org) framework. Supports automatic update checks on launch or manual check via menu items. Updates are cryptographically secured using EdDSA (Ed25519) signatures and published automatically through GitHub Actions.
*   **SwiftData Startup Recovery (`StartupRecovery`)**: When the SwiftData `ModelContainer` is corrupted or schema-incompatible at launch, the app quarantines the affected `.store` / `.store-shm` / `.store-wal` files and presents a readable recovery panel that lets users either rebuild the store or quit, avoiding silent data loss.

### ⚡ Segmented HTTP/HTTPS Engine
*   **Multi-Segment Parallelism**: Fast multi-threaded segmented downloads with robust HTTP Range-based chunk resume capability, with customizable per-task HTTP options.
*   **Response Metadata Capture**: Automatically detects and records HTTP response metadata (including ETag, Last-Modified, and Server headers), rendering professional diagnostics in the inspector.
*   **Checksum Verification**: First-class SHA-256 / SHA-1 / MD5 validation powered by `CryptoKit`. Paste an expected digest when creating a task, and the inspector surfaces a dedicated status card so you can immediately see whether the file matches the source publisher.
*   **Scheduling & Resiliency**: Built-in robust download scheduler with global/queue concurrent task limits, automatic requeue on failure, and customizable retry limits.
*   **Safe Assembly**: Keeps incomplete downloads under a temporary `.part` structure, merging and renaming them instantly upon successful integrity check.

### 🧩 Zero-Configuration Browser Integration
*   **Chrome Takeover (Manifest V3)**: Built-in Chrome extension. When a supported HTTP, HTTPS, magnet, or `.torrent` download is triggered in Chrome, the extension intercept-transports it via Native Messaging to SwiftGetX, cancelling the Chrome item after SwiftGetX accepts. If IPC fails, Chrome resumes the original download instantly.
*   **Multi-Chromium Discovery**: Main App automatically scans local directory trees on startup or focus, auto-detecting extension installations in Chrome, Chrome Canary, Edge, Brave, Vivaldi, Arc, Chromium, and Atlas. Generates or repairs Native Messaging manifests (`com.swiftgetx.native.json`) instantly with zero manual ID copy-pasting.
*   **Rich Handoff Context**: Securely passes download origins (source page URL, page title, and proposed filename) via deep links (`swiftgetx://download` and `swiftgetx://browser-setup`) with an integrated diagnostic status panel.
*   **Browser Download Recovery Policy (`BrowserDownloadRecoveryPolicy`)**: Every browser-originated request is evaluated by a single recovery policy. Requests that require runtime credentials (Cookies, `Authorization`) or replay a non-simple HTTP method with a body are rejected with an explicit reason code, telling the extension to fall back to the browser's native downloader so SwiftGetX never mishandles authenticated or stateful requests.
*   **Native Messaging Bridge (`BrowserBridge`)**: A unified bridge layer on top of `SwiftGetXCore` abstracts Chrome and Safari entry points and ack formats. Adding new protocol fields only requires updating the bridge; `DownloadCoordinator` and the UI stay source-agnostic.
*   **Safari Feature-Parity Extension**: Bundled Safari Web Extension assets cover context menus, popup sends, selection sends, page download-link scanning, connection diagnostics, and the download takeover toggle. Signed distribution still requires an Xcode Safari App Extension target and Apple Developer signing.

### 🧬 Dual-Engine BitTorrent Architecture
*   **Decoupled Design**: Features a generic `TorrentEngineAdapter` protocol, isolating BT implementation details completely from SwiftData models and SwiftUI views.
*   **Swift-Native Torrent Module**: A built-in, lightweight pure-Swift BT/DHT engine. Implements custom KRPC UDP search lookup, routing tables, Local Service Discovery (LSD), and Peer Exchange (PEX). Features zero C++ dependencies and compiles instantly.
*   **Pure Swift Protocol Stack**: Custom-built Peer Wire Protocol binary framing engine (enforces maximum length limits to prevent buffer overflow attacks) with full BEP 9 / BEP 10 Magnet Extension support to query metadata directly from peers. Features integrated pure-Swift HTTP/UDP Tracker announcers.
*   **Optional Reference BT Engine (libtorrent)**: Vendors a pinned source of `arvidn/libtorrent` v2.0.12 via a static `CSwiftGetXLibtorrent` C++ bridge. The default release and daily development path use SwiftTorrent; setting `SWIFTGETX_ENABLE_LIBTORRENT=1` enables the optional libtorrent reference adapter.
*   **Magnet Preview & File Selection UI (`TorrentMetadataService` + `TorrentUXSupport`)**: Pasting a magnet link triggers an async metadata fetch that surfaces candidate files, trackers, web seeds, and exact length before the task is added. Users can pick or deselect individual files in the new-task sheet, matching the UX of mature BT clients. Timeouts gracefully fall back to a partial preview (display name, size hints, tracker list) so the task still enters background resolution.
*   **Fine-Grained Runtime Control**: Toggle DHT, PEX, and LSD options individually with custom DHT bootstrap routers. Supports real-time upload/download speed limits, sequential download prioritization, concurrent connection and upload slot limits, and seeding ratio enforcement.
*   **Deep Health Snapshot & Diagnostics**: Displays metadata fetching progress, complete Peer lists (up to 100 peers monitored in real time), interactive Tracker tables (add, remove, or force reannounce), DHT routing metrics, and resume-data dirty state tracking. The BT inspector additionally exposes upload speed, share ratio, and seeding time cards that go beyond the generic download metrics.

---

## 📐 Architecture & Repository Layout

SwiftGetX is engineered with explicit unidirectional dependencies and clear module boundaries:

```mermaid
graph TD
    classDef main fill:#E3F2FD,stroke:#1565C0,stroke-width:2px;
    classDef browser fill:#F1F8E9,stroke:#558B2F,stroke-width:2px;
    classDef core fill:#EDE7F6,stroke:#651FFF,stroke-width:2px;
    classDef engine fill:#FFF3E0,stroke:#FF8F00,stroke-width:2px;
    
    Chrome["Chromium Extension (Manifest V3)"]:::browser
    Safari["Safari Web Extension"]:::browser
    NativeHost["SwiftGetXNativeHost (Lightweight C Bridge)"]:::browser
    MainApp["SwiftGetX Main App (SwiftUI View)"]:::main
    Models["SwiftData Persistent Models"]:::main
    StartupRecovery["StartupRecovery (SwiftData Quarantine)"]:::main
    Coordinator["Services & Coordinator Layer"]:::main
    BrowserBridge["BrowserBridge / BrowserDownloadRecoveryPolicy"]:::main
    Adapter["DownloadEngineAdapter Interface"]:::core
    HTTPEngine["HTTPDownloadEngine (Multi-segmented)"]:::engine
    TorrentAdapter["TorrentEngineAdapter BT Interface"]:::core
    SwiftTorrent["SwiftGetXTorrentCore + SwiftTorrentEngineAdapter"]:::engine
    LibtorrentWrapper["CSwiftGetXLibtorrent (C++ Wrapper)"]:::engine
    Libtorrent["arvidn/libtorrent Pinned Core"]:::engine

    Chrome <-->|"Native Messaging"| NativeHost
    Safari <-->|"Native Messaging / Deep Link"| MainApp
    NativeHost -->|"Deep Link Scheme Dispatch"| MainApp
    MainApp --> Models
    MainApp --> StartupRecovery
    MainApp --> Coordinator
    MainApp --> BrowserBridge
    Coordinator --> Adapter
    Adapter --> HTTPEngine
    Adapter --> TorrentAdapter
    TorrentAdapter -->|"Default SwiftTorrent"| SwiftTorrent
    TorrentAdapter -->|"SWIFTGETX_ENABLE_LIBTORRENT=1"| LibtorrentWrapper
    LibtorrentWrapper --> Libtorrent
```

> 📦 **Library Product**: `Sources/SwiftGetXTorrentCore` is exposed as a standalone `SwiftGetXTorrentCore` library product, letting third-party Swift projects consume the pure-Swift BT protocol stack without pulling in any UI code.

### 📂 Directory Structure

*   `Sources/SwiftGetX/`: Primary macOS application source code, split into:
    *   `Models/` — SwiftData models and persistence configuration (download tasks, rules, settings, checksum entities, etc.).
    *   `Services/` — Orchestration layer, including `DownloadCoordinator`, the multi-segment `HTTPDownloadEngine`, the BT `TorrentDownloadEngine`, `StartupRecovery`, `PersistenceArchive`, `SupportDiagnostics`, and more.
    *   `Services/Browser/` — Browser integration sub-modules: Chrome/Safari extension discovery, `ChromeNativeHostRegistrar`, the `BrowserBridge` bridge layer, the `BrowserDownloadRecoveryPolicy` recovery policy, and Deep Link policies.
    *   `UI/` — SwiftUI view layer (`ContentView`, `TaskListView`, `InspectorView`, `NewTaskSheet`, `SettingsView`, `SidebarView`, `StartupRecoveryView`, etc.), with `UI/Design/` housing the liquid-glass and responsive layout primitives.
    *   `Utilities/` — Cross-cutting helpers plus feature tools such as `TorrentUXSupport`.
    *   `Resources/` — Icons, Chrome / Safari Web Extension bundles, localized `en.lproj` / `zh-Hans.lproj`, `AppInfo.plist`, and `Acknowledgements.md`.
*   `Sources/SwiftGetXCore/`: Shared protocol layer. Contains deep link encoders, IPC frames, and messaging protocols.
*   `Sources/SwiftGetXNativeHost/`: Ultra-light C bridge that reads stdin/stdout from browsers and dispatches deep-link URLs.
*   `Sources/SwiftGetXTorrentCore/`: Pure-Swift BT protocol stack and DHT/Tracker client, shipped as the standalone `SwiftGetXTorrentCore` library product.
*   `Sources/CSwiftGetXLibtorrent/`: C++ bridge wrapper exposing libtorrent functions via C-compatible symbols to Swift. Compiled only when `SWIFTGETX_ENABLE_LIBTORRENT=1` is set.
*   `Native/CSwiftGetXLibtorrent/`: CMake build workspace for compiling the static libtorrent, OpenSSL, and Boost dependencies.
*   `Vendor/libtorrent/`: Git submodule targeting upstream `arvidn/libtorrent`.
*   `Tests/SwiftGetXTests/`: Comprehensive test suite, including a local HTTP Range mock server, persistence archive fixtures, and startup-recovery containers.
*   `Scripts/`: Helper automation scripts, including:
    *   `local-build.sh` — one-command local build / test / package entrypoint;
    *   `package-dmg.sh` — App / DMG packager and Ad-hoc signer;
    *   `package-chrome-extension.sh` — Chrome extension packager;
    *   `validate-release.sh` — pre-release environment, App, DMG, and Sparkle appcast safety checks;
    *   `generate-appcast.sh` — generates `appcast.xml` from the produced DMG using the Sparkle EdDSA private key;
    *   `build-libtorrent.sh` / `install-native-host.sh` / `find-chrome-extension-id.mjs` / `make-crx.mjs` — libtorrent build, Native Host installer, and extension packaging helpers.

---

## 📦 Zero-Threshold Installation & Usage (Out-of-the-Box - Download from Release)

If you prefer to run pre-built binaries directly without compiling from source, download the pre-packaged assets from the **Releases** page:

### Step 1: Install the Main Application
1. Head over to the repository's [Releases](https://github.com/vancehuds/SwiftGetX/releases) page and download the latest `SwiftGetX.dmg`.
2. Double-click the downloaded `.dmg` file to mount it, and drag **SwiftGetX** into your **Applications** directory.
3. **First-Time Launch Warning**:
   * When Developer ID release secrets are configured, the official tag release workflow performs signing, notarization, and stapling validation. If no paid Apple Developer account is available, or if you install a local build or fork artifact, macOS may still block launch on double-click, displaying: *"Cannot be opened because Apple cannot check it for malicious software"* or *"Unverified Developer"*.
   * **Solution**: Open macOS **System Settings -> Privacy & Security**. Scroll to the bottom to find the "Security" section, click **"Open Anyway"**, and enter your Mac passcode to authorize execution.

### Step 2: Install and Bind the Chrome Browser Extension
1. Download the corresponding `SwiftGetX-Chrome.zip` from the Releases page.
2. Extract the `.zip` archive to a permanent directory of your choice that you **won't delete or move** (such as your `Documents` or a dedicated app support folder).
3. Open Google Chrome, navigate to `chrome://extensions` in the URL bar, and press Enter.
4. Enable the **"Developer Mode"** toggle in the top-right corner.
5. Click the **"Load Unpacked"** button in the top-left corner, and select the folder you just extracted.
6. **Activate Automatic Binding**: Launch and focus the SwiftGetX main application once. Upon startup, the app automatically scans your local Chrome extension directory, verifies the SwiftGetX extension ID, and writes the background Native Messaging host manifest config file automatically.
7. **Start Using**: You are good to go! Right-click any downloadable link in Chrome and choose `Download with SwiftGetX`, or trigger a regular download. The extension will intercept the request and hand it over to SwiftGetX for lightning-fast multi-segment downloads.

---

## 🛠️ Requirements

*   **Operating System**: macOS 14 (Sonoma) or newer.
*   **Toolchain**: Swift 6.0 Compiler / Xcode 15+.
*   **Optional libtorrent reference dependencies** (not needed for normal builds or releases; only needed with `SWIFTGETX_ENABLE_LIBTORRENT=1`):
    ```sh
    brew install cmake boost openssl
    ```

---

## 🚀 Quick Start (For Developers compiling from Source)

### One-command Local Build and Test
The repository includes a local development entrypoint. By default, it builds and tests the pure SwiftTorrent path without Homebrew, CMake, Boost, OpenSSL, or libtorrent:

```sh
Scripts/local-build.sh
```

Common options:

```sh
# Build only, without tests
Scripts/local-build.sh --skip-tests

# Release build
Scripts/local-build.sh --release

# Clean SwiftPM caches before building
Scripts/local-build.sh --clean

# Install optional native libtorrent reference dependencies (cmake, boost, openssl)
Scripts/local-build.sh --install-deps

# Build and test with optional Native libtorrent enabled
Scripts/local-build.sh --native-libtorrent

# Assemble SwiftGetX.app, SwiftGetX.dmg and automatically package the Chrome Extension
Scripts/local-build.sh --release --dmg

# Package only the Chrome extension under dist/chrome/*.crx and *.zip
Scripts/local-build.sh --chrome

# Install the Chrome Native Messaging host after build (with automatic extension discovery)
Scripts/local-build.sh --install-native-host <your-extension-id>

# Build, test, package, and then launch SwiftGetX
Scripts/local-build.sh --run
```

### 1. Default Compilation (SwiftTorrent)
To build and test the codebase instantly without external C++ dependencies:

```sh
# 1. Compile the app and Native Messaging bridge
swift build

# 2. Run the main SwiftGetX app
swift run SwiftGetX

# 3. Execute the Swift Testing suite
swift test
```

### 2. Optional Native libtorrent Reference Build
To compile the optional C++ libtorrent static bridge:

```sh
# 1. Pull libtorrent's required submodules
git -C Vendor/libtorrent submodule update --init deps/try_signal deps/asio-gnutls

# 2. Compile static libtorrent binary using OpenSSL & Boost
Scripts/build-libtorrent.sh

# 3. Build the app with the libtorrent feature flag enabled
SWIFTGETX_ENABLE_LIBTORRENT=1 swift build

# 4. Run optional native BT integration tests
SWIFTGETX_ENABLE_LIBTORRENT=1 swift test
```
> [!TIP]
> If your Homebrew binaries are installed in a non-standard location (such as `/usr/local` on Intel Mac), specify your prefix during compilation:
> `SWIFTGETX_HOMEBREW_PREFIX=/usr/local SWIFTGETX_ENABLE_LIBTORRENT=1 swift build`

---

## 🔌 Browser Integration & Handoff Setup

SwiftGetX is built with a smart auto-discovery framework that configures Chrome Native Messaging automatically.

### Chrome / Chromium Setup
1.  **Load the Extension**: Open Chrome, go to `chrome://extensions`, toggle **Developer Mode** on. Click **Load Unpacked**, and select the folder:
    `Sources/SwiftGetX/Resources/ChromeExtension`
2.  **Launch SwiftGetX**: Start or focus the SwiftGetX App. The app automatically scans supported Chromium profiles (Chrome, Chrome Canary, Edge, Brave, Vivaldi, Arc, Chromium, and Atlas), extracts the unpacked extension ID, and writes a correctly configured `NativeMessagingHosts/com.swiftgetx.native.json` manifest for the matching browser.
3.  **Takeover Downloads**: Right-click any downloadable link in Chrome and click `Download with SwiftGetX`, or trigger a regular download. The extension will automatically capture it and pipe it directly to SwiftGetX.

> [!NOTE]
> **Manual Installation**: You can manually install the manifest for development using:
> ```sh
> Scripts/install-native-host.sh .build/arm64-apple-macosx/debug/SwiftGetXNativeHost <extension-id>
> ```

### Safari Integration
*   Safari Extension assets are located at `Sources/SwiftGetX/Resources/SafariWebExtension`.
*   The Safari extension mirrors the Chrome extension: send the current page, links, media URLs, or selected text from context menus or the popup, scan pages for candidate download links, and take over Safari downloads when Native Messaging is available.
*   Explicit sends use Native Messaging first. If the native host is unavailable, the extension falls back to a validated `swiftgetx://download` deep link so the user-initiated handoff still reaches SwiftGetX. Download takeover only cancels the browser item after SwiftGetX confirms acceptance.
*   For signed distribution, you must build and compile a Safari Web Extension target in Xcode, embedding the extension inside the signed macOS App bundle's `Contents/PlugIns` folder.

---

## 📦 Packaging & CI/CD Pipelines

### Local Packaging
Assemble a local ad-hoc signed `.app` or `.dmg` for debugging outside the terminal:

```sh
# Assemble SwiftGetX.app (Debug Mode)
Scripts/package-dmg.sh debug dist

# Compile and package a clean SwiftGetX.dmg (Release Mode, with icons and DMG layouts)
Scripts/package-dmg.sh release dist --dmg
```

### Pre-Release Safety Checks
`Scripts/validate-release.sh` is the single source of truth for pre-release safety checks. Run any subcommand locally or in CI:

```sh
Scripts/validate-release.sh environment  # Verify Apple / Sparkle / Chrome extension secrets and SUFeedURL
Scripts/validate-release.sh sparkle      # Verify the Sparkle public key embedded in AppInfo.plist
Scripts/validate-release.sh app dist/SwiftGetX.app    # Verify .app signature, Sparkle.framework, and Native Host
Scripts/validate-release.sh dmg dist/SwiftGetX.dmg    # Verify DMG signature / notarization / stapling
Scripts/validate-release.sh appcast dist/appcast/appcast.xml  # Validate the Sparkle appcast fields
```

### GitHub Actions Workflows
Two automated workflows are supplied in `.github/workflows/`:
*   `build.yml`: Runs `Scripts/validate-release.sh sparkle` on every push or pull request, executes `swift test`, packages `dist/SwiftX.dmg` and `dist/chrome/*`, then uploads them as workflow artifacts.
*   `release.yml`: Triggered when a version tag (`v*`) is pushed. It runs `validate-release.sh environment` → unit tests → Developer ID certificate import (only when Apple secrets are configured) → `package-dmg.sh` → `validate-release.sh app/dmg` → Chrome extension packaging → `generate-appcast.sh` → appcast validation → publishing to the `gh-pages` branch and creating a GitHub Release via `softprops/action-gh-release`. When no Apple Developer secrets are configured, the workflow emits a `::warning` and falls back to an Ad-hoc signed build, keeping the release path accessible to open-source contributors without a paid Apple Developer account.

---

## 🧪 Testing

We use Apple's modern **Swift Testing** framework (`@Suite`, `@Test`, and `#expect`):

*   **Coverage**: color-scheme adapters, clipboard link filtering, native messaging framing, multi-segment planners, file-name collision resolution, HTTP checksum verification, real-world HTTP range chunk downloads, SwiftData persistence archive and startup recovery, the BT protocol stack (Peer Wire, DHT, Tracker, extension protocol), magnet metadata preview, menu bar snapshots, extension discovery and native host registration, and the `validate-release.sh` release-validation script.
*   Commands: `swift test` (or `SWIFTGETX_ENABLE_LIBTORRENT=1 swift test` for the optional native BT adapter).

---

## ⚠️ Compliance & Sandbox Warnings

Before distributing your custom build of SwiftGetX, note these critical macOS platform guidelines:

1.  **Gatekeeper Codesigning & Notarization**:
    *   To prevent Gatekeeper warnings on other machines, sign the binaries using an active Apple Developer account's `Developer ID Application` certificate and notarize the output via `xcrun notarytool`. When `release.yml` detects the full set of `APPLE_DEVELOPER_ID_*` and `APPLE_NOTARY_*` secrets, it enables `SWIFTGETX_RELEASE_STRICT=1` and enforces `spctl --assess` and `xcrun stapler validate` checks.
    *   If you do not have a paid Apple Developer account, the repository also supports an **unsigned release path**: `release.yml` emits a `::warning` and produces an Ad-hoc signed app bundle with an unsigned, unnotarized DMG. `validate-release.sh` skips the strict signing checks when `SWIFTGETX_RELEASE_STRICT=0` while still verifying the Sparkle public key, `SUFeedURL`, and (when provided) the Chrome extension signing material, so you never ship a release whose appcast fails basic validation.
2.  **App Sandbox Restrictions**:
    *   Sandboxed apps are forbidden from launching arbitrary helper binaries (like `SwiftGetXNativeHost`) unless they share a matching App Group container, or operate in a privileged non-sandboxed environment.
3.  **Secret Management**:
    *   Do not commit private `.pem` files, the Sparkle EdDSA private key, or the Chrome extension `.pem` signing key to the Git repository. Run `Scripts/validate-release.sh environment` locally before pushing a tag to catch missing secrets early.

---

## 🤝 Contributing

We welcome all contributions, whether it is fixing micro-bugs, updating responsive UI widgets, or improving SwiftTorrent behavior:

1.  Keep indentation at **4 spaces** conforming to idiomatic Swift patterns.
2.  Annotate persistent models or views interacting with SwiftData or observable states with `@MainActor`.
3.  Ensure `swift test` passes locally before opening a pull request.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE). Feel free to use, modify, and distribute it!

---
*Copyright (c) 2026 Vance Hudson. Special thanks to all open-source community members testing and contributing to SwiftGetX.*
