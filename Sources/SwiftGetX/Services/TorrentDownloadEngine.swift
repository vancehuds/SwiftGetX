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
            try await adapter.start(
                torrentRequest(from: request)
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
            try await adapter.resume(
                torrentRequest(from: request),
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
            source: request.source,
            savePath: request.savePath,
            selectedFileIndexes: request.selectedFileIndexes,
            hasExplicitFileSelection: request.hasExplicitFileSelection,
            downloadLimitBytesPerSecond: downloadLimitBytesPerSecond,
            uploadLimitBytesPerSecond: uploadLimitBytesPerSecond,
            stopSeedingAtRatio: stopSeedingAtRatio
        )
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
    let source: String
    let savePath: String
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
                totalBytes: 0,
                downloadedBytes: 0,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: "BT 引擎桥接已预留，需接入 libtorrent 后启用真实磁力/种子下载",
                supportsResume: true,
                eTag: nil,
                lastModified: nil
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
