# Torrent Engine Boundary

`TorrentDownloadEngine` is wired into the same coordinator and UI as HTTP tasks. The default release and SwiftPM build path uses the pure SwiftTorrent engine. The libtorrent binding is isolated behind `TorrentEngineAdapter` and remains an optional development/reference path enabled only with `SWIFTGETX_ENABLE_LIBTORRENT=1` after the static library is built.

## Optional Native Reference Build

The upstream libtorrent source is fetched into `Vendor/libtorrent` from `arvidn/libtorrent` and pinned in `Vendor/libtorrent.version`.

The C wrapper surface lives in `Sources/CSwiftGetXLibtorrent`. This path is not required for normal users, ordinary CI builds, or release packaging. Build libtorrent and the wrapper only when you need the optional reference adapter:

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
    func setFilePriority(id: UUID, fileIndex: Int, priority: Int) async
    func setSequentialDownload(id: UUID, enabled: Bool) async
    func addTracker(id: UUID, url: String) async
    func removeTracker(id: UUID, url: String) async
    func forceReannounce(id: UUID) async
}
```

The adapter should translate libtorrent state into `DownloadSnapshot` so SwiftUI and SwiftData remain independent from libtorrent-specific types.

## Current SwiftTorrent Capabilities

- Magnet and `.torrent` input.
- DHT, PEX, LSD, and tracker updates, with DHT/PEX/LSD applied to each torrent as runtime flags.
- Metadata acquisition and file list reporting.
- Selected-file priorities, per-file priority changes, and sequential download toggles.
- Fast resume data save/load under Application Support.
- Tracker list reporting, tracker add/remove, and forced reannounce.
- Peer list reporting for the first 100 peers.
- Health snapshots covering metadata, connection counts, upload slots, local port, DHT nodes, distributed copies, and resume-data dirtiness.
- Recheck and completion verification.
- Download/upload speed limits.
- Pause/resume without adding duplicate handles.
- Seeding modes: stop at ratio, stop when complete, or never stop automatically.

## Remaining Torrent Hardening

- Add real-world magnet and `.torrent` integration tests with controlled fixtures.
- Keep optional libtorrent, Boost, OpenSSL, and CMake requirements out of ordinary release paths unless a release explicitly opts into the reference adapter again.
