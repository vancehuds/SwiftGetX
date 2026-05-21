import CryptoKit
import Foundation
import SwiftGetXTorrentCore

@MainActor
final class TorrentDownloadEngine: DownloadEngine {
    var onSnapshot: (@Sendable (DownloadSnapshot) -> Void)?

    private var adapter: TorrentEngineAdapter
    private var downloadLimitBytesPerSecond: Int64 = 0
    private var uploadLimitBytesPerSecond: Int64 = 0
    private var runtimeOptions = TorrentRuntimeOptions()

    init(adapter: TorrentEngineAdapter? = nil) {
        self.adapter = adapter ?? Self.makeAdapter(for: TorrentRuntimeOptions().engine)
    }

    var engineKind: TorrentEngineKind {
        adapter.engineKind
    }

    var engineStatus: TorrentEngineStatus {
        adapter.engineStatus
    }

    private static func makeAdapter(for engine: TorrentEngineKind) -> TorrentEngineAdapter {
        switch engine {
        case .swift:
            SwiftTorrentEngineAdapter()
        case .libtorrent:
            #if canImport(CSwiftGetXLibtorrent)
            LibtorrentAdapter() ?? PlaceholderTorrentEngineAdapter()
            #else
            PlaceholderTorrentEngineAdapter()
            #endif
        }
    }

    func start(_ request: DownloadRequest) async {
        do {
            let torrentRequest = try await resolvedRequest(from: request)
            if let resolvedTorrentFilePath = torrentRequest.resolvedTorrentFilePath,
               resolvedTorrentFilePath != request.resolvedTorrentFilePath {
                onSnapshot?(
                    DownloadSnapshot(
                        taskID: request.id,
                        status: .running,
                        totalBytes: request.totalBytes,
                        downloadedBytes: request.downloadedBytes,
                        speedBytesPerSecond: 0,
                        etaSeconds: nil,
                        errorMessage: nil,
                        supportsResume: true,
                        eTag: nil,
                        lastModified: nil,
                        resolvedTorrentFilePath: resolvedTorrentFilePath
                    )
                )
            }
            try await adapter.start(
                torrentRequest
            ) { snapshot in
                Task { @MainActor in
                    self.onSnapshot?(snapshot)
                }
            }
        } catch {
            onSnapshot?(
                DownloadSnapshot(
                    taskID: request.id,
                    status: .failed,
                    totalBytes: request.totalBytes,
                    downloadedBytes: request.downloadedBytes,
                    speedBytesPerSecond: 0,
                    etaSeconds: nil,
                    errorMessage: error.localizedDescription,
                    supportsResume: true,
                    eTag: nil,
                    lastModified: nil
                )
            )
        }
    }

    func pause(_ request: DownloadRequest) async {
        await adapter.pause(id: request.id)
        onSnapshot?(
            DownloadSnapshot(
                taskID: request.id,
                status: .paused,
                totalBytes: request.totalBytes,
                downloadedBytes: request.downloadedBytes,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: nil,
                supportsResume: true,
                eTag: nil,
                lastModified: nil
            )
        )
    }

    func resume(_ request: DownloadRequest) async {
        do {
            let torrentRequest = try await resolvedRequest(from: request)
            try await adapter.resume(
                torrentRequest,
                onSnapshot: { snapshot in
                    Task { @MainActor in
                        self.onSnapshot?(snapshot)
                    }
                }
            )
        } catch {
            onSnapshot?(
                DownloadSnapshot(
                    taskID: request.id,
                    status: .failed,
                    totalBytes: request.totalBytes,
                    downloadedBytes: request.downloadedBytes,
                    speedBytesPerSecond: 0,
                    etaSeconds: nil,
                    errorMessage: error.localizedDescription,
                    supportsResume: true,
                    eTag: nil,
                    lastModified: nil
                )
            )
        }
    }

    func cancel(_ request: DownloadRequest) async {
        await adapter.cancel(id: request.id)
    }

    func remove(_ request: DownloadRequest, deletingFiles: Bool) async {
        await adapter.remove(id: request.id, deletingFiles: deletingFiles)
    }

    func recheck(_ request: DownloadRequest) async {
        onSnapshot?(
            DownloadSnapshot(
                taskID: request.id,
                status: .verifying,
                totalBytes: request.totalBytes,
                downloadedBytes: request.downloadedBytes,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: nil,
                supportsResume: true,
                eTag: nil,
                lastModified: nil
            )
        )
        do {
            let torrentRequest = try await resolvedRequest(from: request)
            await adapter.recheck(
                torrentRequest,
                onSnapshot: { snapshot in
                    Task { @MainActor in
                        self.onSnapshot?(snapshot)
                    }
                }
            )
        } catch {
            onSnapshot?(
                DownloadSnapshot(
                    taskID: request.id,
                    status: .failed,
                    totalBytes: request.totalBytes,
                    downloadedBytes: request.downloadedBytes,
                    speedBytesPerSecond: 0,
                    etaSeconds: nil,
                    errorMessage: error.localizedDescription,
                    supportsResume: true,
                    eTag: nil,
                    lastModified: nil
                )
            )
        }
    }

    func setFileSelection(_ request: DownloadRequest, selectedFileIndexes: [Int]) async {
        await adapter.setFileSelection(id: request.id, selectedFileIndexes: selectedFileIndexes)
    }

    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async {
        downloadLimitBytesPerSecond = downloadBytesPerSecond
        uploadLimitBytesPerSecond = uploadBytesPerSecond
        await adapter.setSpeedLimit(
            downloadBytesPerSecond: downloadBytesPerSecond,
            uploadBytesPerSecond: uploadBytesPerSecond
        )
    }

    @discardableResult
    func configure(stopSeedingAtRatio: Double) -> Task<Void, Never> {
        runtimeOptions.stopSeedingAtRatio = stopSeedingAtRatio
        let task = Task {
            await adapter.configure(runtimeOptions: runtimeOptions)
        }
        return task
    }

    @discardableResult
    func configure(runtimeOptions: TorrentRuntimeOptions) -> Task<Void, Never> {
        if runtimeOptions.engine != self.runtimeOptions.engine {
            adapter = Self.makeAdapter(for: runtimeOptions.engine)
        }
        self.runtimeOptions = runtimeOptions
        let adapter = adapter
        let downloadLimitBytesPerSecond = self.downloadLimitBytesPerSecond
        let uploadLimitBytesPerSecond = self.uploadLimitBytesPerSecond
        let task = Task {
            await adapter.setSpeedLimit(
                downloadBytesPerSecond: downloadLimitBytesPerSecond,
                uploadBytesPerSecond: uploadLimitBytesPerSecond
            )
            await adapter.configure(runtimeOptions: runtimeOptions)
        }
        return task
    }

    private func torrentRequest(from request: DownloadRequest) -> TorrentStartRequest {
        TorrentStartRequest(
            id: request.id,
            displaySource: request.source,
            resolvedTorrentFilePath: request.resolvedTorrentFilePath,
            savePath: request.torrentSaveDirectoryPath ?? request.savePath,
            outputName: request.torrentOutputName,
            contentRootPath: request.torrentContentRootPath ?? request.savePath,
            finalFilePath: request.torrentFinalFilePath,
            totalBytes: request.totalBytes,
            downloadedBytes: request.downloadedBytes,
            selectedFileIndexes: request.selectedFileIndexes,
            hasExplicitFileSelection: request.hasExplicitFileSelection,
            filePriorities: Dictionary(uniqueKeysWithValues: request.torrentFiles.map { ($0.index, $0.priority) }),
            resumeDataPath: request.torrentResumeState?.resumeDataPath
                ?? TorrentResumeStore.resumeDataPath(for: request.id),
            runtimeOptions: request.torrentRuntimeOptions ?? runtimeOptions,
            downloadLimitBytesPerSecond: downloadLimitBytesPerSecond,
            uploadLimitBytesPerSecond: uploadLimitBytesPerSecond
        )
    }

    private func resolvedRequest(from request: DownloadRequest) async throws -> TorrentStartRequest {
        if request.kind == .torrentFile, request.resolvedTorrentFilePath == nil {
            let cachedURL = try await TorrentMetadataService.shared.cachedTorrentFile(for: request.source)
            return TorrentStartRequest(
                id: request.id,
                displaySource: request.source,
                resolvedTorrentFilePath: cachedURL.path,
                savePath: request.torrentSaveDirectoryPath ?? request.savePath,
                outputName: request.torrentOutputName,
                contentRootPath: request.torrentContentRootPath ?? request.savePath,
                finalFilePath: request.torrentFinalFilePath,
                totalBytes: request.totalBytes,
                downloadedBytes: request.downloadedBytes,
                selectedFileIndexes: request.selectedFileIndexes,
                hasExplicitFileSelection: request.hasExplicitFileSelection,
                filePriorities: Dictionary(uniqueKeysWithValues: request.torrentFiles.map { ($0.index, $0.priority) }),
                resumeDataPath: request.torrentResumeState?.resumeDataPath
                    ?? TorrentResumeStore.resumeDataPath(for: request.id),
                runtimeOptions: request.torrentRuntimeOptions ?? runtimeOptions,
                downloadLimitBytesPerSecond: downloadLimitBytesPerSecond,
                uploadLimitBytesPerSecond: uploadLimitBytesPerSecond
            )
        }
        return torrentRequest(from: request)
    }

    func setTorrentFilePriority(_ request: DownloadRequest, fileIndex: Int, priority: Int) async {
        await adapter.setFilePriority(id: request.id, fileIndex: fileIndex, priority: priority)
    }

    func setTorrentSequentialDownload(_ request: DownloadRequest, enabled: Bool) async {
        await adapter.setSequentialDownload(id: request.id, enabled: enabled)
    }

    func setTorrentRuntimeOptions(_ request: DownloadRequest, options: TorrentRuntimeOptions) async {
        await adapter.setRuntimeOptions(id: request.id, options: options)
    }

    func addTorrentTracker(_ request: DownloadRequest, url: String) async {
        await adapter.addTracker(id: request.id, url: url)
    }

    func removeTorrentTracker(_ request: DownloadRequest, url: String) async {
        await adapter.removeTracker(id: request.id, url: url)
    }

    func forceTorrentReannounce(_ request: DownloadRequest) async {
        await adapter.forceReannounce(id: request.id)
    }
}

actor SwiftTorrentEngineAdapter: TorrentEngineAdapter {
    typealias PeerTransportFactory = @Sendable (TorrentPeerEndpoint) async throws -> any TorrentPeerWireTransport
    typealias PeerDiscoveryProvider = @Sendable (Data, UInt16) async -> [TorrentDiscoveredPeer]

    private var runtimeOptions = TorrentRuntimeOptions()
    private var requests: [UUID: TorrentStartRequest] = [:]
    private var trackerSessions: [UUID: SwiftTorrentTrackerSession] = [:]
    private var metadataByID: [UUID: SwiftTorrentMetadataSnapshot] = [:]
    private var snapshotHandlers: [UUID: @Sendable (DownloadSnapshot) -> Void] = [:]
    private var peerSessions: [UUID: [String: TorrentPeerWireSession]] = [:]
    private var peerWorkspaces: [UUID: TorrentPeerWorkspace] = [:]
    private var swarmStates: [UUID: SwiftTorrentSwarmRuntimeState] = [:]
    private var peerDiscoveryStates: [UUID: SwiftTorrentPeerDiscoveryState] = [:]
    private var seedingTasks: [UUID: Task<Void, Never>] = [:]
    private var seedingContexts: [UUID: SwiftTorrentSeedingContext] = [:]
    private var globalDownloadLimitBytesPerSecond: Int64 = 0
    private var globalUploadLimitBytesPerSecond: Int64 = 0
    private let trackerClient: TorrentTrackerClient
    private let peerTransportFactory: PeerTransportFactory
    private let dhtTransport: (any TorrentDHTTransport)?
    private let injectedDHTBootstrapNodes: [TorrentDHTNode]?
    private let dhtNodeStoreURL: URL?
    private let peerExchangeProvider: PeerDiscoveryProvider
    private let localServiceDiscoveryProvider: PeerDiscoveryProvider

    nonisolated var engineKind: TorrentEngineKind { .swift }
    nonisolated var engineStatus: TorrentEngineStatus { .available }

    init(
        trackerClient: TorrentTrackerClient = TorrentTrackerClient(
            retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(250))
        ),
        peerTransportFactory: @escaping PeerTransportFactory = { endpoint in
            try TorrentPeerWireTCPTransport(endpoint: endpoint, timeoutSeconds: 10)
        },
        dhtTransport: (any TorrentDHTTransport)? = SwiftTorrentEngineAdapter.defaultDHTTransport(),
        dhtBootstrapNodes: [TorrentDHTNode]? = nil,
        dhtNodeStoreURL: URL? = nil,
        peerExchangeProvider: @escaping PeerDiscoveryProvider = { _, _ in [] },
        localServiceDiscoveryProvider: @escaping PeerDiscoveryProvider = { _, _ in [] }
    ) {
        self.trackerClient = trackerClient
        self.peerTransportFactory = peerTransportFactory
        self.dhtTransport = dhtTransport
        self.injectedDHTBootstrapNodes = dhtBootstrapNodes
        self.dhtNodeStoreURL = dhtNodeStoreURL
        self.peerExchangeProvider = peerExchangeProvider
        self.localServiceDiscoveryProvider = localServiceDiscoveryProvider
    }

    private static func defaultDHTTransport() -> (any TorrentDHTTransport)? {
        #if canImport(Network)
        NetworkTorrentDHTTransport()
        #else
        nil
        #endif
    }

    func start(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws {
        requests[request.id] = request
        snapshotHandlers[request.id] = onSnapshot
        seedingTasks[request.id]?.cancel()
        seedingTasks[request.id] = nil
        seedingContexts[request.id] = nil
        var metadata = metadataSnapshot(for: request)
        metadataByID[request.id] = metadata
        let trackerSession = SwiftTorrentTrackerSession(
            descriptors: metadata.trackerDescriptors,
            client: trackerClient
        )
        trackerSessions[request.id] = trackerSession
        let initialTrackerSummary = SwiftTorrentTrackerAnnounceSummary(
            trackers: await trackerSession.trackerInfos(),
            peers: [],
            successfulTrackerURL: nil,
            dhtNodeCount: 0,
            lastDiscoveryError: nil
        )
        let needsMagnetMetadata = request.displaySource.lowercased().hasPrefix("magnet:")
            && metadata.metainfo == nil
            && metadata.infoHashV1 != nil
        if needsMagnetMetadata {
            onSnapshot(snapshot(
                for: request,
                status: .fetchingMetadata,
                metadata: metadata,
                trackerSummary: initialTrackerSummary
            ))
        } else if !metadata.trackerDescriptors.isEmpty, metadata.infoHashV1 != nil {
            onSnapshot(snapshot(
                for: request,
                status: .fetchingPeers,
                metadata: metadata,
                trackerSummary: initialTrackerSummary
            ))
        }
        let initialWantedBytes = wantedTotalBytes(metadata: metadata, request: request)
        let trackerSummary = await announceTrackers(
            for: request,
            metadata: metadata,
            trackerSession: trackerSession,
            event: request.downloadedBytes > 0 ? .none : .started,
            downloaded: request.downloadedBytes,
            left: max(0, initialWantedBytes - request.downloadedBytes)
        ) ?? initialTrackerSummary
        let discoveredTrackerSummary = await discoverPeers(
            for: request,
            metadata: metadata,
            trackerSummary: trackerSummary
        )

        guard !discoveredTrackerSummary.peers.isEmpty else {
            onSnapshot(snapshot(
                for: request,
                status: .failed,
                metadata: metadata,
                trackerSummary: discoveredTrackerSummary
            ))
            return
        }

        if needsMagnetMetadata, let infoHash = metadata.infoHashV1 {
            onSnapshot(snapshot(
                for: request,
                status: .fetchingMetadata,
                metadata: metadata,
                trackerSummary: discoveredTrackerSummary
            ))
            do {
                let metadataFetchTask = Task {
                    try await Self.fetchMagnetMetadataFromPeers(
                        infoHash: infoHash,
                        trackers: metadata.trackerDescriptors.map(\.url),
                        peers: deduplicatedPeers(
                            discoveredTrackerSummary.peers,
                            limit: max(1, request.runtimeOptions.maxConnections)
                        ).map(\.endpoint),
                        peerTransportFactory: peerTransportFactory
                    )
                }
                if await Self.metadataFetchTimedOut(
                    metadataFetchTask,
                    timeoutSeconds: request.runtimeOptions.magnetMetadataTimeoutSeconds
                ) {
                    onSnapshot(snapshot(
                        for: request,
                        status: .fetchingMetadata,
                        metadata: metadata,
                        trackerSummary: discoveredTrackerSummary,
                        errorMessageOverride: TorrentMetadataError.metadataTimeout.localizedDescription
                    ))
                }
                let metainfo = try await metadataFetchTask.value
                metadata = metadataSnapshot(for: request, metainfo: metainfo)
                metadataByID[request.id] = metadata
            } catch {
                onSnapshot(snapshot(
                    for: request,
                    status: .failed,
                    metadata: metadata,
                    trackerSummary: discoveredTrackerSummary,
                    errorMessageOverride: error.localizedDescription
                ))
                return
            }
        }

        onSnapshot(snapshot(
            for: request,
            status: .connectingPeers,
            metadata: metadata,
            trackerSummary: discoveredTrackerSummary
        ))

        guard let metainfo = metadata.metainfo,
              let layout = metadata.layout
        else {
            onSnapshot(snapshot(
                for: request,
                status: .failed,
                metadata: metadata,
                trackerSummary: discoveredTrackerSummary,
                errorMessageOverride: L10n.string("torrent_swift_engine_runtime_pending")
            ))
            return
        }

        do {
            try await downloadTorrent(
                request: request,
                metainfo: metainfo,
                layout: layout,
                metadata: metadata,
                trackerSummary: discoveredTrackerSummary,
                onSnapshot: onSnapshot
            )
        } catch is CancellationError {
            onSnapshot(snapshot(
                for: request,
                status: .paused,
                metadata: metadata,
                trackerSummary: discoveredTrackerSummary,
                downloadedBytes: request.downloadedBytes
            ))
        } catch {
            onSnapshot(snapshot(
                for: request,
                status: .failed,
                metadata: metadata,
                trackerSummary: discoveredTrackerSummary,
                downloadedBytes: request.downloadedBytes,
                errorMessageOverride: error.localizedDescription
            ))
        }
    }

    func resume(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws {
        try await start(request, onSnapshot: onSnapshot)
    }

    func pause(id: UUID) async {
        if let sessions = peerSessions[id] {
            for session in sessions.values {
                _ = try? await session.pause()
            }
        }
        seedingTasks[id]?.cancel()
        seedingTasks[id] = nil
        seedingContexts[id] = nil
        await announceStopped(id: id)
    }

    func cancel(id: UUID) async {
        seedingTasks[id]?.cancel()
        seedingTasks[id] = nil
        seedingContexts[id] = nil
        await announceStopped(id: id)
        peerSessions[id] = nil
    }

    func remove(id: UUID, deletingFiles: Bool) async {
        seedingTasks[id]?.cancel()
        seedingTasks[id] = nil
        seedingContexts[id] = nil
        await announceStopped(id: id)
        if deletingFiles, let workspace = peerWorkspaces[id] {
            try? workspace.deletePartialData()
        }
        requests[id] = nil
        trackerSessions[id] = nil
        metadataByID[id] = nil
        snapshotHandlers[id] = nil
        peerSessions[id] = nil
        peerWorkspaces[id] = nil
        swarmStates[id] = nil
        peerDiscoveryStates[id] = nil
        seedingTasks[id] = nil
        seedingContexts[id] = nil
    }

    func recheck(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async {
        requests[request.id] = request
        var metadata = metadataSnapshot(for: request)
        metadataByID[request.id] = metadata
        guard let metainfo = metadata.metainfo,
              let layout = metadata.layout
        else {
            return
        }
        do {
            let resumeURL = request.resumeDataPath.map(URL.init(fileURLWithPath:))
                ?? layout.saveDirectory.appendingPathComponent(".swiftgetx-\(request.id.uuidString).resume.json")
            let workspace = TorrentPeerWorkspace(
                metainfo: metainfo,
                layout: layout,
                resumeStateURL: resumeURL
            )
            peerWorkspaces[request.id] = workspace
            let wanted = wantedContent(in: layout, metainfo: metainfo, request: request)
            let completedPieces = verifiedPieceIndexes(
                in: wanted.pieceIndexes,
                metainfo: metainfo,
                layout: layout
            )
            let resumeState = try TorrentCoreResumeState(
                infoHashV1Hex: metainfo.infoHashV1Hex,
                pieceCount: metainfo.pieces.count,
                layoutTotalLength: layout.totalLength,
                completedPieceIndexes: completedPieces.sorted(),
                fileChecks: layout.files.map {
                    try TorrentResumeFileCheck(
                        fileIndex: $0.index,
                        path: $0.relativePath,
                        length: $0.length
                    )
                },
                updatedAt: .now
            )
            try workspace.saveResumeState(resumeState)
            let downloadedBytes = completedBytes(in: resumeState, metainfo: metainfo, layout: layout, wantedFiles: wanted.files)
            let status: DownloadStatus = wanted.totalBytes > 0 && downloadedBytes < wanted.totalBytes
                ? .paused
                : .completed
            metadata = metadataSnapshot(for: request, metainfo: metainfo)
            metadataByID[request.id] = metadata
            let discoveryState = peerDiscoveryStates[request.id]
            let trackerInfos: [TorrentTrackerInfo]
            if let trackerSession = trackerSessions[request.id] {
                trackerInfos = await trackerSession.trackerInfos()
            } else {
                trackerInfos = metadata.trackers
            }
            let trackerSummary = SwiftTorrentTrackerAnnounceSummary(
                trackers: trackerInfos,
                peers: discoveryState?.peers ?? [],
                successfulTrackerURL: nil,
                dhtNodeCount: discoveryState?.dhtNodeCount ?? 0,
                lastDiscoveryError: discoveryState?.lastError
            )
            onSnapshot(snapshot(
                for: request,
                status: status,
                metadata: metadata,
                trackerSummary: trackerSummary,
                downloadedBytes: downloadedBytes,
                resumeState: resumeState,
                metainfo: metainfo,
                layout: layout,
                resumeStateStatus: .saved,
                totalBytesOverride: wanted.totalBytes
            ))
        } catch {
            onSnapshot(snapshot(
                for: request,
                status: .failed,
                metadata: metadata,
                trackerSummary: nil,
                errorMessageOverride: error.localizedDescription
            ))
        }
    }
    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async {
        globalDownloadLimitBytesPerSecond = max(0, downloadBytesPerSecond)
        globalUploadLimitBytesPerSecond = max(0, uploadBytesPerSecond)
    }
    func setFileSelection(id: UUID, selectedFileIndexes: [Int]) async {
        guard var request = requests[id] else { return }
        request.selectedFileIndexes = selectedFileIndexes.sorted()
        request.hasExplicitFileSelection = true
        if let metadata = metadataByID[id], !metadata.files.isEmpty {
            let selected = Set(selectedFileIndexes)
            for file in metadata.files {
                request.filePriorities[file.index] = selected.contains(file.index)
                    ? maxWantedPriority(request.filePriorities[file.index])
                    : TorrentFilePriority.skip.rawValue
            }
        }
        requests[id] = request
        refreshMetadata(for: request)
    }

    func setFilePriority(id: UUID, fileIndex: Int, priority: Int) async {
        guard var request = requests[id] else { return }
        request.filePriorities[fileIndex] = priority
        if let metadata = metadataByID[id], !metadata.files.isEmpty {
            request.selectedFileIndexes = metadata.files
                .filter { file in
                    let rawPriority = request.filePriorities[file.index] ?? file.priority
                    return appFilePriority(rawPriority).isWanted
                }
                .map(\.index)
                .sorted()
        } else {
            request.selectedFileIndexes = request.filePriorities
                .filter { appFilePriority($0.value).isWanted }
                .map(\.key)
                .sorted()
        }
        request.hasExplicitFileSelection = true
        requests[id] = request
        refreshMetadata(for: request)
    }

    func setSequentialDownload(id: UUID, enabled: Bool) async {
        guard var request = requests[id] else { return }
        request.runtimeOptions.isSequentialDownloadEnabled = enabled
        requests[id] = request
        if let context = seedingContexts[id] {
            await reevaluateSeedingPolicy(context: context, options: request.runtimeOptions)
        }
    }
    func setRuntimeOptions(id: UUID, options: TorrentRuntimeOptions) async {
        if var request = requests[id] {
            request.runtimeOptions = options
            requests[id] = request
        }
        if let context = seedingContexts[id] {
            await reevaluateSeedingPolicy(context: context, options: options)
        }
    }

    func addTracker(id: UUID, url: String) async {
        guard let session = trackerSessions[id] else { return }
        await session.addTracker(url)
        await emitTrackerSnapshot(id: id, forceAnnounce: true)
    }

    func removeTracker(id: UUID, url: String) async {
        guard let session = trackerSessions[id] else { return }
        await session.removeTracker(url)
        await emitTrackerSnapshot(id: id, forceAnnounce: false)
    }

    func forceReannounce(id: UUID) async {
        await emitTrackerSnapshot(id: id, forceAnnounce: true)
    }

    func configure(runtimeOptions: TorrentRuntimeOptions) async {
        self.runtimeOptions = runtimeOptions
    }

    private func emitTrackerSnapshot(id: UUID, forceAnnounce: Bool) async {
        guard let request = requests[id],
              let metadata = metadataByID[id],
              let trackerSession = trackerSessions[id],
              let onSnapshot = snapshotHandlers[id]
        else {
            return
        }
        let trackerSummary = forceAnnounce
            ? await announceTrackers(
                for: request,
                metadata: metadata,
                trackerSession: trackerSession,
                event: request.downloadedBytes > 0 ? .none : .started,
                downloaded: request.downloadedBytes,
                left: max(0, metadata.totalBytes - request.downloadedBytes),
                force: forceAnnounce
            )
            : SwiftTorrentTrackerAnnounceSummary(
                trackers: await trackerSession.trackerInfos(),
                peers: [],
                successfulTrackerURL: nil,
                dhtNodeCount: peerDiscoveryStates[id]?.dhtNodeCount ?? 0,
                lastDiscoveryError: peerDiscoveryStates[id]?.lastError
            )
        let status: DownloadStatus = trackerSummary?.peers.isEmpty == false ? .connectingPeers : .failed
        onSnapshot(snapshot(
            for: request,
            status: status,
            metadata: metadata,
            trackerSummary: trackerSummary
        ))
    }

    private func discoverPeers(
        for request: TorrentStartRequest,
        metadata: SwiftTorrentMetadataSnapshot,
        trackerSummary: SwiftTorrentTrackerAnnounceSummary
    ) async -> SwiftTorrentTrackerAnnounceSummary {
        guard let infoHash = metadata.infoHashV1 else {
            peerDiscoveryStates[request.id] = SwiftTorrentPeerDiscoveryState(peers: trackerSummary.peers)
            return trackerSummary
        }
        let options = effectiveRuntimeOptions(for: request, metadata: metadata)
        let announcePort = UInt16(6_881)
        var peers = trackerSummary.peers
        var dhtNodeCount = 0
        var lastError: String?

        if options.isDHTEnabled, let dhtTransport {
            let storeURL = dhtNodeStoreURL(for: request)
            let persistedNodes = storeURL.flatMap { try? TorrentDHTNodeStore(url: $0).load() } ?? []
            let bootstrapNodes = persistedNodes + dhtBootstrapNodes(for: request)
            if !bootstrapNodes.isEmpty {
                do {
                    let client = try TorrentDHTClient(
                        timeout: .milliseconds(250),
                        transport: dhtTransport
                    )
                    let discovery = try await client.discoverPeers(
                        infoHash: infoHash,
                        bootstrapNodes: bootstrapNodes,
                        announcePort: announcePort,
                        maxPeers: options.maxConnections
                    )
                    peers.append(contentsOf: discovery.peers)
                    dhtNodeCount = discovery.routingTable.nodes.count
                    lastError = discovery.lastError
                    if let storeURL {
                        try? TorrentDHTNodeStore(url: storeURL).save(discovery.routingTable.nodes)
                    }
                } catch {
                    lastError = error.localizedDescription
                }
            } else if metadata.trackerDescriptors.isEmpty {
                lastError = "DHT is enabled but no bootstrap or persisted nodes are configured."
            }
        }

        if options.isPEXEnabled {
            peers.append(contentsOf: await peerExchangeProvider(infoHash, announcePort))
        }
        if options.isLSDEnabled {
            peers.append(contentsOf: await localServiceDiscoveryProvider(infoHash, announcePort))
        }

        let deduplicated = deduplicatedPeers(peers, limit: max(1, options.maxConnections))
        let discoveryState = SwiftTorrentPeerDiscoveryState(
            peers: deduplicated,
            dhtNodeCount: dhtNodeCount,
            lastError: lastError
        )
        peerDiscoveryStates[request.id] = discoveryState
        return SwiftTorrentTrackerAnnounceSummary(
            trackers: trackerSummary.trackers,
            peers: deduplicated,
            successfulTrackerURL: trackerSummary.successfulTrackerURL,
            dhtNodeCount: dhtNodeCount,
            lastDiscoveryError: lastError
        )
    }

    private func dhtNodeStoreURL(for request: TorrentStartRequest) -> URL? {
        if let dhtNodeStoreURL {
            return dhtNodeStoreURL
        }
        guard let resumeDataPath = request.resumeDataPath else {
            return nil
        }
        return URL(fileURLWithPath: resumeDataPath)
            .deletingPathExtension()
            .appendingPathExtension("dht-nodes.json")
    }

    private func dhtBootstrapNodes(for request: TorrentStartRequest) -> [TorrentDHTNode] {
        if let injectedDHTBootstrapNodes {
            return injectedDHTBootstrapNodes
        }
        return request.runtimeOptions.dhtBootstrapNodes.compactMap(Self.dhtBootstrapNode)
    }

    private static func dhtBootstrapNode(from rawValue: String) -> TorrentDHTNode? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let host: String
        let port: Int
        if let url = URL(string: trimmed),
           let urlHost = url.host,
           let urlPort = url.port
        {
            host = urlHost
            port = urlPort
        } else if let separator = trimmed.lastIndex(of: ":") {
            host = String(trimmed[..<separator])
            port = Int(trimmed[trimmed.index(after: separator)...]) ?? 0
        } else {
            host = trimmed
            port = 6_881
        }

        guard let node = try? TorrentDHTNode(host: host, port: port),
              node.isUsable
        else {
            return nil
        }
        return node
    }

    private func effectiveRuntimeOptions(
        for request: TorrentStartRequest,
        metadata: SwiftTorrentMetadataSnapshot
    ) -> TorrentRuntimeOptions {
        var options = request.runtimeOptions
        if metadata.metainfo?.isPrivate == true {
            options.isDHTEnabled = false
            options.isPEXEnabled = false
            options.isLSDEnabled = false
        }
        return options
    }

    private func downloadTorrent(
        request: TorrentStartRequest,
        metainfo: TorrentMetainfo,
        layout: TorrentContentLayout,
        metadata: SwiftTorrentMetadataSnapshot,
        trackerSummary: SwiftTorrentTrackerAnnounceSummary,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws {
        let peers = deduplicatedPeers(
            trackerSummary.peers,
            limit: max(1, request.runtimeOptions.maxConnections)
        )
        guard !peers.isEmpty else {
            throw TorrentTrackerError.invalidResponse("Peer discovery returned no usable peers.")
        }
        let resumeURL = request.resumeDataPath.map(URL.init(fileURLWithPath:))
            ?? layout.saveDirectory.appendingPathComponent(".swiftgetx-\(request.id.uuidString).resume.json")
        let workspace = TorrentPeerWorkspace(
            metainfo: metainfo,
            layout: layout,
            resumeStateURL: resumeURL
        )
        peerWorkspaces[request.id] = workspace
        peerSessions[request.id] = [:]

        let startDate = Date()
        var resumeState = try workspace.loadResumeState() ?? workspace.makeEmptyResumeState()
        var completedPieceIndexes = Set(resumeState.completedPieces.completedPieceIndexes)
        var peerStates = Dictionary(
            uniqueKeysWithValues: peers.map {
                ($0.endpoint.address, SwiftTorrentPeerRuntimeState(endpoint: $0.endpoint, source: $0.source))
            }
        )
        var activeRequest = requests[request.id] ?? request
        var wanted = wantedContent(in: layout, metainfo: metainfo, request: activeRequest)
        swarmStates[request.id] = SwiftTorrentSwarmRuntimeState(
            peers: Array(peerStates.values),
            downloadedBytes: completedBytes(in: resumeState, metainfo: metainfo, layout: layout, wantedFiles: wanted.files)
        )
        var downloadedBytes = completedBytes(in: resumeState, metainfo: metainfo, layout: layout, wantedFiles: wanted.files)
        onSnapshot(snapshot(
            for: activeRequest,
            status: .running,
            metadata: metadata,
            trackerSummary: trackerSummary,
            downloadedBytes: downloadedBytes,
            peerStates: Array(peerStates.values),
            resumeState: resumeState,
            metainfo: metainfo,
            layout: layout,
            resumeStateStatus: activeRequest.resumeDataPath == nil ? .missing : .loaded,
            totalBytesOverride: wanted.totalBytes
        ))

        let pieceAvailability = pieceAvailabilityMap(
            pieceCount: metainfo.pieces.count,
            peerCount: peers.count
        )
        while true {
            try Task.checkCancellation()
            activeRequest = requests[request.id] ?? activeRequest
            wanted = wantedContent(in: layout, metainfo: metainfo, request: activeRequest)
            guard !wanted.pieceIndexes.isEmpty else { break }
            let orderedPieces = try TorrentPieceSelector.orderedPieceIndexes(
                pieceCount: metainfo.pieces.count,
                completedPieceIndexes: completedPieceIndexes,
                availability: pieceAvailability,
                mode: activeRequest.runtimeOptions.isSequentialDownloadEnabled ? .sequential : .rarestFirst
            )
            guard let pieceIndex = orderedPieces.first(where: { wanted.pieceIndexes.contains($0) }) else {
                break
            }
            let isEndgame = TorrentPieceSelector.isEndgame(
                pieceCount: wanted.pieceIndexes.count,
                completedPieceIndexes: completedPieceIndexes.intersection(wanted.pieceIndexes),
                activePeerCount: max(1, peerStates.values.filter(\.isConnected).count)
            )
            let result = try await downloadPieceFromSwarm(
                pieceIndex: pieceIndex,
                request: activeRequest,
                metainfo: metainfo,
                layout: layout,
                workspace: workspace,
                peerStates: &peerStates,
                isEndgame: isEndgame
            )
            resumeState = result.resumeState
            completedPieceIndexes = Set(resumeState.completedPieces.completedPieceIndexes)
            downloadedBytes = completedBytes(in: resumeState, metainfo: metainfo, layout: layout, wantedFiles: wanted.files)
            let speed = cappedSpeed(
                observedSpeed(
                    downloadedBytes: downloadedBytes,
                    initialDownloadedBytes: activeRequest.downloadedBytes,
                    startDate: startDate
                ),
                limit: effectiveDownloadLimit(for: activeRequest)
            )
            try await throttleIfNeeded(
                downloadedBytes: max(0, downloadedBytes - activeRequest.downloadedBytes),
                startDate: startDate,
                limit: effectiveDownloadLimit(for: activeRequest)
            )
            let remainingBytes = max(0, wanted.totalBytes - downloadedBytes)
            swarmStates[request.id] = SwiftTorrentSwarmRuntimeState(
                peers: Array(peerStates.values),
                downloadedBytes: downloadedBytes
            )
            onSnapshot(snapshot(
                for: activeRequest,
                status: .running,
                metadata: metadata,
                trackerSummary: trackerSummary,
                downloadedBytes: downloadedBytes,
                speedBytesPerSecond: speed,
                etaSeconds: remainingBytes > 0 ? TimeInterval(remainingBytes) / TimeInterval(speed) : nil,
                peerStates: Array(peerStates.values),
                resumeState: resumeState,
                metainfo: metainfo,
                layout: layout,
                resumeStateStatus: activeRequest.resumeDataPath == nil ? .missing : .saved,
                totalBytesOverride: wanted.totalBytes
            ))
        }

        peerSessions[request.id] = nil
        activeRequest = requests[request.id] ?? activeRequest
        wanted = wantedContent(in: layout, metainfo: metainfo, request: activeRequest)
        var completionMetadata = metadata
        completionMetadata.totalBytes = wanted.totalBytes
        let completedTrackerSummary = await announceTrackers(
            for: activeRequest,
            metadata: completionMetadata,
            trackerSession: trackerSessions[request.id],
            event: .completed,
            downloaded: wanted.totalBytes,
            left: 0,
            force: true
        ) ?? trackerSummary
        await completeOrSeedTorrent(
            request: activeRequest,
            metadata: completionMetadata,
            trackerSummary: completedTrackerSummary,
            peerStates: Array(peerStates.values),
            resumeState: resumeState,
            metainfo: metainfo,
            layout: layout,
            onSnapshot: onSnapshot
        )
    }

    private func completeOrSeedTorrent(
        request: TorrentStartRequest,
        metadata: SwiftTorrentMetadataSnapshot,
        trackerSummary: SwiftTorrentTrackerAnnounceSummary,
        peerStates: [SwiftTorrentPeerRuntimeState],
        resumeState: TorrentCoreResumeState,
        metainfo: TorrentMetainfo,
        layout: TorrentContentLayout,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async {
        let options = effectiveRuntimeOptions(for: request, metadata: metadata)
        let seedingStartedAt = Date()
        let uploadRate = effectiveUploadLimit(for: request)
        let initialUploadedBytes: Int64 = 0
        let initialShareRatio = shareRatio(
            uploadedBytes: initialUploadedBytes,
            totalBytes: metadata.totalBytes
        )
        swarmStates[request.id] = SwiftTorrentSwarmRuntimeState(
            peers: peerStates,
            downloadedBytes: metadata.totalBytes,
            uploadedBytes: initialUploadedBytes,
            seedingStartedAt: seedingStartedAt
        )

        if options.shouldStopSeeding(
            isSeeding: true,
            shareRatio: initialShareRatio,
            completed: true,
            seedingDurationSeconds: 0
        ) {
            onSnapshot(snapshot(
                for: request,
                status: .completed,
                metadata: metadata,
                trackerSummary: trackerSummary,
                downloadedBytes: metadata.totalBytes,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                peerStates: peerStates,
                resumeState: resumeState,
                metainfo: metainfo,
                layout: layout,
                resumeStateStatus: request.resumeDataPath == nil ? .missing : .saved,
                uploadRateBytesPerSecond: 0,
                shareRatio: initialShareRatio,
                seedingDurationSeconds: 0
            ))
            return
        }

        onSnapshot(snapshot(
            for: request,
            status: .seeding,
            metadata: metadata,
            trackerSummary: trackerSummary,
            downloadedBytes: metadata.totalBytes,
            speedBytesPerSecond: 0,
            etaSeconds: nil,
            peerStates: peerStates,
            resumeState: resumeState,
            metainfo: metainfo,
            layout: layout,
            resumeStateStatus: request.resumeDataPath == nil ? .missing : .saved,
            uploadRateBytesPerSecond: uploadRate,
            shareRatio: initialShareRatio,
            seedingDurationSeconds: 0
        ))
        seedingContexts[request.id] = SwiftTorrentSeedingContext(
            request: request,
            metadata: metadata,
            trackerSummary: trackerSummary,
            peerStates: peerStates,
            resumeState: resumeState,
            metainfo: metainfo,
            layout: layout,
            seedingStartedAt: seedingStartedAt,
            uploadRateBytesPerSecond: uploadRate,
            onSnapshot: onSnapshot
        )
        scheduleSeedingPolicyTask(
            request: request,
            metadata: metadata,
            trackerSummary: trackerSummary,
            peerStates: peerStates,
            resumeState: resumeState,
            metainfo: metainfo,
            layout: layout,
            seedingStartedAt: seedingStartedAt,
            uploadRateBytesPerSecond: uploadRate,
            onSnapshot: onSnapshot
        )
    }

    private func reevaluateSeedingPolicy(
        context: SwiftTorrentSeedingContext,
        options: TorrentRuntimeOptions
    ) async {
        let elapsed = max(0, Date().timeIntervalSince(context.seedingStartedAt))
        let uploadedBytes = Self.modeledUploadedBytes(
            uploadRateBytesPerSecond: context.uploadRateBytesPerSecond,
            duration: elapsed
        )
        let ratio = shareRatio(
            uploadedBytes: uploadedBytes,
            totalBytes: context.metadata.totalBytes
        )
        if options.shouldStopSeeding(
            isSeeding: true,
            shareRatio: ratio,
            completed: true,
            seedingDurationSeconds: elapsed
        ) {
            await finishSeedingDueToPolicy(
                request: context.request.withRuntimeOptions(options),
                metadata: context.metadata,
                trackerSummary: context.trackerSummary,
                peerStates: context.peerStates,
                resumeState: context.resumeState,
                metainfo: context.metainfo,
                layout: context.layout,
                uploadedBytes: uploadedBytes,
                seedingDurationSeconds: elapsed,
                onSnapshot: context.onSnapshot
            )
            return
        }

        seedingTasks[context.request.id]?.cancel()
        emitSeedingUpdate(
            request: context.request.withRuntimeOptions(options),
            metadata: context.metadata,
            trackerSummary: context.trackerSummary,
            peerStates: context.peerStates,
            resumeState: context.resumeState,
            metainfo: context.metainfo,
            layout: context.layout,
            uploadedBytes: uploadedBytes,
            seedingDurationSeconds: elapsed,
            uploadRateBytesPerSecond: context.uploadRateBytesPerSecond,
            onSnapshot: context.onSnapshot
        )
        scheduleSeedingPolicyTask(
            request: context.request.withRuntimeOptions(options),
            metadata: context.metadata,
            trackerSummary: context.trackerSummary,
            peerStates: context.peerStates,
            resumeState: context.resumeState,
            metainfo: context.metainfo,
            layout: context.layout,
            seedingStartedAt: context.seedingStartedAt,
            uploadRateBytesPerSecond: context.uploadRateBytesPerSecond,
            onSnapshot: context.onSnapshot
        )
    }

    private func scheduleSeedingPolicyTask(
        request: TorrentStartRequest,
        metadata: SwiftTorrentMetadataSnapshot,
        trackerSummary: SwiftTorrentTrackerAnnounceSummary,
        peerStates: [SwiftTorrentPeerRuntimeState],
        resumeState: TorrentCoreResumeState,
        metainfo: TorrentMetainfo,
        layout: TorrentContentLayout,
        seedingStartedAt: Date,
        uploadRateBytesPerSecond: Int64,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) {
        let options = effectiveRuntimeOptions(for: request, metadata: metadata)
        let shouldSchedule: Bool
        switch options.seedingLimitMode {
        case .stopAfterTime:
            shouldSchedule = true
        case .stopAtRatio:
            shouldSchedule = uploadRateBytesPerSecond > 0
                && metadata.totalBytes > 0
                && options.stopSeedingAtRatio > 0
        case .stopWhenComplete, .neverStop:
            shouldSchedule = false
        }
        guard shouldSchedule else {
            seedingTasks[request.id]?.cancel()
            seedingTasks[request.id] = nil
            return
        }

        seedingTasks[request.id]?.cancel()
        seedingTasks[request.id] = Task {
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(seedingStartedAt)
                let uploadedBytes = Self.modeledUploadedBytes(
                    uploadRateBytesPerSecond: uploadRateBytesPerSecond,
                    duration: elapsed
                )
                let ratio = Self.shareRatio(
                    uploadedBytes: uploadedBytes,
                    totalBytes: metadata.totalBytes
                )
                if options.shouldStopSeeding(
                    isSeeding: true,
                    shareRatio: ratio,
                    completed: true,
                    seedingDurationSeconds: elapsed
                ) {
                    await self.finishSeedingDueToPolicy(
                        request: request,
                        metadata: metadata,
                        trackerSummary: trackerSummary,
                        peerStates: peerStates,
                        resumeState: resumeState,
                        metainfo: metainfo,
                        layout: layout,
                        uploadedBytes: uploadedBytes,
                        seedingDurationSeconds: elapsed,
                        onSnapshot: onSnapshot
                    )
                    return
                }

                let sleepSeconds = Self.nextSeedingPolicyWakeInterval(
                    options: options,
                    elapsed: elapsed,
                    uploadRateBytesPerSecond: uploadRateBytesPerSecond,
                    totalBytes: metadata.totalBytes
                )
                do {
                    try await Task.sleep(nanoseconds: Self.nanoseconds(for: sleepSeconds))
                } catch {
                    return
                }

                let updatedElapsed = Date().timeIntervalSince(seedingStartedAt)
                let updatedUploadedBytes = Self.modeledUploadedBytes(
                    uploadRateBytesPerSecond: uploadRateBytesPerSecond,
                    duration: updatedElapsed
                )
                self.emitSeedingUpdate(
                    request: request,
                    metadata: metadata,
                    trackerSummary: trackerSummary,
                    peerStates: peerStates,
                    resumeState: resumeState,
                    metainfo: metainfo,
                    layout: layout,
                    uploadedBytes: updatedUploadedBytes,
                    seedingDurationSeconds: updatedElapsed,
                    uploadRateBytesPerSecond: uploadRateBytesPerSecond,
                    onSnapshot: onSnapshot
                )
            }
        }
    }

    private func emitSeedingUpdate(
        request: TorrentStartRequest,
        metadata: SwiftTorrentMetadataSnapshot,
        trackerSummary: SwiftTorrentTrackerAnnounceSummary,
        peerStates: [SwiftTorrentPeerRuntimeState],
        resumeState: TorrentCoreResumeState,
        metainfo: TorrentMetainfo,
        layout: TorrentContentLayout,
        uploadedBytes: Int64,
        seedingDurationSeconds: TimeInterval,
        uploadRateBytesPerSecond: Int64,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) {
        guard seedingContexts[request.id] != nil else { return }
        let ratio = shareRatio(uploadedBytes: uploadedBytes, totalBytes: metadata.totalBytes)
        swarmStates[request.id] = SwiftTorrentSwarmRuntimeState(
            peers: peerStates,
            downloadedBytes: metadata.totalBytes,
            uploadedBytes: uploadedBytes,
            seedingStartedAt: Date().addingTimeInterval(-seedingDurationSeconds)
        )
        onSnapshot(snapshot(
            for: request,
            status: .seeding,
            metadata: metadata,
            trackerSummary: trackerSummary,
            downloadedBytes: metadata.totalBytes,
            speedBytesPerSecond: 0,
            etaSeconds: nil,
            peerStates: peerStates,
            resumeState: resumeState,
            metainfo: metainfo,
            layout: layout,
            resumeStateStatus: request.resumeDataPath == nil ? .missing : .saved,
            uploadRateBytesPerSecond: uploadRateBytesPerSecond,
            shareRatio: ratio,
            seedingDurationSeconds: seedingDurationSeconds
        ))
    }

    private func finishSeedingDueToPolicy(
        request: TorrentStartRequest,
        metadata: SwiftTorrentMetadataSnapshot,
        trackerSummary: SwiftTorrentTrackerAnnounceSummary,
        peerStates: [SwiftTorrentPeerRuntimeState],
        resumeState: TorrentCoreResumeState,
        metainfo: TorrentMetainfo,
        layout: TorrentContentLayout,
        uploadedBytes: Int64,
        seedingDurationSeconds: TimeInterval,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async {
        seedingTasks[request.id]?.cancel()
        seedingTasks[request.id] = nil
        seedingContexts[request.id] = nil
        let stoppedTrackerSummary = await announceTrackers(
            for: request,
            metadata: metadata,
            trackerSession: trackerSessions[request.id],
            event: .stopped,
            downloaded: metadata.totalBytes,
            left: 0,
            force: true
        ) ?? trackerSummary
        let ratio = shareRatio(uploadedBytes: uploadedBytes, totalBytes: metadata.totalBytes)
        swarmStates[request.id] = SwiftTorrentSwarmRuntimeState(
            peers: peerStates,
            downloadedBytes: metadata.totalBytes,
            uploadedBytes: uploadedBytes,
            seedingStartedAt: Date().addingTimeInterval(-seedingDurationSeconds)
        )
        onSnapshot(snapshot(
            for: request,
            status: .completed,
            metadata: metadata,
            trackerSummary: stoppedTrackerSummary,
            downloadedBytes: metadata.totalBytes,
            speedBytesPerSecond: 0,
            etaSeconds: nil,
            peerStates: peerStates,
            resumeState: resumeState,
            metainfo: metainfo,
            layout: layout,
            resumeStateStatus: request.resumeDataPath == nil ? .missing : .saved,
            uploadRateBytesPerSecond: 0,
            shareRatio: ratio,
            seedingDurationSeconds: seedingDurationSeconds
        ))
    }

    private func downloadPieceFromSwarm(
        pieceIndex: Int,
        request: TorrentStartRequest,
        metainfo: TorrentMetainfo,
        layout: TorrentContentLayout,
        workspace: TorrentPeerWorkspace,
        peerStates: inout [String: SwiftTorrentPeerRuntimeState],
        isEndgame: Bool
    ) async throws -> TorrentPeerDownloadResult {
        let peers = peerStates.values.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.endpoint.address < rhs.endpoint.address
            }
            return lhs.score > rhs.score
        }
        var lastError: Error?

        for peer in peers {
            let address = peer.endpoint.address
            do {
                let session = try await peerSession(
                    for: request.id,
                    endpoint: peer.endpoint,
                    metainfo: metainfo,
                    layout: layout,
                    workspace: workspace
                )
                let startedAt = Date()
                let result = try await session.downloadPiece(pieceIndex)
                let elapsed = max(0.001, Date().timeIntervalSince(startedAt))
                let rate = Int64(Double(result.bytesWritten) / elapsed)
                peerStates[address]?.recordSuccess(
                    bytesDownloaded: result.bytesWritten,
                    rate: rate,
                    isEndgame: isEndgame
                )
                return result
            } catch {
                peerSessions[request.id]?[address] = nil
                peerStates[address]?.recordFailure(error)
                lastError = error
            }
        }

        throw lastError ?? TorrentPeerWireError.transport("No peer could provide piece \(pieceIndex).")
    }

    private func peerSession(
        for requestID: UUID,
        endpoint: TorrentPeerEndpoint,
        metainfo: TorrentMetainfo,
        layout: TorrentContentLayout,
        workspace: TorrentPeerWorkspace
    ) async throws -> TorrentPeerWireSession {
        if let session = peerSessions[requestID]?[endpoint.address] {
            return session
        }
        let transport = try await peerTransportFactory(endpoint)
        let session = TorrentPeerWireSession(
            metainfo: metainfo,
            layout: layout,
            workspace: workspace,
            transport: transport
        )
        var sessions = peerSessions[requestID] ?? [:]
        sessions[endpoint.address] = session
        peerSessions[requestID] = sessions
        return session
    }

    private static func metadataFetchTimedOut(
        _ task: Task<TorrentMetainfo, Error>,
        timeoutSeconds: Int
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                try? await Task.sleep(for: .seconds(max(1, timeoutSeconds)))
                return true
            }
            group.addTask {
                _ = try? await task.value
                return false
            }
            let timedOut = await group.next() ?? false
            group.cancelAll()
            return timedOut
        }
    }

    private static func fetchMagnetMetadataFromPeers(
        infoHash: Data,
        trackers: [String],
        peers: [TorrentPeerEndpoint],
        peerTransportFactory: @escaping PeerTransportFactory
    ) async throws -> TorrentMetainfo {
        var lastError: Error?
        for peer in peers {
            do {
                let transport = try await peerTransportFactory(peer)
                let session = try TorrentMagnetMetadataSession(
                    infoHash: infoHash,
                    trackers: trackers,
                    transport: transport
                )
                return try await session.fetchMetadata()
            } catch {
                lastError = error
            }
        }
        throw lastError ?? TorrentPeerWireError.metadataExtensionUnavailable
    }

    private func deduplicatedPeers(
        _ peers: [TorrentDiscoveredPeer],
        limit: Int
    ) -> [TorrentDiscoveredPeer] {
        var seen = Set<String>()
        return peers.filter {
            $0.endpoint.port > 0
                && $0.endpoint.port <= Int(UInt16.max)
                && !$0.endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && seen.insert($0.endpoint.address).inserted
        }
        .prefix(max(1, limit))
        .map { $0 }
    }

    private func pieceAvailabilityMap(pieceCount: Int, peerCount: Int) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: (0..<pieceCount).map { ($0, max(1, peerCount)) })
    }

    private func refreshMetadata(for request: TorrentStartRequest) {
        guard let metadata = metadataByID[request.id],
              let metainfo = metadata.metainfo
        else { return }
        metadataByID[request.id] = metadataSnapshot(for: request, metainfo: metainfo)
    }

    private func maxWantedPriority(_ priority: Int?) -> Int {
        let current = priority.map(appFilePriority) ?? .normal
        return current.isWanted ? current.rawValue : TorrentFilePriority.normal.rawValue
    }

    private func appFilePriority(_ priority: Int) -> TorrentFilePriority {
        TorrentFilePriority(rawValue: priority) ?? TorrentFilePriority.fromEnginePriority(priority)
    }

    private func wantedTotalBytes(
        metadata: SwiftTorrentMetadataSnapshot,
        request: TorrentStartRequest
    ) -> Int64 {
        guard let metainfo = metadata.metainfo,
              let layout = metadata.layout
        else {
            return metadata.totalBytes > 0 ? metadata.totalBytes : request.totalBytes
        }
        return wantedContent(in: layout, metainfo: metainfo, request: request).totalBytes
    }

    private func wantedContent(
        in layout: TorrentContentLayout,
        metainfo: TorrentMetainfo,
        request: TorrentStartRequest
    ) -> SwiftTorrentWantedContent {
        let explicitWanted = request.hasExplicitFileSelection ? Set(request.selectedFileIndexes) : nil
        let files = layout.files.filter { file in
            if let priority = request.filePriorities[file.index] {
                return appFilePriority(priority).isWanted
            }
            if let explicitWanted {
                return explicitWanted.contains(file.index)
            }
            return file.priority.isWanted
        }
        let ranges = files.map { $0.offset..<$0.endOffset }
        let wantedPieceIndexes = Set(ranges.flatMap { range in
            pieceIndexes(overlapping: range, in: metainfo)
        })
        let totalBytes = files.reduce(Int64(0)) { $0 + $1.length }
        return SwiftTorrentWantedContent(files: files, pieceIndexes: wantedPieceIndexes, totalBytes: totalBytes)
    }

    private func pieceIndexes(overlapping range: Range<Int64>, in metainfo: TorrentMetainfo) -> [Int] {
        guard range.lowerBound < range.upperBound,
              metainfo.pieceLength > 0,
              !metainfo.pieces.isEmpty
        else {
            return []
        }
        let first = max(0, Int(range.lowerBound / metainfo.pieceLength))
        let last = min(
            metainfo.pieces.count - 1,
            Int((range.upperBound - 1) / metainfo.pieceLength)
        )
        guard first <= last else { return [] }
        return Array(first...last)
    }

    private func verifiedPieceIndexes(
        in pieceIndexes: Set<Int>,
        metainfo: TorrentMetainfo,
        layout: TorrentContentLayout
    ) -> Set<Int> {
        let storage = TorrentContentStorage(layout: layout)
        var verified = Set<Int>()
        for pieceIndex in pieceIndexes.sorted() {
            let length = pieceLength(in: metainfo, pieceIndex: pieceIndex)
            guard let data = try? storage.read(
                atGlobalOffset: Int64(pieceIndex) * metainfo.pieceLength,
                length: length
            ) else {
                continue
            }
            if Data(Insecure.SHA1.hash(data: data)) == metainfo.pieces[pieceIndex] {
                verified.insert(pieceIndex)
            }
        }
        return verified
    }

    private func effectiveDownloadLimit(for request: TorrentStartRequest) -> Int64 {
        [globalDownloadLimitBytesPerSecond, request.downloadLimitBytesPerSecond]
            .filter { $0 > 0 }
            .min() ?? 0
    }

    private func effectiveUploadLimit(for request: TorrentStartRequest) -> Int64 {
        [globalUploadLimitBytesPerSecond, request.uploadLimitBytesPerSecond]
            .filter { $0 > 0 }
            .min() ?? 0
    }

    private static func shareRatio(uploadedBytes: Int64, totalBytes: Int64) -> Double {
        guard totalBytes > 0 else { return 0 }
        return max(0, Double(uploadedBytes) / Double(totalBytes))
    }

    private func shareRatio(uploadedBytes: Int64, totalBytes: Int64) -> Double {
        Self.shareRatio(uploadedBytes: uploadedBytes, totalBytes: totalBytes)
    }

    private static func modeledUploadedBytes(
        uploadRateBytesPerSecond: Int64,
        duration: TimeInterval
    ) -> Int64 {
        guard uploadRateBytesPerSecond > 0, duration.isFinite, duration > 0 else {
            return 0
        }
        return Int64(Double(uploadRateBytesPerSecond) * duration)
    }

    private static func nextSeedingPolicyWakeInterval(
        options: TorrentRuntimeOptions,
        elapsed: TimeInterval,
        uploadRateBytesPerSecond: Int64,
        totalBytes: Int64
    ) -> TimeInterval {
        switch options.seedingLimitMode {
        case .stopAfterTime:
            return max(0.05, min(1, options.stopSeedingAfterSeconds - elapsed))
        case .stopAtRatio:
            guard uploadRateBytesPerSecond > 0, totalBytes > 0 else { return 1 }
            let requiredUploadedBytes = Double(totalBytes) * options.stopSeedingAtRatio
            let requiredSeconds = requiredUploadedBytes / Double(uploadRateBytesPerSecond)
            return max(0.05, min(1, requiredSeconds - elapsed))
        case .stopWhenComplete, .neverStop:
            return 1
        }
    }

    private static func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        let clamped = max(0.001, min(seconds, 3600))
        return UInt64(clamped * 1_000_000_000)
    }

    private func observedSpeed(
        downloadedBytes: Int64,
        initialDownloadedBytes: Int64,
        startDate: Date
    ) -> Int64 {
        let elapsed = max(0.001, Date().timeIntervalSince(startDate))
        return max(1, Int64(Double(max(0, downloadedBytes - initialDownloadedBytes)) / elapsed))
    }

    private func cappedSpeed(_ speed: Int64, limit: Int64) -> Int64 {
        guard limit > 0 else { return speed }
        return min(speed, limit)
    }

    private func throttleIfNeeded(
        downloadedBytes: Int64,
        startDate: Date,
        limit: Int64
    ) async throws {
        guard limit > 0, downloadedBytes > 0 else { return }
        let expectedElapsed = Double(downloadedBytes) / Double(limit)
        let currentElapsed = Date().timeIntervalSince(startDate)
        let delay = expectedElapsed - currentElapsed
        guard delay > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    private func torrentFiles(
        metadata: SwiftTorrentMetadataSnapshot,
        metainfo: TorrentMetainfo?,
        layout: TorrentContentLayout?,
        resumeState: TorrentCoreResumeState?
    ) -> [TorrentFile] {
        guard let metainfo, let layout, let resumeState else {
            return metadata.files
        }
        let completedRanges = resumeState.completedPieces.completedPieceIndexes.map { pieceIndex in
            let start = Int64(pieceIndex) * metainfo.pieceLength
            let end = min(start + pieceLength(in: metainfo, pieceIndex: pieceIndex), metainfo.totalLength)
            return start..<end
        }

        return metadata.files.map { file in
            guard let layoutFile = layout.files.first(where: { $0.index == file.index }) else {
                return file
            }
            let completedBytes = completedRanges.reduce(Int64(0)) { total, range in
                let lower = max(range.lowerBound, layoutFile.offset)
                let upper = min(range.upperBound, layoutFile.endOffset)
                return upper > lower ? total + (upper - lower) : total
            }
            let progress = file.size > 0
                ? min(1, max(0, Double(completedBytes) / Double(file.size)))
                : 1
            var updated = file
            updated.progress = progress
            return updated
        }
    }

    private func distributedCopies(
        metainfo: TorrentMetainfo?,
        resumeState: TorrentCoreResumeState?,
        connectedPeerCount: Int
    ) -> Double {
        guard let metainfo, let resumeState, metainfo.pieces.count > 0 else {
            return connectedPeerCount > 0 ? 1 : 0
        }
        let localFraction = Double(resumeState.completedPieces.completedPieceIndexes.count) / Double(metainfo.pieces.count)
        return localFraction + (connectedPeerCount > 0 ? 1 : 0)
    }

    private func announceStopped(id: UUID) async {
        guard let request = requests[id],
              let metadata = metadataByID[id],
              let trackerSession = trackerSessions[id]
        else {
            return
        }
        let downloadedBytes = swarmStates[id]?.downloadedBytes ?? request.downloadedBytes
        _ = await announceTrackers(
            for: request,
            metadata: metadata,
            trackerSession: trackerSession,
            event: .stopped,
            downloaded: downloadedBytes,
            left: max(0, metadata.totalBytes - downloadedBytes),
            force: true
        )
    }

    private func completedBytes(in state: TorrentCoreResumeState, metainfo: TorrentMetainfo) -> Int64 {
        state.completedPieces.completedPieceIndexes.reduce(Int64(0)) { total, pieceIndex in
            total + pieceLength(in: metainfo, pieceIndex: pieceIndex)
        }
    }

    private func completedBytes(
        in state: TorrentCoreResumeState,
        metainfo: TorrentMetainfo,
        layout: TorrentContentLayout,
        wantedFiles: [TorrentContentFile]
    ) -> Int64 {
        guard !wantedFiles.isEmpty else { return 0 }
        let wantedRanges = wantedFiles.map { $0.offset..<$0.endOffset }
        return state.completedPieces.completedPieceIndexes.reduce(Int64(0)) { total, pieceIndex in
            let pieceStart = Int64(pieceIndex) * metainfo.pieceLength
            let pieceEnd = min(pieceStart + pieceLength(in: metainfo, pieceIndex: pieceIndex), layout.totalLength)
            let pieceRange = pieceStart..<pieceEnd
            let wantedBytes = wantedRanges.reduce(Int64(0)) { subtotal, range in
                let lower = max(pieceRange.lowerBound, range.lowerBound)
                let upper = min(pieceRange.upperBound, range.upperBound)
                return upper > lower ? subtotal + (upper - lower) : subtotal
            }
            return total + wantedBytes
        }
    }

    private func pieceLength(in metainfo: TorrentMetainfo, pieceIndex: Int) -> Int64 {
        let start = Int64(pieceIndex) * metainfo.pieceLength
        let remaining = metainfo.totalLength - start
        return min(metainfo.pieceLength, remaining)
    }

    private func snapshot(
        for request: TorrentStartRequest,
        status: DownloadStatus,
        metadata: SwiftTorrentMetadataSnapshot,
        trackerSummary: SwiftTorrentTrackerAnnounceSummary?,
        downloadedBytes: Int64? = nil,
        speedBytesPerSecond: Int64 = 0,
        etaSeconds: TimeInterval? = nil,
        errorMessageOverride: String? = nil,
        peerStates: [SwiftTorrentPeerRuntimeState] = [],
        resumeState: TorrentCoreResumeState? = nil,
        metainfo: TorrentMetainfo? = nil,
        layout: TorrentContentLayout? = nil,
        resumeStateStatus: TorrentResumeState.Status = .missing,
        uploadRateBytesPerSecond: Int64? = nil,
        shareRatio: Double? = nil,
        seedingDurationSeconds: TimeInterval = 0,
        totalBytesOverride: Int64? = nil
    ) -> DownloadSnapshot {
        let options = effectiveRuntimeOptions(for: request, metadata: metadata)
        let isMagnet = request.displaySource.lowercased().hasPrefix("magnet:")
        let metadataStatus: TorrentMetadataStatus = {
            if !metadata.files.isEmpty {
                return .available
            }
            if status == .failed {
                return .failed
            }
            return isMagnet ? .fetching : .unavailable
        }()
        let trackers = trackerSummary?.trackers ?? metadata.trackers
        let discoveryState = peerDiscoveryStates[request.id]
            ?? SwiftTorrentPeerDiscoveryState(peers: trackerSummary?.peers ?? [])
        let peers = !peerStates.isEmpty ? peerStates.map(\.peerInfo).sorted { $0.address < $1.address } : trackerSummary?.peers.map {
            TorrentPeerInfo(
                address: $0.endpoint.address,
                client: "",
                progress: 0,
                downloadRate: 0,
                uploadRate: 0,
                direction: $0.source.rawValue,
                flags: $0.source.rawValue,
                source: $0.source.rawValue
            )
        } ?? []
        let connectionCount = peerStates.filter(\.isConnected).count
        let activeUploadSlots = options.maxUploadSlots < 0
            ? connectionCount
            : min(connectionCount, options.maxUploadSlots)
        let displayedFiles = torrentFiles(
            metadata: metadata,
            metainfo: metainfo,
            layout: layout,
            resumeState: resumeState
        )

        return DownloadSnapshot(
            taskID: request.id,
            status: status,
            totalBytes: totalBytesOverride ?? (metadata.totalBytes > 0 ? metadata.totalBytes : request.totalBytes),
            downloadedBytes: downloadedBytes ?? request.downloadedBytes,
            speedBytesPerSecond: speedBytesPerSecond,
            etaSeconds: etaSeconds,
            errorMessage: errorMessageOverride ?? errorMessage(for: status, trackerSummary: trackerSummary),
            supportsResume: true,
            eTag: nil,
            lastModified: nil,
            torrentFiles: displayedFiles,
            connectionSummary: connectionSummary(for: status, peerCount: peers.count),
            torrentMetadataStatus: metadataStatus,
            torrentConnection: TorrentConnectionInfo(
                metadataStatus: metadataStatus,
                engine: .swift,
                engineStatus: .available,
                peerCount: peers.count,
                downloadRate: speedBytesPerSecond,
                uploadRate: uploadRateBytesPerSecond ?? effectiveUploadLimit(for: request),
                shareRatio: shareRatio ?? 0,
                seedingDurationSeconds: seedingDurationSeconds,
                distributedCopies: distributedCopies(
                    metainfo: metainfo,
                    resumeState: resumeState,
                    connectedPeerCount: connectionCount
                ),
                isDHTEnabled: options.isDHTEnabled,
                isPEXEnabled: options.isPEXEnabled,
                isLSDEnabled: options.isLSDEnabled,
                nativeEngineAvailable: false
            ),
            torrentResumeState: request.resumeDataPath.map {
                TorrentResumeState(resumeDataPath: $0, status: resumeStateStatus, updatedAt: .now)
            },
            torrentTrackers: trackers,
            torrentPeers: peers,
            torrentRuntimeOptions: options,
            torrentHealth: TorrentHealthInfo(
                nativeEngineAvailable: false,
                engine: .swift,
                engineStatus: .available,
                hasMetadata: metadataStatus == .available,
                isSequentialDownload: options.isSequentialDownloadEnabled,
                needsResumeDataSave: status == .running,
                peerCount: peers.count,
                connectionCount: connectionCount,
                uploadSlotCount: activeUploadSlots,
                dhtNodeCount: max(trackerSummary?.dhtNodeCount ?? 0, discoveryState.dhtNodeCount),
                distributedCopies: distributedCopies(
                    metainfo: metainfo,
                    resumeState: resumeState,
                    connectedPeerCount: connectionCount
                ),
                trackerCount: trackers.count,
                trackerPeerCount: discoveryState.count(for: .tracker),
                dhtPeerCount: discoveryState.count(for: .dht),
                pexPeerCount: discoveryState.count(for: .pex),
                lsdPeerCount: discoveryState.count(for: .lsd),
                seedingDurationSeconds: seedingDurationSeconds,
                lastError: trackerSummary?.lastDiscoveryError
            )
        )
    }

    private func connectionSummary(for status: DownloadStatus, peerCount: Int) -> String {
        switch status {
        case .running:
            L10n.string("download_status_running")
        case .fetchingMetadata:
            L10n.string("download_status_fetching_metadata")
        case .fetchingPeers:
            L10n.string("torrent_tracker_fetching_peers")
        case .connectingPeers:
            L10n.string("torrent_tracker_connecting_peers", peerCount)
        case .completed:
            L10n.string("download_status_completed")
        case .seeding:
            L10n.string("download_status_seeding")
        default:
            L10n.string("torrent_swift_engine_runtime_pending")
        }
    }

    private func errorMessage(
        for status: DownloadStatus,
        trackerSummary: SwiftTorrentTrackerAnnounceSummary?
    ) -> String? {
        switch status {
        case .fetchingMetadata, .fetchingPeers, .connectingPeers, .running, .seeding, .completed:
            nil
        case .failed where trackerSummary?.successfulTrackerURL == nil && trackerSummary != nil:
            L10n.string("torrent_tracker_no_peers")
        default:
            L10n.string("torrent_swift_engine_runtime_pending")
        }
    }

    private func announceTrackers(
        for request: TorrentStartRequest,
        metadata: SwiftTorrentMetadataSnapshot,
        trackerSession: SwiftTorrentTrackerSession?,
        event: TorrentTrackerEvent,
        downloaded: Int64,
        left: Int64,
        force: Bool = false
    ) async -> SwiftTorrentTrackerAnnounceSummary? {
        guard let trackerSession else { return nil }
        guard let infoHash = metadata.infoHashV1,
              !metadata.trackerDescriptors.isEmpty
        else {
            return nil
        }
        return await trackerSession.announce(
            infoHash: infoHash,
            left: max(0, left),
            downloaded: max(0, downloaded),
            event: event,
            force: force
        )
    }

    private func metadataSnapshot(for request: TorrentStartRequest) -> SwiftTorrentMetadataSnapshot {
        guard let path = request.resolvedTorrentFilePath,
              let metainfo = try? TorrentMetainfo.parse(url: URL(fileURLWithPath: path))
        else {
            let magnet = try? MagnetURI.parse(request.displaySource)
            let trackers = (magnet?.trackers ?? MagnetURI.parseTrackers(from: request.displaySource))
            return SwiftTorrentMetadataSnapshot(
                files: [],
                totalBytes: magnet?.exactLength ?? 0,
                trackerDescriptors: trackers.enumerated().map {
                    TorrentTrackerDescriptor(url: $0.element, tier: $0.offset)
                },
                trackers: trackers.enumerated().map {
                    TorrentTrackerInfo(
                        url: $0.element,
                        tier: $0.offset,
                        status: TorrentTrackerScheduleState.Status.waiting.title
                    )
                },
                infoHashV1: magnet?.infoHashV1,
                metainfo: nil,
                layout: nil
            )
        }

        return metadataSnapshot(for: request, metainfo: metainfo)
    }

    private func metadataSnapshot(
        for request: TorrentStartRequest,
        metainfo: TorrentMetainfo
    ) -> SwiftTorrentMetadataSnapshot {
        let tiers = !metainfo.announceList.isEmpty
            ? metainfo.announceList
            : metainfo.announce.map { [[$0]] } ?? []
        let trackers = tiers.enumerated().flatMap { tierIndex, urls in
            urls.map {
                TorrentTrackerInfo(
                    url: $0,
                    tier: tierIndex,
                    status: TorrentTrackerScheduleState.Status.waiting.title
                )
            }
        }
        let layout = try? TorrentContentLayout(
            metainfo: metainfo,
            saveDirectory: URL(fileURLWithPath: request.savePath, isDirectory: true),
            outputName: request.outputName,
            priorities: Dictionary(uniqueKeysWithValues: request.filePriorities.map {
                ($0.key, TorrentContentPriority(rawValue: appFilePriority($0.value).rawValue) ?? .normal)
            })
        )
        let files = (layout?.files.map {
            TorrentFile(
                index: $0.index,
                path: $0.relativePath,
                size: $0.length,
                priority: request.filePriorities[$0.index].map { appFilePriority($0).rawValue }
                    ?? TorrentFilePriority.normal.rawValue,
                progress: 0
            )
        } ?? metainfo.files.map { info in
            TorrentFile(
                index: info.index,
                path: info.path,
                size: info.length,
                priority: request.filePriorities[info.index].map { appFilePriority($0).rawValue }
                    ?? TorrentFilePriority.normal.rawValue,
                progress: 0
            )
        })
        return SwiftTorrentMetadataSnapshot(
            files: files,
            totalBytes: metainfo.totalLength,
            trackerDescriptors: tiers.enumerated().flatMap { tierIndex, urls in
                urls.map { TorrentTrackerDescriptor(url: $0, tier: tierIndex) }
            },
            trackers: trackers,
            infoHashV1: metainfo.infoHashV1,
            metainfo: metainfo,
            layout: layout
        )
    }
}

private struct SwiftTorrentMetadataSnapshot: Sendable {
    var files: [TorrentFile]
    var totalBytes: Int64
    var trackerDescriptors: [TorrentTrackerDescriptor]
    var trackers: [TorrentTrackerInfo]
    var infoHashV1: Data?
    var metainfo: TorrentMetainfo?
    var layout: TorrentContentLayout?
}

private struct SwiftTorrentWantedContent: Sendable {
    var files: [TorrentContentFile]
    var pieceIndexes: Set<Int>
    var totalBytes: Int64
}

private struct SwiftTorrentSwarmRuntimeState: Sendable {
    var peers: [SwiftTorrentPeerRuntimeState]
    var downloadedBytes: Int64
    var uploadedBytes: Int64 = 0
    var seedingStartedAt: Date? = nil
}

private struct SwiftTorrentSeedingContext: Sendable {
    var request: TorrentStartRequest
    var metadata: SwiftTorrentMetadataSnapshot
    var trackerSummary: SwiftTorrentTrackerAnnounceSummary
    var peerStates: [SwiftTorrentPeerRuntimeState]
    var resumeState: TorrentCoreResumeState
    var metainfo: TorrentMetainfo
    var layout: TorrentContentLayout
    var seedingStartedAt: Date
    var uploadRateBytesPerSecond: Int64
    var onSnapshot: @Sendable (DownloadSnapshot) -> Void
}

private struct SwiftTorrentPeerDiscoveryState: Sendable {
    var peers: [TorrentDiscoveredPeer]
    var dhtNodeCount: Int
    var lastError: String?

    init(
        peers: [TorrentDiscoveredPeer] = [],
        dhtNodeCount: Int = 0,
        lastError: String? = nil
    ) {
        self.peers = peers
        self.dhtNodeCount = max(0, dhtNodeCount)
        self.lastError = lastError
    }

    func count(for source: TorrentPeerDiscoverySource) -> Int {
        peers.filter { $0.source == source }.count
    }
}

private struct SwiftTorrentPeerRuntimeState: Sendable {
    var endpoint: TorrentPeerEndpoint
    var source: TorrentPeerDiscoverySource = .tracker
    var score: Int = 0
    var bytesDownloaded: Int64 = 0
    var lastDownloadRate: Int64 = 0
    var failures: Int = 0
    var timeouts: Int = 0
    var badPieces: Int = 0
    var protocolErrors: Int = 0
    var duplicateBlocks: Int = 0
    var isConnected: Bool = false
    var isEndgame: Bool = false
    var lastError: String?

    var peerInfo: TorrentPeerInfo {
        TorrentPeerInfo(
            address: endpoint.address,
            client: endpoint.peerID ?? "",
            progress: bytesDownloaded > 0 ? 1 : 0,
            downloadRate: lastDownloadRate,
            uploadRate: 0,
            direction: "down",
            flags: flags,
            source: source.rawValue
        )
    }

    mutating func recordSuccess(bytesDownloaded: Int64, rate: Int64, isEndgame: Bool) {
        self.bytesDownloaded += max(0, bytesDownloaded)
        lastDownloadRate = max(0, rate)
        score += 10
        isConnected = true
        self.isEndgame = isEndgame
        lastError = nil
    }

    mutating func recordFailure(_ error: Error) {
        failures += 1
        isConnected = false
        lastDownloadRate = 0
        lastError = error.localizedDescription
        switch error {
        case TorrentPeerWireError.timeout:
            timeouts += 1
            score -= 20
        case TorrentPeerWireError.invalidPieceHash:
            badPieces += 1
            score -= 50
        case TorrentPeerWireError.invalidMessage,
             TorrentPeerWireError.invalidMessageLength,
             TorrentPeerWireError.invalidHandshakeProtocol,
             TorrentPeerWireError.invalidHandshakeLength,
             TorrentPeerWireError.invalidHandshakeInfoHash,
             TorrentPeerWireError.invalidBlockLength,
             TorrentPeerWireError.invalidPieceIndex:
            protocolErrors += 1
            score -= 30
        default:
            score -= 10
        }
    }

    private var flags: String {
        var values = [source.rawValue]
        values.append(isConnected ? "connected" : "disconnected")
        if isEndgame {
            values.append("endgame")
        }
        if timeouts > 0 {
            values.append("timeout")
        }
        if badPieces > 0 {
            values.append("bad-piece")
        }
        if protocolErrors > 0 {
            values.append("protocol-error")
        }
        if failures > 0 {
            values.append("score=\(score)")
        }
        return values.joined(separator: ",")
    }
}

private struct SwiftTorrentTrackerAnnounceSummary: Sendable {
    var trackers: [TorrentTrackerInfo]
    var peers: [TorrentDiscoveredPeer]
    var successfulTrackerURL: String?
    var dhtNodeCount: Int
    var lastDiscoveryError: String?
}

private actor SwiftTorrentTrackerSession {
    private static let peerID = Data("-SGX0001-00000000000".utf8)

    private var scheduler: TorrentTrackerScheduler
    private let client: TorrentTrackerClient

    init(descriptors: [TorrentTrackerDescriptor], client: TorrentTrackerClient) {
        scheduler = TorrentTrackerScheduler(trackers: descriptors, baseBackoffSeconds: 5)
        self.client = client
    }

    func trackerInfos() -> [TorrentTrackerInfo] {
        scheduler.states.map(\.trackerInfo)
    }

    func addTracker(_ url: String) {
        let tier = (scheduler.states.map(\.descriptor.tier).min() ?? 0)
        scheduler.add(TorrentTrackerDescriptor(url: url, tier: tier))
    }

    func removeTracker(_ url: String) {
        scheduler.remove(url: url)
    }

    func announce(
        infoHash: Data,
        left: Int64,
        downloaded: Int64,
        event: TorrentTrackerEvent,
        force: Bool = false
    ) async -> SwiftTorrentTrackerAnnounceSummary {
        let now = Date()
        var peers = [TorrentDiscoveredPeer]()
        var successfulTrackerURL: String?

        if force {
            for descriptor in forcedCandidates() {
                do {
                    let result = try await announce(
                        descriptor: descriptor,
                        infoHash: infoHash,
                        left: left,
                        downloaded: downloaded,
                        event: event
                    )
                    scheduler.recordSuccess(url: descriptor.url, result: result, now: now)
                    peers = result.peers.map { TorrentDiscoveredPeer(endpoint: $0, source: .tracker) }
                    successfulTrackerURL = descriptor.url
                    break
                } catch {
                    scheduler.recordFailure(url: descriptor.url, error: error, now: now)
                }
            }
            return SwiftTorrentTrackerAnnounceSummary(
                trackers: trackerInfos(),
                peers: peers,
                successfulTrackerURL: successfulTrackerURL,
                dhtNodeCount: 0,
                lastDiscoveryError: nil
            )
        }

        while let descriptor = scheduler.nextCandidate(now: now) {
            do {
                let result = try await announce(
                    descriptor: descriptor,
                    infoHash: infoHash,
                    left: left,
                    downloaded: downloaded,
                    event: event
                )
                scheduler.recordSuccess(url: descriptor.url, result: result, now: now)
                peers = result.peers.map { TorrentDiscoveredPeer(endpoint: $0, source: .tracker) }
                successfulTrackerURL = descriptor.url
                break
            } catch {
                scheduler.recordFailure(url: descriptor.url, error: error, now: now)
            }
        }

        return SwiftTorrentTrackerAnnounceSummary(
            trackers: trackerInfos(),
            peers: peers,
            successfulTrackerURL: successfulTrackerURL,
            dhtNodeCount: 0,
            lastDiscoveryError: nil
        )
    }

    private func announce(
        descriptor: TorrentTrackerDescriptor,
        infoHash: Data,
        left: Int64,
        downloaded: Int64,
        event: TorrentTrackerEvent
    ) async throws -> TorrentTrackerAnnounceResult {
        guard let url = URL(string: descriptor.url) else {
            throw TorrentTrackerError.invalidRequest("Invalid tracker URL.")
        }
        let request = try TorrentTrackerAnnounceRequest(
            trackerURL: url,
            infoHash: infoHash,
            peerID: Self.peerID,
            downloaded: downloaded,
            left: left,
            event: event
        )
        return try await client.announce(request)
    }

    private func forcedCandidates() -> [TorrentTrackerDescriptor] {
        scheduler.states.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .working
            }
            if lhs.descriptor.tier != rhs.descriptor.tier {
                return lhs.descriptor.tier < rhs.descriptor.tier
            }
            return lhs.descriptor.url < rhs.descriptor.url
        }
        .map(\.descriptor)
    }
}

private extension TorrentTrackerScheduleState {
    var trackerInfo: TorrentTrackerInfo {
        TorrentTrackerInfo(
            url: descriptor.url,
            tier: descriptor.tier,
            status: status.title,
            seedCount: seedCount,
            leecherCount: leecherCount,
            downloadedCount: downloadedCount,
            lastAnnounce: lastAnnounceDate.map(Self.timestamp) ?? "",
            nextAnnounce: nextAnnounceDate.map(Self.timestamp) ?? "",
            errorMessage: lastError
        )
    }

    private static func timestamp(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }
}

private extension TorrentTrackerScheduleState.Status {
    var title: String {
        switch self {
        case .waiting:
            L10n.string("torrent_tracker_waiting")
        case .announcing:
            L10n.string("torrent_tracker_announcing")
        case .working:
            L10n.string("torrent_tracker_working")
        case .failed:
            L10n.string("torrent_tracker_failed")
        }
    }
}

protocol TorrentEngineAdapter: Sendable {
    var engineKind: TorrentEngineKind { get }
    var engineStatus: TorrentEngineStatus { get }

    func start(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws
    func resume(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws
    func pause(id: UUID) async
    func cancel(id: UUID) async
    func remove(id: UUID, deletingFiles: Bool) async
    func recheck(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async
    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async
    func setFileSelection(id: UUID, selectedFileIndexes: [Int]) async
    func setFilePriority(id: UUID, fileIndex: Int, priority: Int) async
    func setSequentialDownload(id: UUID, enabled: Bool) async
    func setRuntimeOptions(id: UUID, options: TorrentRuntimeOptions) async
    func addTracker(id: UUID, url: String) async
    func removeTracker(id: UUID, url: String) async
    func forceReannounce(id: UUID) async
    func configure(runtimeOptions: TorrentRuntimeOptions) async
}

struct TorrentStartRequest: Sendable {
    let id: UUID
    let displaySource: String
    let resolvedTorrentFilePath: String?
    let savePath: String
    let outputName: String?
    let contentRootPath: String
    let finalFilePath: String?
    let totalBytes: Int64
    let downloadedBytes: Int64
    var selectedFileIndexes: [Int]
    var hasExplicitFileSelection: Bool
    var filePriorities: [Int: Int]
    let resumeDataPath: String?
    var runtimeOptions: TorrentRuntimeOptions
    let downloadLimitBytesPerSecond: Int64
    let uploadLimitBytesPerSecond: Int64
}

private extension TorrentStartRequest {
    func withRuntimeOptions(_ options: TorrentRuntimeOptions) -> TorrentStartRequest {
        var copy = self
        copy.runtimeOptions = options
        return copy
    }
}

struct PlaceholderTorrentEngineAdapter: TorrentEngineAdapter {
    let engineKind: TorrentEngineKind = .libtorrent
    let engineStatus: TorrentEngineStatus = .unavailable

    func start(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws {
        onSnapshot(
            DownloadSnapshot(
                taskID: request.id,
                status: .failed,
                totalBytes: request.totalBytes,
                downloadedBytes: request.downloadedBytes,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: L10n.string("error_libtorrent_unavailable"),
                supportsResume: true,
                eTag: nil,
                lastModified: nil,
                torrentFiles: [],
                torrentMetadataStatus: .unavailable,
                torrentConnection: TorrentConnectionInfo(
                    metadataStatus: .unavailable,
                    engine: .libtorrent,
                    engineStatus: .unavailable,
                    nativeEngineAvailable: false
                ),
                torrentResumeState: request.resumeDataPath.map {
                    TorrentResumeState(resumeDataPath: $0, status: .missing)
                },
                torrentTrackers: [],
                torrentPeers: [],
                torrentRuntimeOptions: request.runtimeOptions,
                torrentHealth: TorrentHealthInfo(
                    nativeEngineAvailable: false,
                    engine: .libtorrent,
                    engineStatus: .unavailable
                )
            )
        )
    }

    func resume(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws {
        try await start(request, onSnapshot: onSnapshot)
    }

    func pause(id: UUID) async {}
    func cancel(id: UUID) async {}
    func remove(id: UUID, deletingFiles: Bool) async {}
    func recheck(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async {}
    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async {}
    func setFileSelection(id: UUID, selectedFileIndexes: [Int]) async {}
    func setFilePriority(id: UUID, fileIndex: Int, priority: Int) async {}
    func setSequentialDownload(id: UUID, enabled: Bool) async {}
    func setRuntimeOptions(id: UUID, options: TorrentRuntimeOptions) async {}
    func addTracker(id: UUID, url: String) async {}
    func removeTracker(id: UUID, url: String) async {}
    func forceReannounce(id: UUID) async {}
    func configure(runtimeOptions: TorrentRuntimeOptions) async {}
}
