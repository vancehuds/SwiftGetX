import Foundation
import SwiftGetXCore

@MainActor
protocol DownloadEngine: AnyObject {
    func start(_ request: DownloadRequest) async
    func pause(_ request: DownloadRequest) async
    func resume(_ request: DownloadRequest) async
    func cancel(_ request: DownloadRequest) async
    func remove(_ request: DownloadRequest, deletingFiles: Bool) async
    func recheck(_ request: DownloadRequest) async
    func setFileSelection(_ request: DownloadRequest, selectedFileIndexes: [Int]) async
    func setTorrentFilePriority(_ request: DownloadRequest, fileIndex: Int, priority: Int) async
    func setTorrentSequentialDownload(_ request: DownloadRequest, enabled: Bool) async
    func addTorrentTracker(_ request: DownloadRequest, url: String) async
    func removeTorrentTracker(_ request: DownloadRequest, url: String) async
    func forceTorrentReannounce(_ request: DownloadRequest) async
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
    let httpResponseMetadata: HTTPResponseMetadata?
    let selectedFileIndexes: [Int]
    let torrentFiles: [TorrentFile]
    let torrentResumeState: TorrentResumeState?
    let torrentRuntimeOptions: TorrentRuntimeOptions?
    let hasExplicitFileSelection: Bool
    let browserContext: BrowserDownloadContext?

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
        httpResponseMetadata: HTTPResponseMetadata? = nil,
        selectedFileIndexes: [Int],
        torrentFiles: [TorrentFile] = [],
        torrentResumeState: TorrentResumeState? = nil,
        torrentRuntimeOptions: TorrentRuntimeOptions? = nil,
        hasExplicitFileSelection: Bool = false,
        browserContext: BrowserDownloadContext? = nil
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
        self.httpResponseMetadata = httpResponseMetadata
        self.selectedFileIndexes = selectedFileIndexes
        self.torrentFiles = torrentFiles
        self.torrentResumeState = torrentResumeState
        self.torrentRuntimeOptions = torrentRuntimeOptions
        self.hasExplicitFileSelection = hasExplicitFileSelection
        self.browserContext = browserContext
    }

    init(task: DownloadTask, browserContext: BrowserDownloadContext? = nil) {
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
        httpResponseMetadata = task.httpResponseMetadata
        selectedFileIndexes = task.selectedFileIndexes
        torrentFiles = task.torrentFiles
        torrentResumeState = task.torrentResumeState
        torrentRuntimeOptions = task.torrentRuntimeOptions
        hasExplicitFileSelection = task.kind == .torrentMagnet || task.kind == .torrentFile
            ? !task.torrentFiles.isEmpty
            : false
        self.browserContext = browserContext ?? task.browserContext
    }
}

extension DownloadEngine {
    func setTorrentFilePriority(_ request: DownloadRequest, fileIndex: Int, priority: Int) async {}
    func setTorrentSequentialDownload(_ request: DownloadRequest, enabled: Bool) async {}
    func addTorrentTracker(_ request: DownloadRequest, url: String) async {}
    func removeTorrentTracker(_ request: DownloadRequest, url: String) async {}
    func forceTorrentReannounce(_ request: DownloadRequest) async {}
}
