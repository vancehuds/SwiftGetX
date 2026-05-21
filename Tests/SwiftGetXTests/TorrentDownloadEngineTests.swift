import CryptoKit
import Foundation
import Testing
@testable import SwiftGetX
@testable import SwiftGetXTorrentCore

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

    @Test("default engine uses Swift peer runtime adapter")
    func defaultEngineUsesSwiftPeerRuntimeAdapter() {
        let engine = TorrentDownloadEngine()

        #expect(engine.engineKind == .swift)
        #expect(engine.engineStatus == .available)
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

    @Test("Swift adapter reports parsed metadata when no peers are available")
    func swiftAdapterReportsParsedMetadataWhenNoPeersAreAvailable() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        try Self.singleFileTorrentData(
            name: "payload.bin",
            length: 42,
            announce: nil
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
        #expect(snapshot.torrentTrackers?.isEmpty == true)
        #expect(snapshot.torrentConnection?.engine == .swift)
        #expect(snapshot.torrentConnection?.engineStatus == .available)
        #expect(snapshot.torrentHealth?.engine == .swift)
        #expect(snapshot.torrentHealth?.engineStatus == .available)
        #expect(snapshot.torrentHealth?.hasMetadata == true)
    }

    @Test("Swift adapter reports tracker peer diagnostics from mocked HTTP tracker")
    func swiftAdapterReportsTrackerPeerDiagnosticsFromMockedHTTPTracker() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        let trackerURL = "http://tracker.local/announce"
        try Self.singleFileTorrentData(
            name: "payload.bin",
            length: 42,
            announce: trackerURL
        ).write(to: torrentURL)
        let httpTransport = AppMockHTTPTrackerTransport(response: Self.httpTrackerResponse())
        let adapter = SwiftTorrentEngineAdapter(trackerClient: TorrentTrackerClient(
            httpTransport: httpTransport,
            retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
        ))
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
        let snapshots = try await store.snapshots(count: 2)

        #expect(snapshots.map(\.status) == [.fetchingPeers, .connectingPeers])
        #expect(snapshots.last?.errorMessage == nil)
        #expect(snapshots.last?.connectionSummary == L10n.string("torrent_tracker_connecting_peers", 1))
        #expect(snapshots.last?.torrentPeers == [
            TorrentPeerInfo(
                address: "127.0.0.1:6881",
                client: "",
                progress: 0,
                downloadRate: 0,
                uploadRate: 0,
                direction: "tracker",
                flags: "tracker"
            )
        ])
        #expect(snapshots.last?.torrentTrackers?.first?.url == trackerURL)
        #expect(snapshots.last?.torrentTrackers?.first?.status == L10n.string("torrent_tracker_working"))
        #expect(snapshots.last?.torrentTrackers?.first?.seedCount == 5)
        #expect(snapshots.last?.torrentTrackers?.first?.leecherCount == 6)
        #expect(snapshots.last?.torrentTrackers?.first?.downloadedCount == 7)
        #expect(snapshots.last?.torrentTrackers?.first?.nextAnnounce.isEmpty == false)
        #expect(snapshots.last?.torrentConnection?.peerCount == 1)
        #expect(snapshots.last?.torrentHealth?.peerCount == 1)
        #expect(await httpTransport.requests.count == 1)
        let announceURL = try #require(await httpTransport.requests.first?.url?.absoluteString)
        #expect(announceURL.contains("event=started"))
        #expect(announceURL.contains("left=42"))
    }

    @Test("Swift adapter completes a single-file download through a mocked peer")
    func swiftAdapterCompletesSingleFileDownloadThroughMockedPeer() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        let trackerURL = "http://tracker.local/announce"
        let contents = Data((0..<20).map(UInt8.init))
        try Self.singleFileTorrentData(
            name: "payload.bin",
            length: contents.count,
            announce: trackerURL,
            pieceLength: contents.count,
            pieceHashes: Data(Insecure.SHA1.hash(data: contents))
        ).write(to: torrentURL)
        let metainfo = try TorrentMetainfo.parse(url: torrentURL)
        let peerTransport = AppMockPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: metainfo.infoHashV1,
                    peerID: Data((60..<80).map(UInt8.init))
                ).encodedData(),
                try TorrentPeerWireMessage.unchoke.encodedData(),
                try TorrentPeerWireMessage.piece(pieceIndex: 0, begin: 0, block: contents).encodedData()
            ]
        )
        let httpTransport = AppMockHTTPTrackerTransport(response: Self.httpTrackerResponse())
        let adapter = SwiftTorrentEngineAdapter(
            trackerClient: TorrentTrackerClient(
                httpTransport: httpTransport,
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
            ),
            peerTransportFactory: { _ in peerTransport }
        )
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
            resumeDataPath: directory.appendingPathComponent("fixture.resume.json").path,
            runtimeOptions: TorrentRuntimeOptions(engine: .swift),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 0
        )

        try await adapter.start(request) { snapshot in
            Task {
                await store.append(snapshot)
            }
        }
        let snapshots = try await store.snapshots(count: 5)
        let completed = try #require(snapshots.last)
        let savedData = try Data(contentsOf: directory.appendingPathComponent("payload.bin"))

        #expect(snapshots.map(\.status) == [.fetchingPeers, .connectingPeers, .running, .running, .completed])
        #expect(completed.downloadedBytes == Int64(contents.count))
        #expect(completed.totalBytes == Int64(contents.count))
        #expect(completed.etaSeconds == nil)
        #expect(completed.torrentConnection?.peerCount == 1)
        #expect(snapshots[3].speedBytesPerSecond > 0)
        #expect(snapshots[3].etaSeconds == nil)
        #expect(savedData == contents)
        #expect(try TorrentPeerWireMessage.decodeFrame((await peerTransport.sentFrames)[1]) == .interested)
        #expect(try TorrentPeerWireMessage.decodeFrame((await peerTransport.sentFrames)[2]) == .request(pieceIndex: 0, begin: 0, length: contents.count))
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
        announce: String? = nil,
        pieceLength: Int = 16_384,
        pieceHashes: Data? = nil
    ) -> Data {
        let hashes = pieceHashes ?? Data("aaaaaaaaaaaaaaaaaaaa".utf8)
        var data = Data("d".utf8)
        if let announce {
            data.append(bencodeString("announce"))
            data.append(bencodeString(announce))
        }
        data.append(bencodeString("info"))
        data.append(Data("d6:lengthi\(length)e4:name\(name.count):\(name)12:piece lengthi\(pieceLength)e6:pieces\(hashes.count):".utf8))
        data.append(hashes)
        data.append(UInt8(ascii: "e"))
        data.append(UInt8(ascii: "e"))
        return data
    }

    private static func bencodeString(_ value: String) -> Data {
        var data = Data("\(value.utf8.count):".utf8)
        data.append(contentsOf: value.utf8)
        return data
    }

    private static func httpTrackerResponse() -> Data {
        var data = Data("d".utf8)
        data.append(bencodeString("complete"))
        data.append(Data("i5e".utf8))
        data.append(bencodeString("downloaded"))
        data.append(Data("i7e".utf8))
        data.append(bencodeString("incomplete"))
        data.append(Data("i6e".utf8))
        data.append(bencodeString("interval"))
        data.append(Data("i30e".utf8))
        data.append(bencodeString("min interval"))
        data.append(Data("i15e".utf8))
        data.append(bencodeString("peers"))
        data.append(Data("6:".utf8))
        data.append(contentsOf: [127, 0, 0, 1, 0x1a, 0xe1])
        data.append(UInt8(ascii: "e"))
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

    func snapshots(count: Int) async throws -> [DownloadSnapshot] {
        for _ in 0..<20 {
            if snapshots.count >= count {
                return Array(snapshots.prefix(count))
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw SnapshotStoreError.missingSnapshot
    }
}

private enum SnapshotStoreError: Error {
    case missingSnapshot
}

private actor AppMockHTTPTrackerTransport: TorrentHTTPTrackerTransport {
    private(set) var requests = [URLRequest]()
    private let response: Data

    init(response: Data) {
        self.response = response
    }

    func load(_ request: URLRequest) async throws -> Data {
        requests.append(request)
        return response
    }
}

private actor AppMockPeerWireTransport: TorrentPeerWireTransport {
    private var responses: [Data]
    private(set) var sentFrames = [Data]()

    init(responses: [Data]) {
        self.responses = responses
    }

    func send(_ data: Data) async throws {
        sentFrames.append(data)
    }

    func receive(maximumLength: Int) async throws -> Data {
        guard !responses.isEmpty else {
            return Data()
        }
        var next = responses.removeFirst()
        if next.count <= maximumLength {
            return next
        }
        let chunk = next.prefix(maximumLength)
        next.removeFirst(maximumLength)
        responses.insert(next, at: 0)
        return Data(chunk)
    }
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
