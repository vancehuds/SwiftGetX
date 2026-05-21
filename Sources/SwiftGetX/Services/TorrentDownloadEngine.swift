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
        await adapter.recheck(id: request.id)
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
    private var runtimeOptions = TorrentRuntimeOptions()
    private var requests: [UUID: TorrentStartRequest] = [:]
    private var trackerSessions: [UUID: SwiftTorrentTrackerSession] = [:]
    private var metadataByID: [UUID: SwiftTorrentMetadataSnapshot] = [:]
    private var snapshotHandlers: [UUID: @Sendable (DownloadSnapshot) -> Void] = [:]
    private let trackerClient: TorrentTrackerClient

    nonisolated var engineKind: TorrentEngineKind { .swift }
    nonisolated var engineStatus: TorrentEngineStatus { .metadataOnly }

    init(
        trackerClient: TorrentTrackerClient = TorrentTrackerClient(
            retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .milliseconds(250))
        )
    ) {
        self.trackerClient = trackerClient
    }

    func start(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws {
        requests[request.id] = request
        snapshotHandlers[request.id] = onSnapshot
        let metadata = metadataSnapshot(for: request)
        metadataByID[request.id] = metadata
        let trackerSession = SwiftTorrentTrackerSession(
            descriptors: metadata.trackerDescriptors,
            client: trackerClient
        )
        trackerSessions[request.id] = trackerSession
        let initialTrackerSummary = SwiftTorrentTrackerAnnounceSummary(
            trackers: await trackerSession.trackerInfos(),
            peers: [],
            successfulTrackerURL: nil
        )
        if !metadata.trackerDescriptors.isEmpty, metadata.infoHashV1 != nil {
            onSnapshot(snapshot(
                for: request,
                status: .fetchingPeers,
                metadata: metadata,
                trackerSummary: initialTrackerSummary
            ))
        }
        let trackerSummary = await announceTrackers(
            for: request,
            metadata: metadata,
            trackerSession: trackerSession
        )
        let finalStatus: DownloadStatus = trackerSummary?.peers.isEmpty == false ? .connectingPeers : .failed
        onSnapshot(snapshot(
            for: request,
            status: finalStatus,
            metadata: metadata,
            trackerSummary: trackerSummary
        ))
    }

    func resume(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws {
        try await start(request, onSnapshot: onSnapshot)
    }

    func pause(id: UUID) async {}
    func cancel(id: UUID) async {}

    func remove(id: UUID, deletingFiles: Bool) async {
        requests[id] = nil
        trackerSessions[id] = nil
        metadataByID[id] = nil
        snapshotHandlers[id] = nil
    }

    func recheck(id: UUID) async {}
    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async {}
    func setFileSelection(id: UUID, selectedFileIndexes: [Int]) async {}
    func setFilePriority(id: UUID, fileIndex: Int, priority: Int) async {}
    func setSequentialDownload(id: UUID, enabled: Bool) async {}

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
            ? await announceTrackers(for: request, metadata: metadata, trackerSession: trackerSession)
            : SwiftTorrentTrackerAnnounceSummary(
                trackers: await trackerSession.trackerInfos(),
                peers: [],
                successfulTrackerURL: nil
            )
        let status: DownloadStatus = trackerSummary?.peers.isEmpty == false ? .connectingPeers : .failed
        onSnapshot(snapshot(
            for: request,
            status: status,
            metadata: metadata,
            trackerSummary: trackerSummary
        ))
    }

    private func snapshot(
        for request: TorrentStartRequest,
        status: DownloadStatus,
        metadata: SwiftTorrentMetadataSnapshot,
        trackerSummary: SwiftTorrentTrackerAnnounceSummary?
    ) -> DownloadSnapshot {
        let options = request.runtimeOptions
        let isMagnet = request.displaySource.lowercased().hasPrefix("magnet:")
        let metadataStatus: TorrentMetadataStatus = metadata.files.isEmpty
            ? (isMagnet ? .fetching : .unavailable)
            : .available
        let trackers = trackerSummary?.trackers ?? metadata.trackers
        let peers = trackerSummary?.peers.map {
            TorrentPeerInfo(
                address: $0.address,
                client: "",
                progress: 0,
                downloadRate: 0,
                uploadRate: 0,
                direction: "tracker",
                flags: "tracker"
            )
        } ?? []

        return DownloadSnapshot(
            taskID: request.id,
            status: status,
            totalBytes: metadata.totalBytes > 0 ? metadata.totalBytes : request.totalBytes,
            downloadedBytes: request.downloadedBytes,
            speedBytesPerSecond: 0,
            etaSeconds: nil,
            errorMessage: errorMessage(for: status, trackerSummary: trackerSummary),
            supportsResume: true,
            eTag: nil,
            lastModified: nil,
            torrentFiles: metadata.files,
            connectionSummary: connectionSummary(for: status, peerCount: peers.count),
            torrentMetadataStatus: metadataStatus,
            torrentConnection: TorrentConnectionInfo(
                metadataStatus: metadataStatus,
                engine: .swift,
                engineStatus: .metadataOnly,
                peerCount: peers.count,
                isDHTEnabled: options.isDHTEnabled,
                isPEXEnabled: options.isPEXEnabled,
                isLSDEnabled: options.isLSDEnabled,
                nativeEngineAvailable: false
            ),
            torrentResumeState: request.resumeDataPath.map {
                TorrentResumeState(resumeDataPath: $0, status: .missing)
            },
            torrentTrackers: trackers,
            torrentPeers: peers,
            torrentRuntimeOptions: options,
            torrentHealth: TorrentHealthInfo(
                nativeEngineAvailable: false,
                engine: .swift,
                engineStatus: .metadataOnly,
                hasMetadata: metadataStatus == .available,
                isSequentialDownload: options.isSequentialDownloadEnabled,
                peerCount: peers.count,
                trackerCount: trackers.count
            )
        )
    }

    private func connectionSummary(for status: DownloadStatus, peerCount: Int) -> String {
        switch status {
        case .fetchingPeers:
            L10n.string("torrent_tracker_fetching_peers")
        case .connectingPeers:
            L10n.string("torrent_tracker_connecting_peers", peerCount)
        default:
            L10n.string("torrent_swift_engine_runtime_pending")
        }
    }

    private func errorMessage(
        for status: DownloadStatus,
        trackerSummary: SwiftTorrentTrackerAnnounceSummary?
    ) -> String? {
        switch status {
        case .fetchingPeers, .connectingPeers:
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
        trackerSession: SwiftTorrentTrackerSession
    ) async -> SwiftTorrentTrackerAnnounceSummary? {
        guard let infoHash = metadata.infoHashV1,
              !metadata.trackerDescriptors.isEmpty
        else {
            return nil
        }
        return await trackerSession.announce(
            infoHash: infoHash,
            left: max(0, metadata.totalBytes - request.downloadedBytes),
            downloaded: max(0, request.downloadedBytes),
            event: request.downloadedBytes > 0 ? .none : .started
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
                infoHashV1: magnet?.infoHashV1
            )
        }

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
        let files = metainfo.files.map { info in
            TorrentFile(
                index: info.index,
                path: info.path,
                size: info.length,
                priority: request.filePriorities[info.index] ?? TorrentFilePriority.normal.rawValue,
                progress: 0
            )
        }
        return SwiftTorrentMetadataSnapshot(
            files: files,
            totalBytes: metainfo.totalLength,
            trackerDescriptors: tiers.enumerated().flatMap { tierIndex, urls in
                urls.map { TorrentTrackerDescriptor(url: $0, tier: tierIndex) }
            },
            trackers: trackers,
            infoHashV1: metainfo.infoHashV1
        )
    }
}

private struct SwiftTorrentMetadataSnapshot: Sendable {
    var files: [TorrentFile]
    var totalBytes: Int64
    var trackerDescriptors: [TorrentTrackerDescriptor]
    var trackers: [TorrentTrackerInfo]
    var infoHashV1: Data?
}

private struct SwiftTorrentTrackerAnnounceSummary: Sendable {
    var trackers: [TorrentTrackerInfo]
    var peers: [TorrentPeerEndpoint]
    var successfulTrackerURL: String?
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
        event: TorrentTrackerEvent
    ) async -> SwiftTorrentTrackerAnnounceSummary {
        let now = Date()
        var peers = [TorrentPeerEndpoint]()
        var successfulTrackerURL: String?

        while let descriptor = scheduler.nextCandidate(now: now) {
            do {
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
                let result = try await client.announce(request)
                scheduler.recordSuccess(url: descriptor.url, result: result, now: now)
                peers = result.peers
                successfulTrackerURL = descriptor.url
                break
            } catch {
                scheduler.recordFailure(url: descriptor.url, error: error, now: now)
            }
        }

        return SwiftTorrentTrackerAnnounceSummary(
            trackers: trackerInfos(),
            peers: peers,
            successfulTrackerURL: successfulTrackerURL
        )
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
    func recheck(id: UUID) async
    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async
    func setFileSelection(id: UUID, selectedFileIndexes: [Int]) async
    func setFilePriority(id: UUID, fileIndex: Int, priority: Int) async
    func setSequentialDownload(id: UUID, enabled: Bool) async
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
    let selectedFileIndexes: [Int]
    let hasExplicitFileSelection: Bool
    let filePriorities: [Int: Int]
    let resumeDataPath: String?
    let runtimeOptions: TorrentRuntimeOptions
    let downloadLimitBytesPerSecond: Int64
    let uploadLimitBytesPerSecond: Int64
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
    func recheck(id: UUID) async {}
    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async {}
    func setFileSelection(id: UUID, selectedFileIndexes: [Int]) async {}
    func setFilePriority(id: UUID, fileIndex: Int, priority: Int) async {}
    func setSequentialDownload(id: UUID, enabled: Bool) async {}
    func addTracker(id: UUID, url: String) async {}
    func removeTracker(id: UUID, url: String) async {}
    func forceReannounce(id: UUID) async {}
    func configure(runtimeOptions: TorrentRuntimeOptions) async {}
}
