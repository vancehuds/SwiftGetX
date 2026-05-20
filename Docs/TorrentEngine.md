# Torrent Engine Boundary

`TorrentDownloadEngine` is wired into the same coordinator and UI as HTTP tasks. The libtorrent binding is isolated behind `TorrentEngineAdapter`; default SwiftPM builds use the lightweight placeholder fallback, and `SWIFTGETX_ENABLE_LIBTORRENT=1` enables the native adapter after the static library is built.

## Native Build

The upstream libtorrent source is fetched into `Vendor/libtorrent` from `arvidn/libtorrent` and pinned in `Vendor/libtorrent.version`.

The C wrapper surface lives in `Sources/CSwiftGetXLibtorrent`. Build libtorrent and the wrapper with:

```sh
brew install cmake boost openssl
Scripts/build-libtorrent.sh
```

Then build the app with native libtorrent enabled:

```sh
SWIFTGETX_ENABLE_LIBTORRENT=1 swift build
SWIFTGETX_ENABLE_LIBTORRENT=1 swift test
```

With `SWIFTGETX_ENABLE_LIBTORRENT=1`, `Package.swift` compiles `Sources/CSwiftGetXLibtorrent/src/CSwiftGetXLibtorrent.cpp`, links the CMake-built `libtorrent-rasterbar.a`, and makes `canImport(CSwiftGetXLibtorrent)` true for `Sources/SwiftGetX/Services/LibtorrentAdapter.swift`.

## Adapter Contract

```swift
protocol TorrentEngineAdapter: Sendable {
    func start(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws
    func pause(id: UUID) async
    func cancel(id: UUID) async
    func remove(id: UUID, deletingFiles: Bool) async
    func recheck(id: UUID) async
    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async
    func setFileSelection(id: UUID, selectedFileIndexes: [Int]) async
}
```

The adapter should translate libtorrent state into `DownloadSnapshot` so SwiftUI and SwiftData remain independent from libtorrent-specific types.

## Current Native Capabilities

- Magnet and `.torrent` input.
- DHT, PEX, tracker updates.
- Metadata acquisition and file list reporting.
- Selected-file priorities.
- Recheck and completion verification.
- Download/upload speed limits.
- Pause/resume without adding duplicate handles.
- Stop seeding when the configured ratio is reached.

## Remaining Torrent Hardening

- Persist libtorrent resume data for faster process-restart recovery.
- Add real-world magnet and `.torrent` integration tests with controlled fixtures.
- Package OpenSSL/libtorrent artifacts in a signed, deployment-target-aligned app bundle.
