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
- Magnet parameter parsing for trackers, web seeds (`ws`), acceptable/exact sources (`as`/`xs`), exact length, and explicit v2-only `btmh` diagnostics.
- `.torrent` web seed parsing for `url-list` and `httpseeds`, plus explicit v2-only rejection while allowing v1-compatible hybrid metadata.
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

## Manual Acceptance Matrix

Use the default SwiftPM build path unless the scenario explicitly mentions the optional native reference build.

| Scenario | Steps | Expected result |
| --- | --- | --- |
| Magnet entry point | Choose **Add Magnet Link** from the toolbar plus menu or File menu, then paste a v1 `btih` magnet. | The new task sheet opens in BT mode, keeps the magnet icon/title, shows tracker and web seed hints when present, and allows adding before metadata completes. |
| Torrent file entry point | Choose **Open Torrent File...** and select one or more `.torrent` files. | The new task sheet is prefilled with local paths, previews file lists, and uses torrent-focused copy and save-path details. |
| Web-seeded torrent | Open a `.torrent` containing `url-list` or `httpseeds`. | Preview shows deduplicated Web Seeds and the created task preserves tracker/web seed metadata for diagnostics. |
| v2-only torrent | Open a v2-only `.torrent` or `btmh` magnet. | The Swift engine rejects it with an explicit BitTorrent v2 unsupported diagnostic instead of a generic parse failure. |
| Hybrid torrent | Open a torrent with v1 fields plus v2 markers. | The Swift parser accepts the v1-compatible metadata and marks it as hybrid for diagnostics. |
| Inspector metrics | Select an active or completed BT task. | Overview includes upload speed, share ratio, peers, trackers, engine status, and seeding time cards in addition to generic download metrics. |
| Timeout fallback | Paste a magnet with `dn`, `xl`, `tr`, and `ws` but no reachable peers. | Timeout state keeps display name, size, trackers, and web seed hints so the task can still be added for background resolution. |
