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
    func setTorrentRuntimeOptions(_ request: DownloadRequest, options: TorrentRuntimeOptions) async
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
    let torrentSaveDirectoryPath: String?
    let torrentOutputName: String?
    let torrentContentRootPath: String?
    let torrentFinalFilePath: String?
    let totalBytes: Int64
    let downloadedBytes: Int64
    let supportsResume: Bool
    let eTag: String?
    let lastModified: String?
    let httpResponseMetadata: HTTPResponseMetadata?
    let httpOptions: HTTPDownloadOptions?
    let selectedFileIndexes: [Int]
    let torrentFiles: [TorrentFile]
    let torrentResumeState: TorrentResumeState?
    let torrentRuntimeOptions: TorrentRuntimeOptions?
    let hasExplicitFileSelection: Bool
    let browserContext: BrowserDownloadContext?
    let perTaskDownloadLimitBytes: Int64
    let perTaskUploadLimitBytes: Int64

    init(
        id: UUID,
        name: String,
        source: String,
        resolvedTorrentFilePath: String? = nil,
        kind: DownloadKind,
        status: DownloadStatus = .queued,
        savePath: String,
        torrentSaveDirectoryPath: String? = nil,
        torrentOutputName: String? = nil,
        torrentContentRootPath: String? = nil,
        torrentFinalFilePath: String? = nil,
        totalBytes: Int64,
        downloadedBytes: Int64,
        supportsResume: Bool,
        eTag: String?,
        lastModified: String?,
        httpResponseMetadata: HTTPResponseMetadata? = nil,
        httpOptions: HTTPDownloadOptions? = nil,
        selectedFileIndexes: [Int],
        torrentFiles: [TorrentFile] = [],
        torrentResumeState: TorrentResumeState? = nil,
        torrentRuntimeOptions: TorrentRuntimeOptions? = nil,
        hasExplicitFileSelection: Bool = false,
        browserContext: BrowserDownloadContext? = nil,
        perTaskDownloadLimitBytes: Int64 = 0,
        perTaskUploadLimitBytes: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.resolvedTorrentFilePath = resolvedTorrentFilePath
        self.kind = kind
        self.status = status
        self.savePath = savePath
        self.torrentSaveDirectoryPath = torrentSaveDirectoryPath
        self.torrentOutputName = torrentOutputName
        self.torrentContentRootPath = torrentContentRootPath
        self.torrentFinalFilePath = torrentFinalFilePath
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.supportsResume = supportsResume
        self.eTag = eTag
        self.lastModified = lastModified
        self.httpResponseMetadata = httpResponseMetadata
        self.httpOptions = httpOptions
        self.selectedFileIndexes = selectedFileIndexes
        self.torrentFiles = torrentFiles
        self.torrentResumeState = torrentResumeState
        self.torrentRuntimeOptions = torrentRuntimeOptions
        self.hasExplicitFileSelection = hasExplicitFileSelection
        self.browserContext = browserContext
        self.perTaskDownloadLimitBytes = max(0, perTaskDownloadLimitBytes)
        self.perTaskUploadLimitBytes = max(0, perTaskUploadLimitBytes)
    }

    init(
        task: DownloadTask,
        browserContext: BrowserDownloadContext? = nil,
        httpOptions: HTTPDownloadOptions? = nil
    ) {
        id = task.id
        name = task.name
        source = task.source
        resolvedTorrentFilePath = task.resolvedTorrentFilePath
        kind = task.kind
        status = task.status
        savePath = task.savePath
        torrentSaveDirectoryPath = task.isTorrent ? task.effectiveTorrentSaveDirectoryPath : nil
        torrentOutputName = task.isTorrent ? task.effectiveTorrentOutputName : nil
        torrentContentRootPath = task.isTorrent ? task.effectiveTorrentContentRootPath : nil
        torrentFinalFilePath = task.isTorrent ? task.torrentFinalFilePath : nil
        totalBytes = task.totalBytes
        downloadedBytes = task.downloadedBytes
        supportsResume = task.supportsResume
        eTag = task.eTag
        lastModified = task.lastModified
        httpResponseMetadata = task.httpResponseMetadata
        self.httpOptions = httpOptions ?? task.httpOptions
        selectedFileIndexes = task.selectedFileIndexes
        torrentFiles = task.torrentFiles
        torrentResumeState = task.torrentResumeState
        torrentRuntimeOptions = task.torrentRuntimeOptions
        hasExplicitFileSelection = task.kind == .torrentMagnet || task.kind == .torrentFile
            ? !task.torrentFiles.isEmpty
            : false
        self.browserContext = browserContext ?? task.browserContext
        perTaskDownloadLimitBytes = task.perTaskDownloadLimitBytes
        perTaskUploadLimitBytes = task.perTaskUploadLimitBytes
    }
}

extension DownloadEngine {
    func setTorrentFilePriority(_ request: DownloadRequest, fileIndex: Int, priority: Int) async {}
    func setTorrentSequentialDownload(_ request: DownloadRequest, enabled: Bool) async {}
    func setTorrentRuntimeOptions(_ request: DownloadRequest, options: TorrentRuntimeOptions) async {}
    func addTorrentTracker(_ request: DownloadRequest, url: String) async {}
    func removeTorrentTracker(_ request: DownloadRequest, url: String) async {}
    func forceTorrentReannounce(_ request: DownloadRequest) async {}
}
