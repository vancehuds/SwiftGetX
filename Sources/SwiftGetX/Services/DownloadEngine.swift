import Foundation

@MainActor
protocol DownloadEngine: AnyObject {
    func start(_ request: DownloadRequest) async
    func pause(_ request: DownloadRequest) async
    func resume(_ request: DownloadRequest) async
    func cancel(_ request: DownloadRequest) async
    func remove(_ request: DownloadRequest, deletingFiles: Bool) async
    func recheck(_ request: DownloadRequest) async
    func setFileSelection(_ request: DownloadRequest, selectedFileIndexes: [Int]) async
    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async
}

struct DownloadRequest: Sendable {
    let id: UUID
    let name: String
    let source: String
    let resolvedTorrentFilePath: String?
    let kind: DownloadKind
    let status: DownloadStatus
    let savePath: String
    let totalBytes: Int64
    let downloadedBytes: Int64
    let supportsResume: Bool
    let eTag: String?
    let lastModified: String?
    let selectedFileIndexes: [Int]
    let hasExplicitFileSelection: Bool

    init(
        id: UUID,
        name: String,
        source: String,
        resolvedTorrentFilePath: String? = nil,
        kind: DownloadKind,
        status: DownloadStatus = .queued,
        savePath: String,
        totalBytes: Int64,
        downloadedBytes: Int64,
        supportsResume: Bool,
        eTag: String?,
        lastModified: String?,
        selectedFileIndexes: [Int],
        hasExplicitFileSelection: Bool = false
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.resolvedTorrentFilePath = resolvedTorrentFilePath
        self.kind = kind
        self.status = status
        self.savePath = savePath
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.supportsResume = supportsResume
        self.eTag = eTag
        self.lastModified = lastModified
        self.selectedFileIndexes = selectedFileIndexes
        self.hasExplicitFileSelection = hasExplicitFileSelection
    }

    init(task: DownloadTask) {
        id = task.id
        name = task.name
        source = task.source
        resolvedTorrentFilePath = task.resolvedTorrentFilePath
        kind = task.kind
        status = task.status
        savePath = task.savePath
        totalBytes = task.totalBytes
        downloadedBytes = task.downloadedBytes
        supportsResume = task.supportsResume
        eTag = task.eTag
        lastModified = task.lastModified
        selectedFileIndexes = task.selectedFileIndexes
        hasExplicitFileSelection = task.kind == .torrentMagnet || task.kind == .torrentFile
            ? !task.torrentFiles.isEmpty
            : false
    }
}
