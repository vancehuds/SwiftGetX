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
}

private actor RecordingTorrentAdapter: TorrentEngineAdapter {
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
