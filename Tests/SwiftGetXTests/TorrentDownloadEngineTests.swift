import Foundation
import Testing
@testable import SwiftGetX

@Suite("TorrentDownloadEngine")
@MainActor
struct TorrentDownloadEngineTests {
    @Test("passes configured stop seeding ratio to adapter")
    func passesConfiguredStopSeedingRatio() async throws {
        let adapter = RecordingTorrentAdapter()
        let engine = TorrentDownloadEngine(adapter: adapter)
        engine.configure(stopSeedingAtRatio: 2.5)

        await engine.start(Self.request())

        let startRequests = await adapter.startRequests
        #expect(startRequests.count == 1)
        #expect(startRequests.first?.runtimeOptions.stopSeedingAtRatio == 2.5)
    }

    @Test("uses resolved torrent file path when present")
    func usesResolvedTorrentFilePath() async throws {
        let adapter = RecordingTorrentAdapter()
        let engine = TorrentDownloadEngine(adapter: adapter)

        await engine.start(Self.request(
            source: "https://example.com/demo.torrent",
            kind: .torrentFile,
            resolvedTorrentFilePath: "/tmp/cache/demo.torrent"
        ))

        let startRequests = await adapter.startRequests
        #expect(startRequests.first?.displaySource == "https://example.com/demo.torrent")
        #expect(startRequests.first?.resolvedTorrentFilePath == "/tmp/cache/demo.torrent")
    }

    @Test("passes save directory separately from content paths")
    func passesSaveDirectorySeparatelyFromContentPaths() async throws {
        let adapter = RecordingTorrentAdapter()
        let engine = TorrentDownloadEngine(adapter: adapter)

        await engine.start(Self.request(
            savePath: "/tmp/downloads/album",
            torrentSaveDirectoryPath: "/tmp/downloads",
            torrentOutputName: "album",
            torrentContentRootPath: "/tmp/downloads/album",
            torrentFinalFilePath: nil
        ))

        let startRequests = await adapter.startRequests
        #expect(startRequests.first?.savePath == "/tmp/downloads")
        #expect(startRequests.first?.outputName == "album")
        #expect(startRequests.first?.contentRootPath == "/tmp/downloads/album")
        #expect(startRequests.first?.finalFilePath == nil)
    }

    @Test("resume uses adapter resume without adding a second handle")
    func resumeUsesAdapterResume() async throws {
        let adapter = RecordingTorrentAdapter()
        let engine = TorrentDownloadEngine(adapter: adapter)
        let request = Self.request()

        await engine.start(request)
        await engine.resume(request)

        let startCount = await adapter.startRequests.count
        let resumeCount = await adapter.resumeRequests.count
        #expect(startCount == 1)
        #expect(resumeCount == 1)
    }

    @Test("forwards selected file indexes")
    func forwardsSelectedFileIndexes() async throws {
        let adapter = RecordingTorrentAdapter()
        let engine = TorrentDownloadEngine(adapter: adapter)
        let request = Self.request(
            selectedFileIndexes: [2, 0],
            torrentFiles: [
                TorrentFile(index: 0, path: "a", size: 1, priority: 7),
                TorrentFile(index: 2, path: "b", size: 1, priority: 2)
            ],
            hasExplicitFileSelection: true
        )

        await engine.start(request)
        await engine.setFileSelection(request, selectedFileIndexes: [1])

        let startRequests = await adapter.startRequests
        let selections = await adapter.fileSelections
        #expect(startRequests.first?.selectedFileIndexes == [2, 0])
        #expect(startRequests.first?.filePriorities == [0: 7, 2: 2])
        #expect(selections == [[1]])
    }

    @Test("forwards runtime options and resume data path")
    func forwardsRuntimeOptionsAndResumeDataPath() async throws {
        let adapter = RecordingTorrentAdapter()
        let engine = TorrentDownloadEngine(adapter: adapter)
        let options = TorrentRuntimeOptions(
            isDHTEnabled: false,
            isPEXEnabled: false,
            isLSDEnabled: false,
            isSequentialDownloadEnabled: true,
            magnetMetadataTimeoutSeconds: 45,
            maxConnections: 50,
            maxUploadSlots: 3,
            seedingLimitMode: .neverStop,
            stopSeedingAtRatio: 4
        )

        await engine.start(Self.request(
            torrentResumeState: TorrentResumeState(resumeDataPath: "/tmp/demo.fastresume", status: .saved),
            torrentRuntimeOptions: options
        ))

        let startRequests = await adapter.startRequests
        #expect(startRequests.first?.resumeDataPath == "/tmp/demo.fastresume")
        #expect(startRequests.first?.runtimeOptions == options)
    }

    @Test("configuration is forwarded to adapter")
    func configurationIsForwardedToAdapter() async throws {
        let adapter = RecordingTorrentAdapter()
        let engine = TorrentDownloadEngine(adapter: adapter)
        let options = TorrentRuntimeOptions(
            isDHTEnabled: false,
            isPEXEnabled: false,
            isLSDEnabled: false,
            maxConnections: 32,
            maxUploadSlots: 2,
            seedingLimitMode: .neverStop
        )

        await engine.configure(runtimeOptions: options).value

        let configurations = await adapter.runtimeConfigurations
        #expect(configurations.last == options)
    }

    @Test("forwards torrent control commands")
    func forwardsTorrentControlCommands() async throws {
        let adapter = RecordingTorrentAdapter()
        let engine = TorrentDownloadEngine(adapter: adapter)
        let request = Self.request()

        await engine.setTorrentFilePriority(request, fileIndex: 2, priority: 7)
        await engine.setTorrentSequentialDownload(request, enabled: true)
        await engine.addTorrentTracker(request, url: "udp://tracker.example:80")
        await engine.removeTorrentTracker(request, url: "udp://tracker.example:80")
        await engine.forceTorrentReannounce(request)

        let priorities = await adapter.filePriorities
        let sequential = await adapter.sequentialChanges
        let added = await adapter.addedTrackers
        let removed = await adapter.removedTrackers
        let reannounceCount = await adapter.reannounceCount
        #expect(priorities.first?.fileIndex == 2)
        #expect(priorities.first?.priority == 7)
        #expect(sequential == [true])
        #expect(added == ["udp://tracker.example:80"])
        #expect(removed == ["udp://tracker.example:80"])
        #expect(reannounceCount == 1)
    }

    @Test("keeps implicit empty selection distinct from explicit cleared selection")
    func keepsImplicitEmptySelectionDistinctFromExplicitClearedSelection() async throws {
        let adapter = RecordingTorrentAdapter()
        let engine = TorrentDownloadEngine(adapter: adapter)
        let implicitRequest = Self.request(selectedFileIndexes: [], hasExplicitFileSelection: false)
        let explicitRequest = Self.request(selectedFileIndexes: [], hasExplicitFileSelection: true)

        await engine.start(implicitRequest)
        await engine.start(explicitRequest)

        let startRequests = await adapter.startRequests
        #expect(startRequests.map(\.hasExplicitFileSelection) == [false, true])
    }

    @Test("default engine uses Swift metadata adapter")
    func defaultEngineUsesSwiftMetadataAdapter() {
        let engine = TorrentDownloadEngine()

        #expect(engine.engineKind == .swift)
        #expect(engine.engineStatus == .metadataOnly)
    }

    @Test("libtorrent setting keeps libtorrent identity when bridge is unavailable")
    func libtorrentSettingKeepsLibtorrentIdentityWhenBridgeIsUnavailable() async throws {
        let engine = TorrentDownloadEngine()

        await engine.configure(runtimeOptions: TorrentRuntimeOptions(engine: .libtorrent)).value

        #expect(engine.engineKind == .libtorrent)
        #if !canImport(CSwiftGetXLibtorrent)
        #expect(engine.engineStatus == .unavailable)
        #endif
    }

    @Test("Swift adapter reports metadata-only torrent snapshots")
    func swiftAdapterReportsMetadataOnlyTorrentSnapshots() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        try Self.singleFileTorrentData(
            name: "payload.bin",
            length: 42,
            announce: "udp://tracker.example:80"
        ).write(to: torrentURL)
        let adapter = SwiftTorrentEngineAdapter()
        let store = SnapshotStore()
        let request = TorrentStartRequest(
            id: UUID(),
            displaySource: "file://\(torrentURL.path)",
            resolvedTorrentFilePath: torrentURL.path,
            savePath: directory.path,
            outputName: "payload.bin",
            contentRootPath: directory.path,
            finalFilePath: directory.appendingPathComponent("payload.bin").path,
            totalBytes: 0,
            downloadedBytes: 0,
            selectedFileIndexes: [],
            hasExplicitFileSelection: false,
            filePriorities: [:],
            resumeDataPath: nil,
            runtimeOptions: TorrentRuntimeOptions(engine: .swift),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 0
        )

        try await adapter.start(request) { snapshot in
            Task {
                await store.append(snapshot)
            }
        }
        let snapshot = try await store.firstSnapshot()

        #expect(snapshot.status == .failed)
        #expect(snapshot.errorMessage == L10n.string("torrent_swift_engine_runtime_pending"))
        #expect(snapshot.totalBytes == 42)
        #expect(snapshot.torrentMetadataStatus == .available)
        #expect(snapshot.torrentFiles == [
            TorrentFile(index: 0, path: "payload.bin", size: 42, priority: TorrentFilePriority.normal.rawValue)
        ])
        #expect(snapshot.torrentTrackers?.map(\.url) == ["udp://tracker.example:80"])
        #expect(snapshot.torrentConnection?.engine == .swift)
        #expect(snapshot.torrentConnection?.engineStatus == .metadataOnly)
        #expect(snapshot.torrentHealth?.engine == .swift)
        #expect(snapshot.torrentHealth?.engineStatus == .metadataOnly)
        #expect(snapshot.torrentHealth?.hasMetadata == true)
    }

    private static func request(
        source: String = "magnet:?xt=urn:btih:abcdef",
        kind: DownloadKind = .torrentMagnet,
        resolvedTorrentFilePath: String? = nil,
        savePath: String = "/tmp/demo",
        torrentSaveDirectoryPath: String? = nil,
        torrentOutputName: String? = nil,
        torrentContentRootPath: String? = nil,
        torrentFinalFilePath: String? = nil,
        selectedFileIndexes: [Int] = [],
        torrentFiles: [TorrentFile] = [],
        torrentResumeState: TorrentResumeState? = nil,
        torrentRuntimeOptions: TorrentRuntimeOptions? = nil,
        hasExplicitFileSelection: Bool = false
    ) -> DownloadRequest {
        DownloadRequest(
            id: UUID(),
            name: "demo",
            source: source,
            resolvedTorrentFilePath: resolvedTorrentFilePath,
            kind: kind,
            status: .queued,
            savePath: savePath,
            torrentSaveDirectoryPath: torrentSaveDirectoryPath,
            torrentOutputName: torrentOutputName,
            torrentContentRootPath: torrentContentRootPath,
            torrentFinalFilePath: torrentFinalFilePath,
            totalBytes: 0,
            downloadedBytes: 0,
            supportsResume: true,
            eTag: nil,
            lastModified: nil,
            selectedFileIndexes: selectedFileIndexes,
            torrentFiles: torrentFiles,
            torrentResumeState: torrentResumeState,
            torrentRuntimeOptions: torrentRuntimeOptions,
            hasExplicitFileSelection: hasExplicitFileSelection
        )
    }

    private static func singleFileTorrentData(
        name: String,
        length: Int,
        announce: String? = nil
    ) -> Data {
        var data = Data("d".utf8)
        if let announce {
            data.append(bencodeString("announce"))
            data.append(bencodeString(announce))
        }
        data.append(bencodeString("info"))
        data.append(Data("d6:lengthi\(length)e4:name\(name.count):\(name)12:piece lengthi16384e6:pieces20:aaaaaaaaaaaaaaaaaaaae".utf8))
        data.append(UInt8(ascii: "e"))
        return data
    }

    private static func bencodeString(_ value: String) -> Data {
        var data = Data("\(value.utf8.count):".utf8)
        data.append(contentsOf: value.utf8)
        return data
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor SnapshotStore {
    private var snapshots = [DownloadSnapshot]()

    func append(_ snapshot: DownloadSnapshot) {
        snapshots.append(snapshot)
    }

    func firstSnapshot() async throws -> DownloadSnapshot {
        for _ in 0..<20 {
            if let snapshot = snapshots.first {
                return snapshot
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw SnapshotStoreError.missingSnapshot
    }
}

private enum SnapshotStoreError: Error {
    case missingSnapshot
}

private actor RecordingTorrentAdapter: TorrentEngineAdapter {
    nonisolated var engineKind: TorrentEngineKind { .swift }
    nonisolated var engineStatus: TorrentEngineStatus { .metadataOnly }

    private(set) var startRequests = [TorrentStartRequest]()
    private(set) var resumeRequests = [TorrentStartRequest]()
    private(set) var fileSelections = [[Int]]()
    private(set) var filePriorities = [(fileIndex: Int, priority: Int)]()
    private(set) var sequentialChanges = [Bool]()
    private(set) var addedTrackers = [String]()
    private(set) var removedTrackers = [String]()
    private(set) var reannounceCount = 0
    private(set) var runtimeConfigurations = [TorrentRuntimeOptions]()

    func start(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws {
        startRequests.append(request)
    }

    func resume(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws {
        resumeRequests.append(request)
    }

    func pause(id: UUID) async {}
    func cancel(id: UUID) async {}
    func remove(id: UUID, deletingFiles: Bool) async {}
    func recheck(id: UUID) async {}
    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async {}

    func setFileSelection(id: UUID, selectedFileIndexes: [Int]) async {
        fileSelections.append(selectedFileIndexes)
    }

    func setFilePriority(id: UUID, fileIndex: Int, priority: Int) async {
        filePriorities.append((fileIndex, priority))
    }

    func setSequentialDownload(id: UUID, enabled: Bool) async {
        sequentialChanges.append(enabled)
    }

    func addTracker(id: UUID, url: String) async {
        addedTrackers.append(url)
    }

    func removeTracker(id: UUID, url: String) async {
        removedTrackers.append(url)
    }

    func forceReannounce(id: UUID) async {
        reannounceCount += 1
    }

    func configure(runtimeOptions: TorrentRuntimeOptions) async {
        runtimeConfigurations.append(runtimeOptions)
    }
}
