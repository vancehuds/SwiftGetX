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
        await engine.setTorrentRuntimeOptions(request, options: TorrentRuntimeOptions(seedingLimitMode: .stopAfterTime, stopSeedingAfterSeconds: 120))
        await engine.addTorrentTracker(request, url: "udp://tracker.example:80")
        await engine.removeTorrentTracker(request, url: "udp://tracker.example:80")
        await engine.forceTorrentReannounce(request)

        let priorities = await adapter.filePriorities
        let sequential = await adapter.sequentialChanges
        let runtimeOptions = await adapter.runtimeOptionChanges
        let added = await adapter.addedTrackers
        let removed = await adapter.removedTrackers
        let reannounceCount = await adapter.reannounceCount
        #expect(priorities.first?.fileIndex == 2)
        #expect(priorities.first?.priority == 7)
        #expect(sequential == [true])
        #expect(runtimeOptions.first?.seedingLimitMode == .stopAfterTime)
        #expect(runtimeOptions.first?.stopSeedingAfterSeconds == 120)
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
        let adapter = SwiftTorrentEngineAdapter(
            dhtTransport: nil,
            dhtBootstrapNodes: []
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
        #expect(snapshot.errorMessage == L10n.string("torrent_tracker_no_peers"))
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
        let adapter = SwiftTorrentEngineAdapter(
            trackerClient: TorrentTrackerClient(
                httpTransport: httpTransport,
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
            ),
            dhtTransport: nil,
            dhtBootstrapNodes: []
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
                flags: "tracker",
                source: "tracker"
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

    @Test("Swift adapter fetches magnet metadata through an extended peer and downloads")
    func swiftAdapterFetchesMagnetMetadataThroughExtendedPeerAndDownloads() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let trackerURL = "http://tracker.local/announce"
        let contents = Data((0..<20).map(UInt8.init))
        let info = Self.singleFileInfoData(
            name: "payload.bin",
            length: contents.count,
            pieceLength: contents.count,
            pieceHashes: Data(Insecure.SHA1.hash(data: contents))
        )
        let infoHash = Data(Insecure.SHA1.hash(data: info))
        let metadataMessageID: UInt8 = 4
        let metadataTransport = AppMockPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: infoHash,
                    peerID: Data((60..<80).map(UInt8.init)),
                    reserved: TorrentPeerWireHandshake.extensionProtocolReservedBytes
                ).encodedData(),
                try TorrentPeerWireMessage.extended(
                    extendedID: TorrentPeerExtensionHandshake.handshakeExtendedID,
                    payload: TorrentPeerExtensionHandshake(
                        utMetadataMessageID: metadataMessageID,
                        metadataSize: info.count
                    ).encodedPayload()
                ).encodedData(),
                try TorrentPeerWireMessage.extended(
                    extendedID: metadataMessageID,
                    payload: TorrentMetadataExtensionMessage.data(
                        pieceIndex: 0,
                        totalSize: info.count,
                        metadata: info
                    ).encodedPayload()
                ).encodedData()
            ]
        )
        let downloadTransport = AppMockPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: infoHash,
                    peerID: Data((80..<100).map(UInt8.init))
                ).encodedData(),
                try TorrentPeerWireMessage.unchoke.encodedData(),
                try TorrentPeerWireMessage.piece(pieceIndex: 0, begin: 0, block: contents).encodedData()
            ]
        )
        let peer = TorrentPeerEndpoint(host: "127.0.0.1", port: 6_881)
        let transportFactory = AppQueuedPeerWireTransportFactory(transports: [
            peer.address: [metadataTransport, downloadTransport]
        ])
        let httpTransport = AppMockHTTPTrackerTransport(response: Self.httpTrackerResponse(peers: [peer]))
        let adapter = SwiftTorrentEngineAdapter(
            trackerClient: TorrentTrackerClient(
                httpTransport: httpTransport,
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
            ),
            peerTransportFactory: { endpoint in
                try await transportFactory.nextTransport(for: endpoint)
            },
            dhtTransport: nil,
            dhtBootstrapNodes: []
        )
        let store = SnapshotStore()
        let magnet = "magnet:?xt=urn:btih:\(infoHash.hexEncodedString)&dn=payload.bin&xl=\(contents.count)&tr=\(Self.percentEncoded(trackerURL))"
        let request = TorrentStartRequest(
            id: UUID(),
            displaySource: magnet,
            resolvedTorrentFilePath: nil,
            savePath: directory.path,
            outputName: "payload.bin",
            contentRootPath: directory.path,
            finalFilePath: directory.appendingPathComponent("payload.bin").path,
            totalBytes: Int64(contents.count),
            downloadedBytes: 0,
            selectedFileIndexes: [],
            hasExplicitFileSelection: false,
            filePriorities: [:],
            resumeDataPath: directory.appendingPathComponent("fixture.resume.json").path,
            runtimeOptions: TorrentRuntimeOptions(
                engine: .swift,
                magnetMetadataTimeoutSeconds: 2,
                seedingLimitMode: .stopWhenComplete
            ),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 0
        )

        try await adapter.start(request) { snapshot in
            Task {
                await store.append(snapshot)
            }
        }
        let snapshots = try await store.snapshots(untilStatus: .completed)
        let final = try #require(snapshots.last { $0.status == .completed })
        let savedData = try Data(contentsOf: directory.appendingPathComponent("payload.bin"))

        let statuses = snapshots.map(\.status)
        #expect(statuses.filter { $0 == .fetchingMetadata }.count >= 2)
        #expect(statuses.contains(.connectingPeers))
        #expect(statuses.contains(.running))
        #expect(statuses.contains(.completed))
        #expect(snapshots.contains { $0.torrentMetadataStatus == .fetching })
        #expect(snapshots.contains { $0.torrentMetadataStatus == .available })
        #expect(final.torrentFiles == [
            TorrentFile(index: 0, path: "payload.bin", size: Int64(contents.count), priority: TorrentFilePriority.normal.rawValue, progress: 1)
        ])
        #expect(savedData == contents)
        #expect(try TorrentPeerWireMessage.decodeFrame((await metadataTransport.sentFrames)[1]) == .extended(
            extendedID: TorrentPeerExtensionHandshake.handshakeExtendedID,
            payload: try TorrentPeerExtensionHandshake().encodedPayload()
        ))
        #expect(try TorrentPeerWireMessage.decodeFrame((await metadataTransport.sentFrames)[2]) == .extended(
            extendedID: metadataMessageID,
            payload: TorrentMetadataExtensionMessage.request(pieceIndex: 0).encodedPayload()
        ))
    }

    @Test("Swift adapter keeps waiting after magnet metadata timeout")
    func swiftAdapterKeepsWaitingAfterMagnetMetadataTimeout() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let trackerURL = "http://tracker.local/announce"
        let contents = Data((0..<8).map(UInt8.init))
        let info = Self.singleFileInfoData(
            name: "payload.bin",
            length: contents.count,
            pieceLength: contents.count,
            pieceHashes: Data(Insecure.SHA1.hash(data: contents))
        )
        let infoHash = Data(Insecure.SHA1.hash(data: info))
        let metadataMessageID: UInt8 = 6
        let metadataTransport = AppDelayedPeerWireTransport(
            responses: [
                .init(data: try TorrentPeerWireHandshake(
                    infoHash: infoHash,
                    peerID: Data((60..<80).map(UInt8.init)),
                    reserved: TorrentPeerWireHandshake.extensionProtocolReservedBytes
                ).encodedData()),
                .init(data: try TorrentPeerWireMessage.extended(
                    extendedID: TorrentPeerExtensionHandshake.handshakeExtendedID,
                    payload: TorrentPeerExtensionHandshake(
                        utMetadataMessageID: metadataMessageID,
                        metadataSize: info.count
                    ).encodedPayload()
                ).encodedData()),
                .init(
                    data: try TorrentPeerWireMessage.extended(
                        extendedID: metadataMessageID,
                        payload: TorrentMetadataExtensionMessage.data(
                            pieceIndex: 0,
                            totalSize: info.count,
                            metadata: info
                        ).encodedPayload()
                    ).encodedData(),
                    delay: .milliseconds(1_100)
                )
            ]
        )
        let downloadTransport = AppMockPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: infoHash,
                    peerID: Data((80..<100).map(UInt8.init))
                ).encodedData(),
                try TorrentPeerWireMessage.unchoke.encodedData(),
                try TorrentPeerWireMessage.piece(pieceIndex: 0, begin: 0, block: contents).encodedData()
            ]
        )
        let peer = TorrentPeerEndpoint(host: "127.0.0.1", port: 6_881)
        let transportFactory = AppQueuedPeerWireTransportFactory(transports: [
            peer.address: [metadataTransport, downloadTransport]
        ])
        let httpTransport = AppMockHTTPTrackerTransport(response: Self.httpTrackerResponse(peers: [peer]))
        let adapter = SwiftTorrentEngineAdapter(
            trackerClient: TorrentTrackerClient(
                httpTransport: httpTransport,
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
            ),
            peerTransportFactory: { endpoint in
                try await transportFactory.nextTransport(for: endpoint)
            },
            dhtTransport: nil,
            dhtBootstrapNodes: []
        )
        let store = SnapshotStore()
        let magnet = "magnet:?xt=urn:btih:\(infoHash.hexEncodedString)&dn=payload.bin&tr=\(Self.percentEncoded(trackerURL))"
        let request = TorrentStartRequest(
            id: UUID(),
            displaySource: magnet,
            resolvedTorrentFilePath: nil,
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
            runtimeOptions: TorrentRuntimeOptions(
                engine: .swift,
                magnetMetadataTimeoutSeconds: 1,
                seedingLimitMode: .stopWhenComplete
            ),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 0
        )

        try await adapter.start(request) { snapshot in
            Task {
                await store.append(snapshot)
            }
        }
        let snapshots = try await store.snapshots(count: 7)

        #expect(snapshots.map(\.status) == [
            .fetchingMetadata,
            .fetchingMetadata,
            .fetchingMetadata,
            .connectingPeers,
            .running,
            .running,
            .completed
        ])
        #expect(snapshots[2].errorMessage == TorrentMetadataError.metadataTimeout.localizedDescription)
        #expect(snapshots.last?.torrentMetadataStatus == .available)
        #expect(try Data(contentsOf: directory.appendingPathComponent("payload.bin")) == contents)
    }

    @Test("Swift adapter rejects magnet metadata with the wrong info hash")
    func swiftAdapterRejectsMagnetMetadataWithWrongInfoHash() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let trackerURL = "http://tracker.local/announce"
        let contents = Data((0..<20).map(UInt8.init))
        let info = Self.singleFileInfoData(
            name: "payload.bin",
            length: contents.count,
            pieceLength: contents.count,
            pieceHashes: Data(Insecure.SHA1.hash(data: contents))
        )
        let wrongHash = Data(repeating: 7, count: 20)
        let metadataMessageID: UInt8 = 4
        let peer = TorrentPeerEndpoint(host: "127.0.0.1", port: 6_881)
        let metadataTransport = AppMockPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: wrongHash,
                    peerID: Data((60..<80).map(UInt8.init)),
                    reserved: TorrentPeerWireHandshake.extensionProtocolReservedBytes
                ).encodedData(),
                try TorrentPeerWireMessage.extended(
                    extendedID: TorrentPeerExtensionHandshake.handshakeExtendedID,
                    payload: TorrentPeerExtensionHandshake(
                        utMetadataMessageID: metadataMessageID,
                        metadataSize: info.count
                    ).encodedPayload()
                ).encodedData(),
                try TorrentPeerWireMessage.extended(
                    extendedID: metadataMessageID,
                    payload: TorrentMetadataExtensionMessage.data(
                        pieceIndex: 0,
                        totalSize: info.count,
                        metadata: info
                    ).encodedPayload()
                ).encodedData()
            ]
        )
        let transportFactory = AppQueuedPeerWireTransportFactory(transports: [
            peer.address: [metadataTransport]
        ])
        let httpTransport = AppMockHTTPTrackerTransport(response: Self.httpTrackerResponse(peers: [peer]))
        let adapter = SwiftTorrentEngineAdapter(
            trackerClient: TorrentTrackerClient(
                httpTransport: httpTransport,
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
            ),
            peerTransportFactory: { endpoint in
                try await transportFactory.nextTransport(for: endpoint)
            },
            dhtTransport: nil,
            dhtBootstrapNodes: []
        )
        let store = SnapshotStore()
        let magnet = "magnet:?xt=urn:btih:\(wrongHash.hexEncodedString)&dn=payload.bin&tr=\(Self.percentEncoded(trackerURL))"
        let request = TorrentStartRequest(
            id: UUID(),
            displaySource: magnet,
            resolvedTorrentFilePath: nil,
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
            runtimeOptions: TorrentRuntimeOptions(engine: .swift, magnetMetadataTimeoutSeconds: 2),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 0
        )

        try await adapter.start(request) { snapshot in
            Task {
                await store.append(snapshot)
            }
        }
        let snapshots = try await store.snapshots(count: 3)
        let final = try #require(snapshots.last)

        #expect(snapshots.map(\.status) == [.fetchingMetadata, .fetchingMetadata, .failed])
        #expect(final.torrentMetadataStatus == .failed)
        #expect(final.errorMessage?.contains("metadata hash mismatch") == true)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("payload.bin").path))
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
            peerTransportFactory: { _ in peerTransport },
            dhtTransport: nil,
            dhtBootstrapNodes: []
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
            runtimeOptions: TorrentRuntimeOptions(engine: .swift, seedingLimitMode: .stopWhenComplete),
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

        await adapter.cancel(id: request.id)

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
        let announceURLs = await httpTransport.requests.compactMap { $0.url?.absoluteString }
        #expect(announceURLs.contains { $0.contains("event=started") })
        #expect(announceURLs.contains { $0.contains("event=completed") })
        #expect(announceURLs.contains { $0.contains("event=stopped") })
    }

    @Test("Swift adapter downloads only wanted file pieces")
    func swiftAdapterDownloadsOnlyWantedFilePieces() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        let trackerURL = "http://tracker.local/announce"
        let firstFile = Data((0..<4).map(UInt8.init))
        let secondFile = Data((4..<8).map(UInt8.init))
        try Self.multiFileTorrentData(
            rootName: "album",
            files: [
                (["first.bin"], firstFile),
                (["second.bin"], secondFile)
            ],
            announce: trackerURL,
            pieceLength: firstFile.count
        ).write(to: torrentURL)
        let metainfo = try TorrentMetainfo.parse(url: torrentURL)
        let peerTransport = AppMockPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: metainfo.infoHashV1,
                    peerID: Data((60..<80).map(UInt8.init))
                ).encodedData(),
                try TorrentPeerWireMessage.unchoke.encodedData(),
                try TorrentPeerWireMessage.piece(pieceIndex: 0, begin: 0, block: firstFile).encodedData()
            ]
        )
        let httpTransport = AppMockHTTPTrackerTransport(response: Self.httpTrackerResponse())
        let adapter = SwiftTorrentEngineAdapter(
            trackerClient: TorrentTrackerClient(
                httpTransport: httpTransport,
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
            ),
            peerTransportFactory: { _ in peerTransport },
            dhtTransport: nil,
            dhtBootstrapNodes: []
        )
        let store = SnapshotStore()
        let request = TorrentStartRequest(
            id: UUID(),
            displaySource: "file://\(torrentURL.path)",
            resolvedTorrentFilePath: torrentURL.path,
            savePath: directory.path,
            outputName: "album",
            contentRootPath: directory.appendingPathComponent("album").path,
            finalFilePath: nil,
            totalBytes: 0,
            downloadedBytes: 0,
            selectedFileIndexes: [0],
            hasExplicitFileSelection: true,
            filePriorities: [
                0: TorrentFilePriority.normal.rawValue,
                1: TorrentFilePriority.skip.rawValue
            ],
            resumeDataPath: directory.appendingPathComponent("fixture.resume.json").path,
            runtimeOptions: TorrentRuntimeOptions(engine: .swift, seedingLimitMode: .stopWhenComplete),
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
        let writtenFirstFile = try Data(contentsOf: directory.appendingPathComponent("album/first.bin"))
        let secondFileURL = directory.appendingPathComponent("album/second.bin")
        let sentFrames = await peerTransport.sentFrames
        let requestedPieces = try sentFrames.dropFirst().compactMap { frame -> Int? in
            if case .request(let pieceIndex, _, _) = try TorrentPeerWireMessage.decodeFrame(frame) {
                return pieceIndex
            }
            return nil
        }

        #expect(snapshots.map(\.status) == [.fetchingPeers, .connectingPeers, .running, .running, .completed])
        #expect(writtenFirstFile == firstFile)
        #expect(!FileManager.default.fileExists(atPath: secondFileURL.path))
        #expect(completed.downloadedBytes == Int64(firstFile.count))
        #expect(completed.totalBytes == Int64(firstFile.count))
        #expect(completed.torrentFiles.map(\.progress) == [1, 0])
        #expect(completed.torrentFiles.map(\.priorityLevel) == [.normal, .skip])
        #expect(requestedPieces == [0])
    }

    @Test("Swift adapter stops seeding after configured time")
    func swiftAdapterStopsSeedingAfterConfiguredTime() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        let trackerURL = "http://tracker.local/announce"
        let contents = Data((0..<12).map(UInt8.init))
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
            peerTransportFactory: { _ in peerTransport },
            dhtTransport: nil,
            dhtBootstrapNodes: []
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
            runtimeOptions: TorrentRuntimeOptions(
                engine: .swift,
                seedingLimitMode: .stopAfterTime,
                stopSeedingAfterSeconds: 0.05
            ),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 512
        )

        try await adapter.start(request) { snapshot in
            Task {
                await store.append(snapshot)
            }
        }
        let snapshots = try await store.snapshots(untilStatus: .completed)
        let final = try #require(snapshots.last)

        #expect(snapshots.map(\.status).contains(.seeding))
        #expect(final.status == .completed)
        #expect(final.torrentConnection?.seedingDurationSeconds ?? 0 >= 0.05)
        #expect(final.torrentConnection?.shareRatio ?? 0 > 0)
        let announceURLs = await httpTransport.requests.compactMap { $0.url?.absoluteString }
        #expect(announceURLs.contains { $0.contains("event=completed") })
        #expect(announceURLs.contains { $0.contains("event=stopped") })
    }

    @Test("Swift adapter applies seeding policy changes while seeding")
    func swiftAdapterAppliesSeedingPolicyChangesWhileSeeding() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        let trackerURL = "http://tracker.local/announce"
        let contents = Data((0..<12).map(UInt8.init))
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
            peerTransportFactory: { _ in peerTransport },
            dhtTransport: nil,
            dhtBootstrapNodes: []
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
            runtimeOptions: TorrentRuntimeOptions(
                engine: .swift,
                seedingLimitMode: .neverStop
            ),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 512
        )

        try await adapter.start(request) { snapshot in
            Task {
                await store.append(snapshot)
            }
        }
        _ = try await store.snapshots(untilStatus: .seeding)
        await adapter.setRuntimeOptions(
            id: request.id,
            options: TorrentRuntimeOptions(
                engine: .swift,
                seedingLimitMode: .stopAfterTime,
                stopSeedingAfterSeconds: 0.05
            )
        )
        let snapshots = try await store.snapshots(untilStatus: .completed)
        let final = try #require(snapshots.last)

        #expect(snapshots.map(\.status).contains(.seeding))
        #expect(final.status == .completed)
        #expect(final.torrentConnection?.seedingDurationSeconds ?? 0 >= 0.05)
        let announceURLs = await httpTransport.requests.compactMap { $0.url?.absoluteString }
        #expect(announceURLs.contains { $0.contains("event=stopped") })
    }

    @Test("Swift adapter retries scored peers and maps swarm runtime snapshots")
    func swiftAdapterRetriesScoredPeersAndMapsSwarmRuntimeSnapshots() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        let trackerURL = "http://tracker.local/announce"
        let firstPiece = Data((0..<8).map(UInt8.init))
        let secondPiece = Data((8..<16).map(UInt8.init))
        var pieceHashes = Data(Insecure.SHA1.hash(data: firstPiece))
        pieceHashes.append(Data(Insecure.SHA1.hash(data: secondPiece)))
        try Self.singleFileTorrentData(
            name: "payload.bin",
            length: firstPiece.count + secondPiece.count,
            announce: trackerURL,
            pieceLength: firstPiece.count,
            pieceHashes: pieceHashes
        ).write(to: torrentURL)
        let metainfo = try TorrentMetainfo.parse(url: torrentURL)
        let badPeer = TorrentPeerEndpoint(host: "127.0.0.1", port: 6_881)
        let goodPeer = TorrentPeerEndpoint(host: "127.0.0.2", port: 6_882)
        let badTransport = AppMockPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: metainfo.infoHashV1,
                    peerID: Data((60..<80).map(UInt8.init))
                ).encodedData(),
                try TorrentPeerWireMessage.unchoke.encodedData(),
                try TorrentPeerWireMessage.piece(
                    pieceIndex: 0,
                    begin: 0,
                    block: Data(repeating: 255, count: firstPiece.count)
                ).encodedData()
            ]
        )
        let goodTransport = AppMockPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: metainfo.infoHashV1,
                    peerID: Data((80..<100).map(UInt8.init))
                ).encodedData(),
                try TorrentPeerWireMessage.unchoke.encodedData(),
                try TorrentPeerWireMessage.piece(pieceIndex: 0, begin: 0, block: firstPiece).encodedData(),
                try TorrentPeerWireMessage.piece(pieceIndex: 1, begin: 0, block: secondPiece).encodedData()
            ]
        )
        let transports = [
            badPeer.address: badTransport,
            goodPeer.address: goodTransport
        ]
        let httpTransport = AppMockHTTPTrackerTransport(response: Self.httpTrackerResponse(peers: [badPeer, goodPeer]))
        let adapter = SwiftTorrentEngineAdapter(
            trackerClient: TorrentTrackerClient(
                httpTransport: httpTransport,
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
            ),
            peerTransportFactory: { endpoint in
                guard let transport = transports[endpoint.address] else {
                    throw TorrentPeerWireError.transport("missing mock peer")
                }
                return transport
            },
            dhtTransport: nil,
            dhtBootstrapNodes: []
        )
        await adapter.setSpeedLimit(downloadBytesPerSecond: 4_000, uploadBytesPerSecond: 512)
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
            runtimeOptions: TorrentRuntimeOptions(
                engine: .swift,
                isSequentialDownloadEnabled: false,
                maxConnections: 2,
                seedingLimitMode: .neverStop
            ),
            downloadLimitBytesPerSecond: 10_000,
            uploadLimitBytesPerSecond: 0
        )

        try await adapter.start(request) { snapshot in
            Task {
                await store.append(snapshot)
            }
        }
        let snapshots = try await store.snapshots(count: 6)
        let final = try #require(snapshots.last)
        let savedData = try Data(contentsOf: directory.appendingPathComponent("payload.bin"))

        #expect(snapshots.map(\.status) == [.fetchingPeers, .connectingPeers, .running, .running, .running, .seeding])
        #expect(savedData == firstPiece + secondPiece)
        #expect(final.downloadedBytes == Int64(firstPiece.count + secondPiece.count))
        #expect(final.torrentFiles.allSatisfy { $0.progress == 1 })
        #expect(final.torrentRuntimeOptions?.maxConnections == 2)
        #expect(final.torrentHealth?.peerCount == 2)
        #expect(final.torrentHealth?.connectionCount == 1)
        #expect(final.torrentHealth?.isSequentialDownload == false)
        #expect(final.torrentPeers?.contains {
            $0.address == badPeer.address && $0.flags.contains("bad-piece")
        } == true)
        #expect(final.torrentPeers?.contains {
            $0.address == goodPeer.address && $0.flags.contains("connected")
        } == true)
        #expect(snapshots[3].speedBytesPerSecond <= 4_000)
        #expect(final.torrentConnection?.uploadRate == 512)
        #expect(final.torrentConnection?.shareRatio == 0)
        #expect(final.torrentConnection?.seedingDurationSeconds == 0)
        let announceURLs = await httpTransport.requests.compactMap { $0.url?.absoluteString }
        #expect(announceURLs.contains { $0.contains("event=started") })
        #expect(announceURLs.contains { $0.contains("event=completed") })
        #expect(try TorrentPeerWireMessage.decodeFrame((await badTransport.sentFrames)[2]) == .request(pieceIndex: 0, begin: 0, length: firstPiece.count))
        #expect(try TorrentPeerWireMessage.decodeFrame((await goodTransport.sentFrames)[2]) == .request(pieceIndex: 0, begin: 0, length: firstPiece.count))
        #expect(try TorrentPeerWireMessage.decodeFrame((await goodTransport.sentFrames)[3]) == .request(pieceIndex: 1, begin: 0, length: secondPiece.count))
    }

    @Test("Swift adapter writes multi-file small-piece torrents through a mocked peer")
    func swiftAdapterWritesMultiFileSmallPieceTorrentsThroughMockedPeer() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        let trackerURL = "http://tracker.local/announce"
        let firstFile = Data((0..<5).map(UInt8.init))
        let secondFile = Data((5..<12).map(UInt8.init))
        let contents = firstFile + secondFile
        let pieceLength = 4
        try Self.multiFileTorrentData(
            rootName: "album",
            files: [
                (["a.bin"], firstFile),
                (["b.bin"], secondFile)
            ],
            announce: trackerURL,
            pieceLength: pieceLength
        ).write(to: torrentURL)
        let metainfo = try TorrentMetainfo.parse(url: torrentURL)
        let peerTransport = AppMockPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: metainfo.infoHashV1,
                    peerID: Data((60..<80).map(UInt8.init))
                ).encodedData(),
                try TorrentPeerWireMessage.unchoke.encodedData(),
                try TorrentPeerWireMessage.piece(
                    pieceIndex: 0,
                    begin: 0,
                    block: contents.prefix(pieceLength)
                ).encodedData(),
                try TorrentPeerWireMessage.piece(
                    pieceIndex: 1,
                    begin: 0,
                    block: contents.dropFirst(pieceLength).prefix(pieceLength)
                ).encodedData(),
                try TorrentPeerWireMessage.piece(
                    pieceIndex: 2,
                    begin: 0,
                    block: contents.dropFirst(pieceLength * 2)
                ).encodedData()
            ]
        )
        let httpTransport = AppMockHTTPTrackerTransport(response: Self.httpTrackerResponse())
        let adapter = SwiftTorrentEngineAdapter(
            trackerClient: TorrentTrackerClient(
                httpTransport: httpTransport,
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
            ),
            peerTransportFactory: { _ in peerTransport },
            dhtTransport: nil,
            dhtBootstrapNodes: []
        )
        let store = SnapshotStore()
        let request = TorrentStartRequest(
            id: UUID(),
            displaySource: "file://\(torrentURL.path)",
            resolvedTorrentFilePath: torrentURL.path,
            savePath: directory.path,
            outputName: "album",
            contentRootPath: directory.appendingPathComponent("album").path,
            finalFilePath: nil,
            totalBytes: 0,
            downloadedBytes: 0,
            selectedFileIndexes: [],
            hasExplicitFileSelection: false,
            filePriorities: [:],
            resumeDataPath: directory.appendingPathComponent("fixture.resume.json").path,
            runtimeOptions: TorrentRuntimeOptions(engine: .swift, seedingLimitMode: .stopWhenComplete),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 0
        )

        try await adapter.start(request) { snapshot in
            Task {
                await store.append(snapshot)
            }
        }
        let snapshots = try await store.snapshots(count: 7)
        let completed = try #require(snapshots.last)
        let writtenFirstFile = try Data(contentsOf: directory.appendingPathComponent("album/a.bin"))
        let writtenSecondFile = try Data(contentsOf: directory.appendingPathComponent("album/b.bin"))

        #expect(snapshots.map(\.status) == [.fetchingPeers, .connectingPeers, .running, .running, .running, .running, .completed])
        #expect(writtenFirstFile == firstFile)
        #expect(writtenSecondFile == secondFile)
        #expect(completed.torrentFiles.map(\.progress) == [1, 1])
        #expect(completed.torrentHealth?.hasMetadata == true)
        #expect(completed.torrentHealth?.trackerCount == 1)
    }

    @Test("Swift adapter skips unwanted files and reports selected content totals")
    func swiftAdapterSkipsUnwantedFilesAndReportsSelectedContentTotals() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        let trackerURL = "http://tracker.local/announce"
        let wantedFile = Data([0, 1, 2, 3])
        let skippedFile = Data([4, 5, 6, 7])
        let pieceLength = 4
        try Self.multiFileTorrentData(
            rootName: "album",
            files: [
                (["wanted.bin"], wantedFile),
                (["skipped.bin"], skippedFile)
            ],
            announce: trackerURL,
            pieceLength: pieceLength
        ).write(to: torrentURL)
        let metainfo = try TorrentMetainfo.parse(url: torrentURL)
        let peerTransport = AppMockPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: metainfo.infoHashV1,
                    peerID: Data((60..<80).map(UInt8.init))
                ).encodedData(),
                try TorrentPeerWireMessage.unchoke.encodedData(),
                try TorrentPeerWireMessage.piece(
                    pieceIndex: 0,
                    begin: 0,
                    block: wantedFile
                ).encodedData()
            ]
        )
        let httpTransport = AppMockHTTPTrackerTransport(response: Self.httpTrackerResponse())
        let adapter = SwiftTorrentEngineAdapter(
            trackerClient: TorrentTrackerClient(
                httpTransport: httpTransport,
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
            ),
            peerTransportFactory: { _ in peerTransport },
            dhtTransport: nil,
            dhtBootstrapNodes: []
        )
        let store = SnapshotStore()
        let request = TorrentStartRequest(
            id: UUID(),
            displaySource: "file://\(torrentURL.path)",
            resolvedTorrentFilePath: torrentURL.path,
            savePath: directory.path,
            outputName: "album",
            contentRootPath: directory.appendingPathComponent("album").path,
            finalFilePath: nil,
            totalBytes: 0,
            downloadedBytes: 0,
            selectedFileIndexes: [0],
            hasExplicitFileSelection: true,
            filePriorities: [0: TorrentFilePriority.low.rawValue, 1: TorrentFilePriority.skip.rawValue],
            resumeDataPath: directory.appendingPathComponent("fixture.resume.json").path,
            runtimeOptions: TorrentRuntimeOptions(
                engine: .swift,
                isSequentialDownloadEnabled: true,
                seedingLimitMode: .stopWhenComplete
            ),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 0
        )

        try await adapter.start(request) { snapshot in
            Task {
                await store.append(snapshot)
            }
        }
        let snapshots = try await store.snapshots(untilStatus: .completed)
        let completed = try #require(snapshots.last { $0.status == .completed })
        let savedWantedFile = try Data(contentsOf: directory.appendingPathComponent("album/wanted.bin"))

        #expect(completed.totalBytes == Int64(wantedFile.count))
        #expect(completed.downloadedBytes == Int64(wantedFile.count))
        #expect(savedWantedFile == wantedFile)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("album/skipped.bin").path))
        #expect(completed.torrentFiles.map(\.priorityLevel) == [.low, .skip])
        #expect(completed.torrentFiles.map(\.progress) == [1, 0])
        let sentFrames = await peerTransport.sentFrames
        #expect(sentFrames.count == 3)
        #expect(try TorrentPeerWireMessage.decodeFrame(sentFrames[2]) == .request(pieceIndex: 0, begin: 0, length: pieceLength))
        let announceURLs = await httpTransport.requests.compactMap { $0.url?.absoluteString }
        #expect(announceURLs.contains { $0.contains("left=4") })
        #expect(announceURLs.contains { $0.contains("event=completed") })
    }

    @Test("Swift adapter recheck verifies existing wanted files and saves resume state")
    func swiftAdapterRecheckVerifiesExistingWantedFilesAndSavesResumeState() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        let contents = Data([10, 11, 12, 13])
        let pieceHash = Data(Insecure.SHA1.hash(data: contents))
        try Self.singleFileTorrentData(
            name: "payload.bin",
            length: contents.count,
            announce: nil,
            pieceLength: contents.count,
            pieceHashes: pieceHash
        ).write(to: torrentURL)
        try contents.write(to: directory.appendingPathComponent("payload.bin"))
        let adapter = SwiftTorrentEngineAdapter(
            dhtTransport: nil,
            dhtBootstrapNodes: []
        )
        let store = SnapshotStore()
        let resumeURL = directory.appendingPathComponent("fixture.resume.json")
        let request = TorrentStartRequest(
            id: UUID(),
            displaySource: "file://\(torrentURL.path)",
            resolvedTorrentFilePath: torrentURL.path,
            savePath: directory.path,
            outputName: "payload.bin",
            contentRootPath: directory.path,
            finalFilePath: directory.appendingPathComponent("payload.bin").path,
            totalBytes: Int64(contents.count),
            downloadedBytes: 0,
            selectedFileIndexes: [0],
            hasExplicitFileSelection: true,
            filePriorities: [0: TorrentFilePriority.normal.rawValue],
            resumeDataPath: resumeURL.path,
            runtimeOptions: TorrentRuntimeOptions(engine: .swift),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 0
        )

        await adapter.recheck(request) { snapshot in
            Task {
                await store.append(snapshot)
            }
        }
        let snapshot = try await store.firstSnapshot()
        let metainfo = try TorrentMetainfo.parse(url: torrentURL)
        let layout = try TorrentContentLayout(
            metainfo: metainfo,
            saveDirectory: directory,
            outputName: "payload.bin"
        )
        let resumeState = try TorrentCoreResumeState.decodeJSON(
            Data(contentsOf: resumeURL),
            expectedInfoHashV1Hex: metainfo.infoHashV1Hex,
            expectedLayout: layout
        )

        #expect(snapshot.status == .completed)
        #expect(snapshot.totalBytes == Int64(contents.count))
        #expect(snapshot.downloadedBytes == Int64(contents.count))
        #expect(snapshot.torrentFiles.first?.progress == 1)
        #expect(snapshot.torrentResumeState?.status == .saved)
        #expect(resumeState.completedPieces.completedPieceIndexes == [0])
    }

    @Test("Swift adapter tracks peers from DHT, PEX, and LSD discovery sources")
    func swiftAdapterDHTPEXLSDDiscovery() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        try Self.singleFileTorrentData(
            name: "payload.bin",
            length: 42,
            announce: nil
        ).write(to: torrentURL)

        let dhtTransport = AppMockDHTTransport()
        let bootstrapNode = try TorrentDHTNode(
            id: Data(repeating: 9, count: 20),
            host: "127.0.0.1",
            port: 6881
        )
        
        await dhtTransport.setResponses(
            nodes: [],
            peers: [TorrentPeerEndpoint(host: "192.168.1.5", port: 6889)]
        )

        let adapter = SwiftTorrentEngineAdapter(
            trackerClient: TorrentTrackerClient(
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
            ),
            peerTransportFactory: { _ in
                throw TorrentPeerWireError.transport("peer transport is not exercised by this discovery test")
            },
            dhtTransport: dhtTransport,
            dhtBootstrapNodes: [bootstrapNode],
            peerExchangeProvider: { _, _ in
                [TorrentDiscoveredPeer(endpoint: TorrentPeerEndpoint(host: "10.0.0.5", port: 6882), source: .pex)]
            },
            localServiceDiscoveryProvider: { _, _ in
                [TorrentDiscoveredPeer(endpoint: TorrentPeerEndpoint(host: "192.168.1.100", port: 6883), source: .lsd)]
            }
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
            resumeDataPath: nil,
            runtimeOptions: TorrentRuntimeOptions(
                engine: .swift,
                isDHTEnabled: true,
                isPEXEnabled: true,
                isLSDEnabled: true
            ),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 0
        )

        try await adapter.start(request) { snapshot in
            Task {
                await store.append(snapshot)
            }
        }
        let snapshots = try await store.snapshots(count: 2)
        let last = try #require(snapshots.last)

        #expect(last.torrentHealth?.dhtNodeCount == 1)
        #expect(last.torrentHealth?.dhtPeerCount == 1)
        #expect(last.torrentHealth?.pexPeerCount == 1)
        #expect(last.torrentHealth?.lsdPeerCount == 1)
        #expect(last.torrentConnection?.peerCount == 3)
    }

    @Test("Swift adapter uses runtime DHT bootstrap nodes from settings")
    func swiftAdapterUsesRuntimeDHTBootstrapNodes() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        try Self.singleFileTorrentData(
            name: "payload.bin",
            length: 42,
            announce: nil
        ).write(to: torrentURL)

        let dhtTransport = AppMockDHTTransport()
        await dhtTransport.setResponses(
            nodes: [],
            peers: [TorrentPeerEndpoint(host: "192.168.1.5", port: 6889)]
        )
        let adapter = SwiftTorrentEngineAdapter(
            trackerClient: TorrentTrackerClient(
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
            ),
            peerTransportFactory: { _ in
                throw TorrentPeerWireError.transport("peer transport is not exercised by this discovery test")
            },
            dhtTransport: dhtTransport
        )
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
            runtimeOptions: TorrentRuntimeOptions(
                engine: .swift,
                isDHTEnabled: true,
                isPEXEnabled: false,
                isLSDEnabled: false,
                dhtBootstrapNodes: ["127.0.0.1:6881", "udp://127.0.0.2:6882", "invalid:"]
            ),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 0
        )

        try await adapter.start(request) { _ in }

        let queriedAddresses = await dhtTransport.queriedAddresses()
        #expect(queriedAddresses.contains("127.0.0.1:6881"))
        #expect(queriedAddresses.contains("127.0.0.2:6882"))
        #expect(!queriedAddresses.contains("invalid:0"))
    }

    @Test("Swift adapter respects DHT/PEX/LSD settings toggles and completely gates private torrents")
    func swiftAdapterDiscoveryGatingAndPrivateTorrents() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        
        let publicTorrentURL = directory.appendingPathComponent("public.torrent")
        try Self.singleFileTorrentData(
            name: "payload.bin",
            length: 42,
            announce: nil
        ).write(to: publicTorrentURL)

        let tracker1 = CallTracker()

        let dhtTransport1 = AppMockDHTTransport(onSend: {
            Task { await tracker1.recordDht() }
        })

        let adapter1 = SwiftTorrentEngineAdapter(
            trackerClient: TorrentTrackerClient(
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
            ),
            dhtTransport: dhtTransport1,
            dhtBootstrapNodes: [try TorrentDHTNode(id: Data(repeating: 9, count: 20), host: "127.0.0.1", port: 6881)],
            peerExchangeProvider: { _, _ in
                await tracker1.recordPex()
                return [TorrentDiscoveredPeer(endpoint: TorrentPeerEndpoint(host: "10.0.0.5", port: 6882), source: .pex)]
            },
            localServiceDiscoveryProvider: { _, _ in
                await tracker1.recordLsd()
                return [TorrentDiscoveredPeer(endpoint: TorrentPeerEndpoint(host: "192.168.1.100", port: 6883), source: .lsd)]
            }
        )

        let store1 = SnapshotStore()
        let requestDisabled = TorrentStartRequest(
            id: UUID(),
            displaySource: "file://\(publicTorrentURL.path)",
            resolvedTorrentFilePath: publicTorrentURL.path,
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
            runtimeOptions: TorrentRuntimeOptions(
                engine: .swift,
                isDHTEnabled: false,
                isPEXEnabled: false,
                isLSDEnabled: false
            ),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 0
        )

        try await adapter1.start(requestDisabled) { snapshot in
            Task {
                await store1.append(snapshot)
            }
        }
        let snapshots1 = try await store1.snapshots(count: 1)
        let last1 = try #require(snapshots1.last)

        let dhtQuerySent1 = await tracker1.getDht()
        let pexCalled1 = await tracker1.getPex()
        let lsdCalled1 = await tracker1.getLsd()

        #expect(dhtQuerySent1 == false)
        #expect(pexCalled1 == false)
        #expect(lsdCalled1 == false)
        #expect(last1.torrentConnection?.peerCount == 0)
        #expect(last1.torrentHealth?.dhtPeerCount == 0)
        #expect(last1.torrentHealth?.pexPeerCount == 0)
        #expect(last1.torrentHealth?.lsdPeerCount == 0)

        let privateTorrentURL = directory.appendingPathComponent("private.torrent")
        try Self.singleFilePrivateTorrentData(
            name: "private_payload.bin",
            length: 42,
            announce: nil
        ).write(to: privateTorrentURL)

        let tracker2 = CallTracker()

        let dhtTransport2 = AppMockDHTTransport(onSend: {
            Task { await tracker2.recordDht() }
        })

        let adapter2 = SwiftTorrentEngineAdapter(
            trackerClient: TorrentTrackerClient(
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(50))
            ),
            dhtTransport: dhtTransport2,
            dhtBootstrapNodes: [try TorrentDHTNode(id: Data(repeating: 9, count: 20), host: "127.0.0.1", port: 6881)],
            peerExchangeProvider: { _, _ in
                await tracker2.recordPex()
                return [TorrentDiscoveredPeer(endpoint: TorrentPeerEndpoint(host: "10.0.0.5", port: 6882), source: .pex)]
            },
            localServiceDiscoveryProvider: { _, _ in
                await tracker2.recordLsd()
                return [TorrentDiscoveredPeer(endpoint: TorrentPeerEndpoint(host: "192.168.1.100", port: 6883), source: .lsd)]
            }
        )

        let store2 = SnapshotStore()
        let requestPrivate = TorrentStartRequest(
            id: UUID(),
            displaySource: "file://\(privateTorrentURL.path)",
            resolvedTorrentFilePath: privateTorrentURL.path,
            savePath: directory.path,
            outputName: "private_payload.bin",
            contentRootPath: directory.path,
            finalFilePath: directory.appendingPathComponent("private_payload.bin").path,
            totalBytes: 0,
            downloadedBytes: 0,
            selectedFileIndexes: [],
            hasExplicitFileSelection: false,
            filePriorities: [:],
            resumeDataPath: nil,
            runtimeOptions: TorrentRuntimeOptions(
                engine: .swift,
                isDHTEnabled: true,
                isPEXEnabled: true,
                isLSDEnabled: true
            ),
            downloadLimitBytesPerSecond: 0,
            uploadLimitBytesPerSecond: 0
        )

        try await adapter2.start(requestPrivate) { snapshot in
            Task {
                await store2.append(snapshot)
            }
        }
        let snapshots2 = try await store2.snapshots(count: 1)
        let last2 = try #require(snapshots2.last)

        let dhtQuerySent2 = await tracker2.getDht()
        let pexCalled2 = await tracker2.getPex()
        let lsdCalled2 = await tracker2.getLsd()

        #expect(dhtQuerySent2 == false)
        #expect(pexCalled2 == false)
        #expect(lsdCalled2 == false)
        #expect(last2.torrentConnection?.peerCount == 0)
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
        var data = Data("d".utf8)
        if let announce {
            data.append(bencodeString("announce"))
            data.append(bencodeString(announce))
        }
        data.append(bencodeString("info"))
        data.append(singleFileInfoData(
            name: name,
            length: length,
            pieceLength: pieceLength,
            pieceHashes: pieceHashes ?? Data("aaaaaaaaaaaaaaaaaaaa".utf8)
        ))
        data.append(UInt8(ascii: "e"))
        return data
    }

    private static func singleFileInfoData(
        name: String,
        length: Int,
        pieceLength: Int,
        pieceHashes: Data
    ) -> Data {
        var data = Data("d6:lengthi\(length)e4:name\(name.count):\(name)12:piece lengthi\(pieceLength)e6:pieces\(pieceHashes.count):".utf8)
        data.append(pieceHashes)
        data.append(UInt8(ascii: "e"))
        return data
    }

    private static func multiFileTorrentData(
        rootName: String,
        files: [([String], Data)],
        announce: String,
        pieceLength: Int
    ) -> Data {
        let contents = files.reduce(into: Data()) { partialResult, file in
            partialResult.append(file.1)
        }
        var pieceHashes = Data()
        var offset = 0
        while offset < contents.count {
            let end = min(offset + pieceLength, contents.count)
            pieceHashes.append(Data(Insecure.SHA1.hash(data: contents[offset..<end])))
            offset = end
        }
        let fileEntries = files.map { pathComponents, data in
            bencodeDictionary([
                ("length", bencodeInteger(Int64(data.count))),
                ("path", bencodeList(pathComponents.map(bencodeString)))
            ])
        }
        let info = bencodeDictionary([
            ("files", bencodeList(fileEntries)),
            ("name", bencodeString(rootName)),
            ("piece length", bencodeInteger(Int64(pieceLength))),
            ("pieces", bencodeData(pieceHashes))
        ])
        return bencodeDictionary([
            ("announce", bencodeString(announce)),
            ("info", info)
        ])
    }

    private static func bencodeString(_ value: String) -> Data {
        var data = Data("\(value.utf8.count):".utf8)
        data.append(contentsOf: value.utf8)
        return data
    }

    private static func bencodeData(_ value: Data) -> Data {
        var data = Data("\(value.count):".utf8)
        data.append(value)
        return data
    }

    private static func bencodeInteger(_ value: Int64) -> Data {
        Data("i\(value)e".utf8)
    }

    private static func bencodeList(_ values: [Data]) -> Data {
        var data = Data("l".utf8)
        for value in values {
            data.append(value)
        }
        data.append(UInt8(ascii: "e"))
        return data
    }

    private static func bencodeDictionary(_ fields: [(String, Data)]) -> Data {
        var data = Data("d".utf8)
        for (key, value) in fields.sorted(by: { Array($0.0.utf8).lexicographicallyPrecedes(Array($1.0.utf8)) }) {
            data.append(bencodeString(key))
            data.append(value)
        }
        data.append(UInt8(ascii: "e"))
        return data
    }

    private static func httpTrackerResponse(
        peers: [TorrentPeerEndpoint] = [TorrentPeerEndpoint(host: "127.0.0.1", port: 6_881)]
    ) -> Data {
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
        var compactPeers = Data()
        for peer in peers {
            let octets = peer.host.split(separator: ".").compactMap { UInt8(String($0)) }
            guard octets.count == 4 else { continue }
            compactPeers.append(contentsOf: octets)
            compactPeers.append(UInt8((peer.port >> 8) & 0xff))
            compactPeers.append(UInt8(peer.port & 0xff))
        }
        data.append(Data("\(compactPeers.count):".utf8))
        data.append(compactPeers)
        data.append(UInt8(ascii: "e"))
        return data
    }

    private static func percentEncoded(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func singleFilePrivateTorrentData(
        name: String,
        length: Int,
        announce: String? = nil,
        pieceLength: Int = 16_384,
        pieceHashes: Data? = nil
    ) -> Data {
        var data = Data("d".utf8)
        if let announce {
            data.append(bencodeString(announce))
        }
        data.append(bencodeString("info"))
        data.append(singleFilePrivateInfoData(
            name: name,
            length: length,
            pieceLength: pieceLength,
            pieceHashes: pieceHashes ?? Data("aaaaaaaaaaaaaaaaaaaa".utf8)
        ))
        data.append(UInt8(ascii: "e"))
        return data
    }

    private static func singleFilePrivateInfoData(
        name: String,
        length: Int,
        pieceLength: Int,
        pieceHashes: Data
    ) -> Data {
        var data = Data("d6:lengthi\(length)e4:name\(name.count):\(name)12:piece lengthi\(pieceLength)e6:pieces\(pieceHashes.count):".utf8)
        data.append(pieceHashes)
        data.append(contentsOf: "7:privatei1e".utf8)
        data.append(UInt8(ascii: "e"))
        return data
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

    func snapshots(untilStatus status: DownloadStatus) async throws -> [DownloadSnapshot] {
        for _ in 0..<40 {
            if snapshots.contains(where: { $0.status == status }) {
                return snapshots
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw SnapshotStoreError.missingSnapshot
    }
}

private enum SnapshotStoreError: Error {
    case missingSnapshot
}

private actor CallTracker {
    private var pexCalled = false
    private var lsdCalled = false
    private var dhtCalled = false
    
    func recordPex() { pexCalled = true }
    func recordLsd() { lsdCalled = true }
    func recordDht() { dhtCalled = true }
    
    func getPex() -> Bool { pexCalled }
    func getLsd() -> Bool { lsdCalled }
    func getDht() -> Bool { dhtCalled }
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

private actor AppMockDHTTransport: TorrentDHTTransport {
    private var responsePeers = [TorrentPeerEndpoint]()
    private var responseNodes = [TorrentDHTNode]()
    private var queriedNodeAddresses = [String]()
    private var token = Data([0xaa, 0xbb])
    var onSend: (@Sendable () -> Void)?

    init(onSend: (@Sendable () -> Void)? = nil) {
        self.onSend = onSend
    }

    func setResponses(nodes: [TorrentDHTNode], peers: [TorrentPeerEndpoint]) {
        self.responseNodes = nodes
        self.responsePeers = peers
    }

    func queriedAddresses() -> [String] {
        queriedNodeAddresses
    }

    func send(_ data: Data, to node: TorrentDHTNode, timeout: Duration) async throws -> Data {
        queriedNodeAddresses.append(node.address)
        onSend?()
        guard let value = try? BencodeParser(data: data).parse(),
              case .dictionary(let dict) = value,
              let q = dict[Data("q".utf8)]?.stringValue,
              let t = dict[Data("t".utf8)]?.dataValue
        else {
            throw TorrentDHTError.timeout
        }

        let nodeID = Data(repeating: 9, count: 20)
        if q == "find_node" {
            return try TorrentDHTKRPC.response(
                transactionID: t,
                nodeID: nodeID,
                nodes: responseNodes.isEmpty ? [node] : responseNodes
            )
        } else if q == "get_peers" {
            return try TorrentDHTKRPC.response(
                transactionID: t,
                nodeID: nodeID,
                peers: responsePeers,
                token: token
            )
        } else if q == "announce_peer" {
            return try TorrentDHTKRPC.response(
                transactionID: t,
                nodeID: nodeID
            )
        }
        
        throw TorrentDHTError.timeout
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

private struct DelayedPeerWireResponse: Sendable {
    var data: Data
    var delay: Duration?

    init(data: Data, delay: Duration? = nil) {
        self.data = data
        self.delay = delay
    }
}

private actor AppDelayedPeerWireTransport: TorrentPeerWireTransport {
    private var responses: [DelayedPeerWireResponse]
    private(set) var sentFrames = [Data]()

    init(responses: [DelayedPeerWireResponse]) {
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
        if let delay = next.delay {
            try await Task.sleep(for: delay)
            next.delay = nil
        }
        if next.data.count <= maximumLength {
            return next.data
        }
        let chunk = next.data.prefix(maximumLength)
        next.data.removeFirst(maximumLength)
        responses.insert(next, at: 0)
        return Data(chunk)
    }
}

private actor AppQueuedPeerWireTransportFactory {
    private var transports: [String: [any TorrentPeerWireTransport]]

    init(transports: [String: [any TorrentPeerWireTransport]]) {
        self.transports = transports
    }

    func nextTransport(for endpoint: TorrentPeerEndpoint) throws -> any TorrentPeerWireTransport {
        guard var queue = transports[endpoint.address],
              !queue.isEmpty
        else {
            throw TorrentPeerWireError.transport("missing mock peer")
        }
        let transport = queue.removeFirst()
        transports[endpoint.address] = queue
        return transport
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
    private(set) var runtimeOptionChanges = [TorrentRuntimeOptions]()

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
    func recheck(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async {}
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

    func setRuntimeOptions(id: UUID, options: TorrentRuntimeOptions) async {
        runtimeOptionChanges.append(options)
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

private extension Data {
    var hexEncodedString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension BencodeValue {
    var dataValue: Data? {
        guard case .data(let data) = self else { return nil }
        return data
    }
}
