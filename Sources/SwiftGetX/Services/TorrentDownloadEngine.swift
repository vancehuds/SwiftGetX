import Foundation

@MainActor
final class TorrentDownloadEngine: DownloadEngine {
    var onSnapshot: (@Sendable (DownloadSnapshot) -> Void)?

    private let adapter: TorrentEngineAdapter
    private var downloadLimitBytesPerSecond: Int64 = 0
    private var uploadLimitBytesPerSecond: Int64 = 0
    private var stopSeedingAtRatio: Double = 1.0

    init(adapter: TorrentEngineAdapter? = nil) {
        if let adapter {
            self.adapter = adapter
        } else {
            #if canImport(CSwiftGetXLibtorrent)
            self.adapter = LibtorrentAdapter() ?? PlaceholderTorrentEngineAdapter()
            #else
            self.adapter = PlaceholderTorrentEngineAdapter()
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

    func configure(stopSeedingAtRatio: Double) {
        self.stopSeedingAtRatio = stopSeedingAtRatio
    }

    private func torrentRequest(from request: DownloadRequest) -> TorrentStartRequest {
        TorrentStartRequest(
            id: request.id,
            displaySource: request.source,
            resolvedTorrentFilePath: request.resolvedTorrentFilePath,
            savePath: request.savePath,
            totalBytes: request.totalBytes,
            downloadedBytes: request.downloadedBytes,
            selectedFileIndexes: request.selectedFileIndexes,
            hasExplicitFileSelection: request.hasExplicitFileSelection,
            downloadLimitBytesPerSecond: downloadLimitBytesPerSecond,
            uploadLimitBytesPerSecond: uploadLimitBytesPerSecond,
            stopSeedingAtRatio: stopSeedingAtRatio
        )
    }

    private func resolvedRequest(from request: DownloadRequest) async throws -> TorrentStartRequest {
        if request.kind == .torrentFile, request.resolvedTorrentFilePath == nil {
            let cachedURL = try await TorrentMetadataService.shared.cachedTorrentFile(for: request.source)
            return TorrentStartRequest(
                id: request.id,
                displaySource: request.source,
                resolvedTorrentFilePath: cachedURL.path,
                savePath: request.savePath,
                totalBytes: request.totalBytes,
                downloadedBytes: request.downloadedBytes,
                selectedFileIndexes: request.selectedFileIndexes,
                hasExplicitFileSelection: request.hasExplicitFileSelection,
                downloadLimitBytesPerSecond: downloadLimitBytesPerSecond,
                uploadLimitBytesPerSecond: uploadLimitBytesPerSecond,
                stopSeedingAtRatio: stopSeedingAtRatio
            )
        }
        return torrentRequest(from: request)
    }
}

protocol TorrentEngineAdapter: Sendable {
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
}

struct TorrentStartRequest: Sendable {
    let id: UUID
    let displaySource: String
    let resolvedTorrentFilePath: String?
    let savePath: String
    let totalBytes: Int64
    let downloadedBytes: Int64
    let selectedFileIndexes: [Int]
    let hasExplicitFileSelection: Bool
    let downloadLimitBytesPerSecond: Int64
    let uploadLimitBytesPerSecond: Int64
    let stopSeedingAtRatio: Double
}

struct PlaceholderTorrentEngineAdapter: TorrentEngineAdapter {
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
                    nativeEngineAvailable: false
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
}
