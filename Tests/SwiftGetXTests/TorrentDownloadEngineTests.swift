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
        #expect(startRequests.first?.stopSeedingAtRatio == 2.5)
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
        let request = Self.request(selectedFileIndexes: [2, 0], hasExplicitFileSelection: true)

        await engine.start(request)
        await engine.setFileSelection(request, selectedFileIndexes: [1])

        let startRequests = await adapter.startRequests
        let selections = await adapter.fileSelections
        #expect(startRequests.first?.selectedFileIndexes == [2, 0])
        #expect(selections == [[1]])
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
        selectedFileIndexes: [Int] = [],
        hasExplicitFileSelection: Bool = false
    ) -> DownloadRequest {
        DownloadRequest(
            id: UUID(),
            name: "demo",
            source: source,
            resolvedTorrentFilePath: resolvedTorrentFilePath,
            kind: kind,
            status: .queued,
            savePath: "/tmp/demo",
            totalBytes: 0,
            downloadedBytes: 0,
            supportsResume: true,
            eTag: nil,
            lastModified: nil,
            selectedFileIndexes: selectedFileIndexes,
            hasExplicitFileSelection: hasExplicitFileSelection
        )
    }
}

private actor RecordingTorrentAdapter: TorrentEngineAdapter {
    private(set) var startRequests = [TorrentStartRequest]()
    private(set) var resumeRequests = [TorrentStartRequest]()
    private(set) var fileSelections = [[Int]]()

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
}
