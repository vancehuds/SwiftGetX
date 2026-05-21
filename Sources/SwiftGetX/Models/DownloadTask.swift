import Foundation
import SwiftData
import SwiftGetXCore
import SwiftGetXTorrentCore

@Model
final class DownloadTask {
    @Attribute(.unique) var id: UUID
    var name: String
    var source: String
    var kindRawValue: String
    var statusRawValue: String
    var savePath: String
    var totalBytes: Int64
    var downloadedBytes: Int64
    var speedBytesPerSecond: Int64
    var etaSeconds: TimeInterval?
    var createdAt: Date
    var completedAt: Date?
    var errorMessage: String?
    var retryCount: Int
    var supportsResume: Bool
    var eTag: String?
    var lastModified: String?
    var resolvedTorrentFilePath: String?
    var torrentMetadataStatusRawValue: String?
    var torrentConnectionJSON: String?
    var torrentResumeStateJSON: String?
    var torrentTrackersJSON: String?
    var torrentPeersJSON: String?
    var torrentRuntimeOptionsJSON: String?
    var torrentHealthJSON: String?
    var torrentSaveDirectoryPath: String?
    var torrentOutputName: String?
    var torrentContentRootPath: String?
    var torrentFinalFilePath: String?
    var selectedFileIndexes: [Int]
    var torrentFilesJSON: String?
    var connectionSummary: String?
    var browserContextJSON: String?
    var httpResponseMetadataJSON: String?
    var httpOptionsJSON: String?
    var queuePosition: Double = 0
    var queuePriorityRawValue: String = DownloadQueuePriority.normal.rawValue
    var queueFailureCount: Int = 0
    var nextQueueRetryAt: Date?
    var logEntries: [String]

    init(
        id: UUID = UUID(),
        name: String,
        source: String,
        kind: DownloadKind,
        status: DownloadStatus = .queued,
        savePath: String,
        totalBytes: Int64 = 0,
        downloadedBytes: Int64 = 0,
        speedBytesPerSecond: Int64 = 0,
        etaSeconds: TimeInterval? = nil,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        errorMessage: String? = nil,
        retryCount: Int = 0,
        supportsResume: Bool = false,
        eTag: String? = nil,
        lastModified: String? = nil,
        resolvedTorrentFilePath: String? = nil,
        torrentMetadataStatus: TorrentMetadataStatus = .unknown,
        torrentConnectionJSON: String? = nil,
        torrentResumeStateJSON: String? = nil,
        torrentTrackersJSON: String? = nil,
        torrentPeersJSON: String? = nil,
        torrentRuntimeOptionsJSON: String? = nil,
        torrentHealthJSON: String? = nil,
        torrentSaveDirectoryPath: String? = nil,
        torrentOutputName: String? = nil,
        torrentContentRootPath: String? = nil,
        torrentFinalFilePath: String? = nil,
        selectedFileIndexes: [Int] = [],
        torrentFilesJSON: String? = nil,
        connectionSummary: String? = nil,
        browserContext: BrowserDownloadContext? = nil,
        httpResponseMetadata: HTTPResponseMetadata? = nil,
        httpOptions: HTTPDownloadOptions? = nil,
        queuePosition: Double = 0,
        queuePriority: DownloadQueuePriority = .normal,
        queueFailureCount: Int = 0,
        nextQueueRetryAt: Date? = nil,
        logEntries: [String] = []
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.kindRawValue = kind.rawValue
        self.statusRawValue = status.rawValue
        self.savePath = savePath
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.etaSeconds = etaSeconds
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
        self.retryCount = retryCount
        self.supportsResume = supportsResume
        self.eTag = eTag
        self.lastModified = lastModified
        self.resolvedTorrentFilePath = resolvedTorrentFilePath
        self.torrentMetadataStatusRawValue = torrentMetadataStatus.rawValue
        self.torrentConnectionJSON = torrentConnectionJSON
        self.torrentResumeStateJSON = torrentResumeStateJSON
        self.torrentTrackersJSON = torrentTrackersJSON
        self.torrentPeersJSON = torrentPeersJSON
        self.torrentRuntimeOptionsJSON = torrentRuntimeOptionsJSON
        self.torrentHealthJSON = torrentHealthJSON
        self.torrentSaveDirectoryPath = torrentSaveDirectoryPath
        self.torrentOutputName = torrentOutputName
        self.torrentContentRootPath = torrentContentRootPath
        self.torrentFinalFilePath = torrentFinalFilePath
        self.selectedFileIndexes = selectedFileIndexes
        self.torrentFilesJSON = torrentFilesJSON
        self.connectionSummary = connectionSummary
        self.browserContextJSON = Self.encode(browserContext)
        self.httpResponseMetadataJSON = Self.encode(httpResponseMetadata)
        self.httpOptionsJSON = Self.encodeHTTPOptions(httpOptions)
        self.queuePosition = queuePosition
        self.queuePriorityRawValue = queuePriority.rawValue
        self.queueFailureCount = queueFailureCount
        self.nextQueueRetryAt = nextQueueRetryAt
        self.logEntries = logEntries
    }

    var kind: DownloadKind {
        get { DownloadKind(rawValue: kindRawValue) ?? .http }
        set { kindRawValue = newValue.rawValue }
    }

    var status: DownloadStatus {
        get { DownloadStatus(rawValue: statusRawValue) ?? .queued }
        set { statusRawValue = newValue.rawValue }
    }

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(downloadedBytes) / Double(totalBytes), 0), 1)
    }

    var isTerminal: Bool {
        status == .completed || status == .failed || status == .cancelled
    }

    var usesActiveDownloadSlot: Bool {
        status == .running || status == .fetchingPeers || status == .connectingPeers || status == .verifying
    }

    var isQueueManageable: Bool {
        status == .queued || status == .paused || status == .failed || status == .cancelled
    }

    var hasFinishedDownloading: Bool {
        status == .completed || status == .seeding
    }

    var queuePriority: DownloadQueuePriority {
        get { DownloadQueuePriority(rawValue: queuePriorityRawValue) ?? .normal }
        set { queuePriorityRawValue = newValue.rawValue }
    }

    var effectiveQueuePosition: Double {
        queuePosition > 0 ? queuePosition : createdAt.timeIntervalSinceReferenceDate
    }

    func isQueueRetryDue(at date: Date = .now) -> Bool {
        guard let nextQueueRetryAt else { return true }
        return nextQueueRetryAt <= date
    }

    var displaySource: String {
        browserContext?.redactedPrimaryURL
            ?? httpResponseMetadata?.finalURL
            ?? BrowserDownloadContext.redactedURLString(source)
            ?? source
    }

    var isTorrent: Bool {
        kind == .torrentMagnet || kind == .torrentFile
    }

    var effectiveTorrentSaveDirectoryPath: String {
        torrentSaveDirectoryPath?.nonEmptyTrimmed ?? savePath
    }

    var effectiveTorrentOutputName: String {
        torrentOutputName?.nonEmptyTrimmed
            ?? URL(fileURLWithPath: savePath).lastPathComponent
    }

    var effectiveTorrentContentRootPath: String {
        torrentContentRootPath?.nonEmptyTrimmed ?? savePath
    }

    var displaySavePath: String {
        guard isTorrent else { return savePath }
        return torrentFinalFilePath?.nonEmptyTrimmed
            ?? torrentContentRootPath?.nonEmptyTrimmed
            ?? torrentSaveDirectoryPath?.nonEmptyTrimmed
            ?? savePath
    }

    var revealURL: URL {
        URL(fileURLWithPath: displaySavePath)
    }

    var localContentDeletionURLs: [URL] {
        guard isTorrent else {
            var urls = [URL(fileURLWithPath: savePath)]
            urls.append(contentsOf: HTTPPartialDataStore(savePath: savePath).existingDataURLs)
            return Self.uniqueStandardizedURLs(urls)
        }

        let saveDirectoryURL = URL(
            fileURLWithPath: effectiveTorrentSaveDirectoryPath,
            isDirectory: true
        ).standardizedFileURL
        let candidatePath = torrentFinalFilePath?.nonEmptyTrimmed
            ?? torrentContentRootPath?.nonEmptyTrimmed
        guard let candidatePath else { return [] }
        let contentURL = URL(fileURLWithPath: candidatePath).standardizedFileURL

        guard contentURL.path != saveDirectoryURL.path,
              contentURL.isDescendant(of: saveDirectoryURL)
        else {
            return []
        }
        return [contentURL]
    }

    var localContentDeletionPathSummary: String {
        let paths = localContentDeletionURLs.map(\.path)
        guard !paths.isEmpty else {
            return L10n.string("delete_task_no_known_local_content")
        }
        return paths.joined(separator: "\n")
    }

    var torrentMetadataStatus: TorrentMetadataStatus {
        get {
            guard let rawValue = torrentMetadataStatusRawValue else { return .unknown }
            return TorrentMetadataStatus(rawValue: rawValue) ?? .unknown
        }
        set { torrentMetadataStatusRawValue = newValue.rawValue }
    }

    func appendLog(_ message: String) {
        let formatter = DateFormatter.taskLogFormatter
        logEntries.append("[\(formatter.string(from: .now))] \(message)")
        if logEntries.count > 200 {
            logEntries.removeFirst(logEntries.count - 200)
        }
    }

    var torrentFiles: [TorrentFile] {
        get {
            guard let torrentFilesJSON,
                  let data = torrentFilesJSON.data(using: .utf8),
                  let files = try? JSONDecoder().decode([TorrentFile].self, from: data)
            else {
                return []
            }
            return files
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                torrentFilesJSON = nil
                return
            }
            torrentFilesJSON = String(data: data, encoding: .utf8)
        }
    }

    var torrentConnection: TorrentConnectionInfo? {
        get {
            guard let torrentConnectionJSON,
                  let data = torrentConnectionJSON.data(using: .utf8)
            else {
                return nil
            }
            return try? JSONDecoder().decode(TorrentConnectionInfo.self, from: data)
        }
        set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue)
            else {
                torrentConnectionJSON = nil
                return
            }
            torrentConnectionJSON = String(data: data, encoding: .utf8)
        }
    }

    var torrentResumeState: TorrentResumeState? {
        get { Self.decode(TorrentResumeState.self, from: torrentResumeStateJSON) }
        set { torrentResumeStateJSON = Self.encode(newValue) }
    }

    var torrentTrackers: [TorrentTrackerInfo] {
        get { Self.decode([TorrentTrackerInfo].self, from: torrentTrackersJSON) ?? [] }
        set { torrentTrackersJSON = Self.encode(newValue) }
    }

    var torrentPeers: [TorrentPeerInfo] {
        get { Self.decode([TorrentPeerInfo].self, from: torrentPeersJSON) ?? [] }
        set { torrentPeersJSON = Self.encode(newValue) }
    }

    var torrentRuntimeOptions: TorrentRuntimeOptions? {
        get { Self.decode(TorrentRuntimeOptions.self, from: torrentRuntimeOptionsJSON) }
        set { torrentRuntimeOptionsJSON = Self.encode(newValue) }
    }

    var torrentHealth: TorrentHealthInfo? {
        get { Self.decode(TorrentHealthInfo.self, from: torrentHealthJSON) }
        set { torrentHealthJSON = Self.encode(newValue) }
    }

    var browserContext: BrowserDownloadContext? {
        get { Self.decode(BrowserDownloadContext.self, from: browserContextJSON) }
        set { browserContextJSON = Self.encode(newValue) }
    }

    var httpResponseMetadata: HTTPResponseMetadata? {
        get { Self.decode(HTTPResponseMetadata.self, from: httpResponseMetadataJSON) }
        set { httpResponseMetadataJSON = Self.encode(newValue) }
    }

    var httpOptions: HTTPDownloadOptions? {
        get { Self.decode(HTTPDownloadOptions.self, from: httpOptionsJSON) }
        set { httpOptionsJSON = Self.encodeHTTPOptions(newValue) }
    }

    func applyTorrentLayout(
        saveDirectory: URL,
        outputName: String? = nil,
        files: [TorrentFile]? = nil,
        isMultiFile: Bool? = nil
    ) {
        guard isTorrent else { return }
        let normalizedSaveDirectory = saveDirectory.standardizedFileURL
        savePath = normalizedSaveDirectory.path
        torrentSaveDirectoryPath = normalizedSaveDirectory.path
        let torrentFiles = files ?? self.torrentFiles
        let sanitizedOutputName = outputName?.nonEmptyTrimmed
            ?? SourceParser.sanitizeFilename(name).nonEmptyTrimmed
        torrentOutputName = sanitizedOutputName

        guard !torrentFiles.isEmpty else {
            torrentContentRootPath = nil
            torrentFinalFilePath = nil
            return
        }

        guard let layout = try? TorrentContentLayout(
            files: torrentFiles.map(\.torrentFileInfo),
            saveDirectory: normalizedSaveDirectory,
            outputName: sanitizedOutputName,
            isMultiFile: isMultiFile
        ) else {
            torrentContentRootPath = nil
            torrentFinalFilePath = nil
            return
        }

        torrentOutputName = layout.outputName
        torrentContentRootPath = layout.contentRoot.path
        torrentFinalFilePath = layout.finalFileURL?.path
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from json: String?) -> Value? {
        guard let json,
              let data = json.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private static func encode<Value: Encodable>(_ value: Value?) -> String? {
        guard let value,
              let data = try? JSONEncoder().encode(value)
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func encodeHTTPOptions(_ options: HTTPDownloadOptions?) -> String? {
        guard let persistable = options?.persistable, !persistable.isEmpty else {
            return nil
        }
        return encode(persistable)
    }

    private static func uniqueStandardizedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var unique = [URL]()
        for url in urls {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            unique.append(standardized)
        }
        return unique
    }
}

enum DownloadKind: String, Codable, CaseIterable, Identifiable {
    case http
    case torrentMagnet
    case torrentFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .http:
            "HTTP"
        case .torrentMagnet:
            L10n.string("download_kind_magnet")
        case .torrentFile:
            "BT"
        }
    }

    var symbolName: String {
        switch self {
        case .http:
            "link"
        case .torrentMagnet:
            "magnet"
        case .torrentFile:
            "doc.zipper"
        }
    }
}

enum DownloadStatus: String, Codable, CaseIterable, Identifiable {
    case queued
    case running
    case fetchingPeers
    case connectingPeers
    case seeding
    case paused
    case verifying
    case completed
    case failed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queued:
            L10n.string("download_status_queued")
        case .running:
            L10n.string("download_status_running")
        case .fetchingPeers:
            L10n.string("download_status_fetching_peers")
        case .connectingPeers:
            L10n.string("download_status_connecting_peers")
        case .seeding:
            L10n.string("download_status_seeding")
        case .paused:
            L10n.string("download_status_paused")
        case .verifying:
            L10n.string("download_status_verifying")
        case .completed:
            L10n.string("download_status_completed")
        case .failed:
            L10n.string("download_status_failed")
        case .cancelled:
            L10n.string("download_status_cancelled")
        }
    }

    var symbolName: String {
        switch self {
        case .queued:
            "clock"
        case .running:
            "arrow.down.circle.fill"
        case .fetchingPeers:
            "antenna.radiowaves.left.and.right"
        case .connectingPeers:
            "point.3.connected.trianglepath.dotted"
        case .seeding:
            "arrow.up.circle.fill"
        case .paused:
            "pause.circle"
        case .verifying:
            "checkmark.seal"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .cancelled:
            "xmark.circle.fill"
        }
    }
}

enum DownloadQueuePriority: String, Codable, CaseIterable, Identifiable {
    case high = "0_high"
    case normal = "1_normal"
    case low = "2_low"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high:
            L10n.string("queue_priority_high")
        case .normal:
            L10n.string("queue_priority_normal")
        case .low:
            L10n.string("queue_priority_low")
        }
    }

    var symbolName: String {
        switch self {
        case .high:
            "arrow.up.circle"
        case .normal:
            "equal.circle"
        case .low:
            "arrow.down.circle"
        }
    }
}

struct DownloadSnapshot: Sendable {
    let taskID: UUID
    let status: DownloadStatus
    let name: String?
    let savePath: String?
    let resolvedTorrentFilePath: String?
    let torrentMetadataStatus: TorrentMetadataStatus?
    let totalBytes: Int64
    let downloadedBytes: Int64
    let speedBytesPerSecond: Int64
    let etaSeconds: TimeInterval?
    let errorMessage: String?
    let supportsResume: Bool
    let eTag: String?
    let lastModified: String?
    let torrentFiles: [TorrentFile]
    let torrentConnection: TorrentConnectionInfo?
    let torrentResumeState: TorrentResumeState?
    let torrentTrackers: [TorrentTrackerInfo]?
    let torrentPeers: [TorrentPeerInfo]?
    let torrentRuntimeOptions: TorrentRuntimeOptions?
    let torrentHealth: TorrentHealthInfo?
    let connectionSummary: String?
    let httpResponseMetadata: HTTPResponseMetadata?
    let retryCount: Int?

    init(
        taskID: UUID,
        status: DownloadStatus,
        name: String? = nil,
        savePath: String? = nil,
        totalBytes: Int64,
        downloadedBytes: Int64,
        speedBytesPerSecond: Int64,
        etaSeconds: TimeInterval?,
        errorMessage: String?,
        supportsResume: Bool,
        eTag: String?,
        lastModified: String?,
        torrentFiles: [TorrentFile] = [],
        connectionSummary: String? = nil,
        httpResponseMetadata: HTTPResponseMetadata? = nil,
        retryCount: Int? = nil,
        resolvedTorrentFilePath: String? = nil,
        torrentMetadataStatus: TorrentMetadataStatus? = nil,
        torrentConnection: TorrentConnectionInfo? = nil,
        torrentResumeState: TorrentResumeState? = nil,
        torrentTrackers: [TorrentTrackerInfo]? = nil,
        torrentPeers: [TorrentPeerInfo]? = nil,
        torrentRuntimeOptions: TorrentRuntimeOptions? = nil,
        torrentHealth: TorrentHealthInfo? = nil
    ) {
        self.taskID = taskID
        self.status = status
        self.name = name
        self.savePath = savePath
        self.resolvedTorrentFilePath = resolvedTorrentFilePath
        self.torrentMetadataStatus = torrentMetadataStatus
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.etaSeconds = etaSeconds
        self.errorMessage = errorMessage
        self.supportsResume = supportsResume
        self.eTag = eTag
        self.lastModified = lastModified
        self.torrentFiles = torrentFiles
        self.torrentConnection = torrentConnection
        self.torrentResumeState = torrentResumeState
        self.torrentTrackers = torrentTrackers
        self.torrentPeers = torrentPeers
        self.torrentRuntimeOptions = torrentRuntimeOptions
        self.torrentHealth = torrentHealth
        self.connectionSummary = connectionSummary
        self.httpResponseMetadata = httpResponseMetadata
        self.retryCount = retryCount
    }
}

enum TorrentMetadataStatus: String, Codable, Sendable, CaseIterable {
    case unknown
    case fetching
    case available
    case unavailable
    case failed

    var title: String {
        switch self {
        case .unknown:
            L10n.string("torrent_metadata_unknown")
        case .fetching:
            L10n.string("torrent_metadata_fetching")
        case .available:
            L10n.string("torrent_metadata_available")
        case .unavailable:
            L10n.string("torrent_metadata_unavailable")
        case .failed:
            L10n.string("torrent_metadata_failed")
        }
    }
}

struct TorrentFile: Codable, Identifiable, Equatable, Sendable {
    var index: Int
    var path: String
    var size: Int64
    var priority: Int
    var progress: Double

    var id: Int { index }

    init(index: Int, path: String, size: Int64, priority: Int = 1, progress: Double = 0) {
        self.index = index
        self.path = path
        self.size = size
        self.priority = priority
        self.progress = progress
    }

    var priorityLevel: TorrentFilePriority {
        get { TorrentFilePriority(rawValue: priority) ?? .normal }
        set { priority = newValue.rawValue }
    }

    var torrentFileInfo: TorrentFileInfo {
        TorrentFileInfo(index: index, path: path, length: size)
    }
}

enum TorrentFilePriority: Int, Codable, CaseIterable, Identifiable, Sendable {
    case skip = 0
    case normal = 1
    case high = 2
    case maximum = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .skip:
            L10n.string("torrent_file_priority_skip")
        case .normal:
            L10n.string("torrent_file_priority_normal")
        case .high:
            L10n.string("torrent_file_priority_high")
        case .maximum:
            L10n.string("torrent_file_priority_maximum")
        }
    }
}

struct TorrentConnectionInfo: Codable, Equatable, Sendable {
    var metadataStatus: TorrentMetadataStatus
    var engine: TorrentEngineKind
    var engineStatus: TorrentEngineStatus
    var peerCount: Int
    var downloadRate: Int64
    var uploadRate: Int64
    var shareRatio: Double
    var distributedCopies: Double
    var isDHTEnabled: Bool
    var isPEXEnabled: Bool
    var isLSDEnabled: Bool
    var localPortDescription: String
    var nativeEngineAvailable: Bool

    private enum CodingKeys: String, CodingKey {
        case metadataStatus
        case engine
        case engineStatus
        case peerCount
        case downloadRate
        case uploadRate
        case shareRatio
        case distributedCopies
        case isDHTEnabled
        case isPEXEnabled
        case isLSDEnabled
        case localPortDescription
        case nativeEngineAvailable
    }

    init(
        metadataStatus: TorrentMetadataStatus = .unknown,
        engine: TorrentEngineKind = .swift,
        engineStatus: TorrentEngineStatus = .unavailable,
        peerCount: Int = 0,
        downloadRate: Int64 = 0,
        uploadRate: Int64 = 0,
        shareRatio: Double = 0,
        distributedCopies: Double = 0,
        isDHTEnabled: Bool = false,
        isPEXEnabled: Bool = false,
        isLSDEnabled: Bool = false,
        localPortDescription: String = "",
        nativeEngineAvailable: Bool = false
    ) {
        self.metadataStatus = metadataStatus
        self.engine = engine
        self.engineStatus = engineStatus
        self.peerCount = peerCount
        self.downloadRate = downloadRate
        self.uploadRate = uploadRate
        self.shareRatio = shareRatio
        self.distributedCopies = distributedCopies
        self.isDHTEnabled = isDHTEnabled
        self.isPEXEnabled = isPEXEnabled
        self.isLSDEnabled = isLSDEnabled
        self.localPortDescription = localPortDescription
        self.nativeEngineAvailable = nativeEngineAvailable
    }

    var summary: String {
        guard engineStatus.supportsRuntimeControls else {
            return engineStatus.title
        }
        return L10n.string(
            "torrent_connection_summary",
            peerCount,
            Self.speedLabel(downloadRate),
            Self.speedLabel(uploadRate),
            shareRatio
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metadataStatus = try container.decodeIfPresent(TorrentMetadataStatus.self, forKey: .metadataStatus) ?? .unknown
        nativeEngineAvailable = try container.decodeIfPresent(Bool.self, forKey: .nativeEngineAvailable) ?? false
        engine = try container.decodeIfPresent(TorrentEngineKind.self, forKey: .engine)
            ?? (nativeEngineAvailable ? .libtorrent : .swift)
        engineStatus = try container.decodeIfPresent(TorrentEngineStatus.self, forKey: .engineStatus)
            ?? (nativeEngineAvailable ? .available : .unavailable)
        peerCount = try container.decodeIfPresent(Int.self, forKey: .peerCount) ?? 0
        downloadRate = try container.decodeIfPresent(Int64.self, forKey: .downloadRate) ?? 0
        uploadRate = try container.decodeIfPresent(Int64.self, forKey: .uploadRate) ?? 0
        shareRatio = try container.decodeIfPresent(Double.self, forKey: .shareRatio) ?? 0
        distributedCopies = try container.decodeIfPresent(Double.self, forKey: .distributedCopies) ?? 0
        isDHTEnabled = try container.decodeIfPresent(Bool.self, forKey: .isDHTEnabled) ?? false
        isPEXEnabled = try container.decodeIfPresent(Bool.self, forKey: .isPEXEnabled) ?? false
        isLSDEnabled = try container.decodeIfPresent(Bool.self, forKey: .isLSDEnabled) ?? false
        localPortDescription = try container.decodeIfPresent(String.self, forKey: .localPortDescription) ?? ""
    }

    private static func speedLabel(_ bytesPerSecond: Int64) -> String {
        let value = Double(max(bytesPerSecond, 0))
        if value >= 1_000_000_000 {
            return String(format: "%.1f GB/s", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1f MB/s", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0f KB/s", value / 1_000)
        }
        return "\(Int(value)) B/s"
    }
}

enum TorrentEngineKind: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case swift
    case libtorrent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swift:
            L10n.string("torrent_engine_swift")
        case .libtorrent:
            L10n.string("torrent_engine_libtorrent")
        }
    }
}

enum TorrentEngineStatus: String, Codable, Equatable, Sendable {
    case available
    case metadataOnly
    case unavailable

    var isAvailable: Bool {
        self == .available || self == .metadataOnly
    }

    var supportsRuntimeControls: Bool {
        self == .available
    }

    var title: String {
        switch self {
        case .available:
            L10n.string("torrent_engine_status_available")
        case .metadataOnly:
            L10n.string("torrent_engine_status_metadata_only")
        case .unavailable:
            L10n.string("torrent_engine_status_unavailable")
        }
    }
}

struct TorrentTrackerInfo: Codable, Identifiable, Equatable, Sendable {
    var url: String
    var tier: Int
    var status: String
    var seedCount: Int
    var leecherCount: Int
    var downloadedCount: Int
    var lastAnnounce: String
    var nextAnnounce: String
    var errorMessage: String?

    var id: String { "\(tier)-\(url)" }

    init(
        url: String,
        tier: Int = 0,
        status: String = "",
        seedCount: Int = -1,
        leecherCount: Int = -1,
        downloadedCount: Int = -1,
        lastAnnounce: String = "",
        nextAnnounce: String = "",
        errorMessage: String? = nil
    ) {
        self.url = url
        self.tier = tier
        self.status = status
        self.seedCount = seedCount
        self.leecherCount = leecherCount
        self.downloadedCount = downloadedCount
        self.lastAnnounce = lastAnnounce
        self.nextAnnounce = nextAnnounce
        self.errorMessage = errorMessage
    }
}

struct TorrentPeerInfo: Codable, Identifiable, Equatable, Sendable {
    var address: String
    var client: String
    var progress: Double
    var downloadRate: Int64
    var uploadRate: Int64
    var direction: String
    var flags: String

    var id: String { address }
}

struct TorrentHealthInfo: Codable, Equatable, Sendable {
    var nativeEngineAvailable: Bool
    var engine: TorrentEngineKind
    var engineStatus: TorrentEngineStatus
    var hasMetadata: Bool
    var isSequentialDownload: Bool
    var needsResumeDataSave: Bool
    var peerCount: Int
    var connectionCount: Int
    var uploadSlotCount: Int
    var listenPort: Int
    var dhtNodeCount: Int
    var distributedCopies: Double
    var trackerCount: Int
    var lastError: String?

    private enum CodingKeys: String, CodingKey {
        case nativeEngineAvailable
        case engine
        case engineStatus
        case hasMetadata
        case isSequentialDownload
        case needsResumeDataSave
        case peerCount
        case connectionCount
        case uploadSlotCount
        case listenPort
        case dhtNodeCount
        case distributedCopies
        case trackerCount
        case lastError
    }

    init(
        nativeEngineAvailable: Bool = false,
        engine: TorrentEngineKind = .swift,
        engineStatus: TorrentEngineStatus = .unavailable,
        hasMetadata: Bool = false,
        isSequentialDownload: Bool = false,
        needsResumeDataSave: Bool = false,
        peerCount: Int = 0,
        connectionCount: Int = 0,
        uploadSlotCount: Int = 0,
        listenPort: Int = 0,
        dhtNodeCount: Int = 0,
        distributedCopies: Double = 0,
        trackerCount: Int = 0,
        lastError: String? = nil
    ) {
        self.nativeEngineAvailable = nativeEngineAvailable
        self.engine = engine
        self.engineStatus = engineStatus
        self.hasMetadata = hasMetadata
        self.isSequentialDownload = isSequentialDownload
        self.needsResumeDataSave = needsResumeDataSave
        self.peerCount = peerCount
        self.connectionCount = connectionCount
        self.uploadSlotCount = uploadSlotCount
        self.listenPort = listenPort
        self.dhtNodeCount = dhtNodeCount
        self.distributedCopies = distributedCopies
        self.trackerCount = trackerCount
        self.lastError = lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nativeEngineAvailable = try container.decodeIfPresent(Bool.self, forKey: .nativeEngineAvailable) ?? false
        engine = try container.decodeIfPresent(TorrentEngineKind.self, forKey: .engine)
            ?? (nativeEngineAvailable ? .libtorrent : .swift)
        engineStatus = try container.decodeIfPresent(TorrentEngineStatus.self, forKey: .engineStatus)
            ?? (nativeEngineAvailable ? .available : .unavailable)
        hasMetadata = try container.decodeIfPresent(Bool.self, forKey: .hasMetadata) ?? false
        isSequentialDownload = try container.decodeIfPresent(Bool.self, forKey: .isSequentialDownload) ?? false
        needsResumeDataSave = try container.decodeIfPresent(Bool.self, forKey: .needsResumeDataSave) ?? false
        peerCount = try container.decodeIfPresent(Int.self, forKey: .peerCount) ?? 0
        connectionCount = try container.decodeIfPresent(Int.self, forKey: .connectionCount) ?? 0
        uploadSlotCount = try container.decodeIfPresent(Int.self, forKey: .uploadSlotCount) ?? 0
        listenPort = try container.decodeIfPresent(Int.self, forKey: .listenPort) ?? 0
        dhtNodeCount = try container.decodeIfPresent(Int.self, forKey: .dhtNodeCount) ?? 0
        distributedCopies = try container.decodeIfPresent(Double.self, forKey: .distributedCopies) ?? 0
        trackerCount = try container.decodeIfPresent(Int.self, forKey: .trackerCount) ?? 0
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}

struct TorrentResumeState: Codable, Equatable, Sendable {
    var resumeDataPath: String
    var status: Status
    var updatedAt: Date?
    var errorMessage: String?

    enum Status: String, Codable, Sendable {
        case missing
        case loaded
        case saved
        case failed
    }

    init(
        resumeDataPath: String,
        status: Status,
        updatedAt: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.resumeDataPath = resumeDataPath
        self.status = status
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
    }
}

enum TorrentSeedingLimitMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case stopAtRatio
    case stopWhenComplete
    case neverStop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stopAtRatio:
            L10n.string("torrent_seeding_mode_ratio")
        case .stopWhenComplete:
            L10n.string("torrent_seeding_mode_complete")
        case .neverStop:
            L10n.string("torrent_seeding_mode_never")
        }
    }
}

struct TorrentRuntimeOptions: Codable, Equatable, Sendable {
    var engine: TorrentEngineKind
    var isDHTEnabled: Bool
    var isPEXEnabled: Bool
    var isLSDEnabled: Bool
    var isSequentialDownloadEnabled: Bool
    var magnetMetadataTimeoutSeconds: Int
    var maxConnections: Int
    var maxUploadSlots: Int
    var seedingLimitMode: TorrentSeedingLimitMode
    var stopSeedingAtRatio: Double

    private enum CodingKeys: String, CodingKey {
        case engine
        case isDHTEnabled
        case isPEXEnabled
        case isLSDEnabled
        case isSequentialDownloadEnabled
        case magnetMetadataTimeoutSeconds
        case maxConnections
        case maxUploadSlots
        case seedingLimitMode
        case stopSeedingAtRatio
    }

    init(
        engine: TorrentEngineKind = .swift,
        isDHTEnabled: Bool = true,
        isPEXEnabled: Bool = true,
        isLSDEnabled: Bool = true,
        isSequentialDownloadEnabled: Bool = false,
        magnetMetadataTimeoutSeconds: Int = 12,
        maxConnections: Int = 200,
        maxUploadSlots: Int = 8,
        seedingLimitMode: TorrentSeedingLimitMode = .stopAtRatio,
        stopSeedingAtRatio: Double = 1.0
    ) {
        self.engine = engine
        self.isDHTEnabled = isDHTEnabled
        self.isPEXEnabled = isPEXEnabled
        self.isLSDEnabled = isLSDEnabled
        self.isSequentialDownloadEnabled = isSequentialDownloadEnabled
        self.magnetMetadataTimeoutSeconds = max(1, magnetMetadataTimeoutSeconds)
        self.maxConnections = max(2, maxConnections)
        self.maxUploadSlots = max(-1, maxUploadSlots)
        self.seedingLimitMode = seedingLimitMode
        self.stopSeedingAtRatio = max(0, stopSeedingAtRatio)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            engine: try container.decodeIfPresent(TorrentEngineKind.self, forKey: .engine) ?? .swift,
            isDHTEnabled: try container.decodeIfPresent(Bool.self, forKey: .isDHTEnabled) ?? true,
            isPEXEnabled: try container.decodeIfPresent(Bool.self, forKey: .isPEXEnabled) ?? true,
            isLSDEnabled: try container.decodeIfPresent(Bool.self, forKey: .isLSDEnabled) ?? true,
            isSequentialDownloadEnabled: try container.decodeIfPresent(Bool.self, forKey: .isSequentialDownloadEnabled) ?? false,
            magnetMetadataTimeoutSeconds: try container.decodeIfPresent(Int.self, forKey: .magnetMetadataTimeoutSeconds) ?? 12,
            maxConnections: try container.decodeIfPresent(Int.self, forKey: .maxConnections) ?? 200,
            maxUploadSlots: try container.decodeIfPresent(Int.self, forKey: .maxUploadSlots) ?? 8,
            seedingLimitMode: try container.decodeIfPresent(TorrentSeedingLimitMode.self, forKey: .seedingLimitMode) ?? .stopAtRatio,
            stopSeedingAtRatio: try container.decodeIfPresent(Double.self, forKey: .stopSeedingAtRatio) ?? 1.0
        )
    }

    func shouldStopSeeding(isSeeding: Bool, shareRatio: Double, completed: Bool) -> Bool {
        switch seedingLimitMode {
        case .stopAtRatio:
            return isSeeding && stopSeedingAtRatio > 0 && shareRatio >= stopSeedingAtRatio
        case .stopWhenComplete:
            return completed
        case .neverStop:
            return false
        }
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension URL {
    func isDescendant(of ancestor: URL) -> Bool {
        let ancestorPath = ancestor.standardizedFileURL.path
        let path = standardizedFileURL.path
        guard path.hasPrefix(ancestorPath) else { return false }
        if path == ancestorPath { return true }
        return path.dropFirst(ancestorPath.count).first == "/"
    }
}

extension DateFormatter {
    static let taskLogFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
