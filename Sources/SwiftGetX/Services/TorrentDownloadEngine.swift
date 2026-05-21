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

    nonisolated var engineKind: TorrentEngineKind { .swift }
    nonisolated var engineStatus: TorrentEngineStatus { .metadataOnly }

    func start(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws {
        requests[request.id] = request
        onSnapshot(snapshot(for: request, status: .failed))
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
    }

    func recheck(id: UUID) async {}
    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async {}
    func setFileSelection(id: UUID, selectedFileIndexes: [Int]) async {}
    func setFilePriority(id: UUID, fileIndex: Int, priority: Int) async {}
    func setSequentialDownload(id: UUID, enabled: Bool) async {}
    func addTracker(id: UUID, url: String) async {}
    func removeTracker(id: UUID, url: String) async {}
    func forceReannounce(id: UUID) async {}

    func configure(runtimeOptions: TorrentRuntimeOptions) async {
        self.runtimeOptions = runtimeOptions
    }

    private func snapshot(for request: TorrentStartRequest, status: DownloadStatus) -> DownloadSnapshot {
        let metadata = metadataSnapshot(for: request)
        let options = request.runtimeOptions
        let isMagnet = request.displaySource.lowercased().hasPrefix("magnet:")
        let metadataStatus: TorrentMetadataStatus = metadata.files.isEmpty
            ? (isMagnet ? .fetching : .unavailable)
            : .available

        return DownloadSnapshot(
            taskID: request.id,
            status: status,
            totalBytes: metadata.totalBytes > 0 ? metadata.totalBytes : request.totalBytes,
            downloadedBytes: request.downloadedBytes,
            speedBytesPerSecond: 0,
            etaSeconds: nil,
            errorMessage: L10n.string("torrent_swift_engine_runtime_pending"),
            supportsResume: true,
            eTag: nil,
            lastModified: nil,
            torrentFiles: metadata.files,
            connectionSummary: L10n.string("torrent_swift_engine_runtime_pending"),
            torrentMetadataStatus: metadataStatus,
            torrentConnection: TorrentConnectionInfo(
                metadataStatus: metadataStatus,
                engine: .swift,
                engineStatus: .metadataOnly,
                isDHTEnabled: options.isDHTEnabled,
                isPEXEnabled: options.isPEXEnabled,
                isLSDEnabled: options.isLSDEnabled,
                nativeEngineAvailable: false
            ),
            torrentResumeState: request.resumeDataPath.map {
                TorrentResumeState(resumeDataPath: $0, status: .missing)
            },
            torrentTrackers: metadata.trackers,
            torrentPeers: [],
            torrentRuntimeOptions: options,
            torrentHealth: TorrentHealthInfo(
                nativeEngineAvailable: false,
                engine: .swift,
                engineStatus: .metadataOnly,
                hasMetadata: metadataStatus == .available,
                isSequentialDownload: options.isSequentialDownloadEnabled,
                trackerCount: metadata.trackers.count
            )
        )
    }

    private func metadataSnapshot(for request: TorrentStartRequest) -> (
        files: [TorrentFile],
        totalBytes: Int64,
        trackers: [TorrentTrackerInfo]
    ) {
        guard let path = request.resolvedTorrentFilePath,
              let metainfo = try? TorrentMetainfo.parse(url: URL(fileURLWithPath: path))
        else {
            let trackers = MagnetURI.parseTrackers(from: request.displaySource).enumerated().map {
                TorrentTrackerInfo(
                    url: $0.element,
                    tier: $0.offset,
                    status: L10n.string("torrent_tracker_metadata_only")
                )
            }
            return ([], 0, trackers)
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
        let trackers = metainfo.trackerURLs.enumerated().map {
            TorrentTrackerInfo(
                url: $0.element,
                tier: $0.offset,
                status: L10n.string("torrent_tracker_metadata_only")
            )
        }
        return (files, metainfo.totalLength, trackers)
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
