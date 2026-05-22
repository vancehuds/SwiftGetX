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
    var startedAt: Date?
    var completedAt: Date?
    var finishedAt: Date?
    var averageSpeedBytesPerSecond: Int64 = 0
    var peakSpeedBytesPerSecond: Int64 = 0
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
    var httpSegmentsJSON: String?
    var queuePosition: Double = 0
    var queuePriorityRawValue: String = DownloadQueuePriority.normal.rawValue
    var queueFailureCount: Int = 0
    var nextQueueRetryAt: Date?
    var categoryRawValue: String = DownloadTaskCategory.uncategorized.rawValue
    var tags: [String] = []
    var archivedAt: Date?
    var perTaskDownloadLimitBytes: Int64 = 0
    var perTaskUploadLimitBytes: Int64 = 0
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
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        finishedAt: Date? = nil,
        averageSpeedBytesPerSecond: Int64 = 0,
        peakSpeedBytesPerSecond: Int64 = 0,
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
        httpSegments: [HTTPSegmentInfo]? = nil,
        queuePosition: Double = 0,
        queuePriority: DownloadQueuePriority = .normal,
        queueFailureCount: Int = 0,
        nextQueueRetryAt: Date? = nil,
        category: DownloadTaskCategory = .uncategorized,
        tags: [String] = [],
        archivedAt: Date? = nil,
        perTaskDownloadLimitBytes: Int64 = 0,
        perTaskUploadLimitBytes: Int64 = 0,
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
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.finishedAt = finishedAt ?? completedAt
        self.averageSpeedBytesPerSecond = max(0, averageSpeedBytesPerSecond)
        self.peakSpeedBytesPerSecond = max(0, peakSpeedBytesPerSecond)
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
        self.browserContextJSON = Self.encodeBrowserContext(browserContext)
        self.httpResponseMetadataJSON = Self.encode(httpResponseMetadata)
        self.httpOptionsJSON = Self.encodeHTTPOptions(httpOptions)
        self.httpSegmentsJSON = Self.encode(httpSegments)
        self.queuePosition = queuePosition
        self.queuePriorityRawValue = queuePriority.rawValue
        self.queueFailureCount = queueFailureCount
        self.nextQueueRetryAt = nextQueueRetryAt
        self.categoryRawValue = category.rawValue
        self.tags = Self.normalizedTagList(tags)
        self.archivedAt = archivedAt
        self.perTaskDownloadLimitBytes = max(0, perTaskDownloadLimitBytes)
        self.perTaskUploadLimitBytes = max(0, perTaskUploadLimitBytes)
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
        status == .running
            || status == .fetchingMetadata
            || status == .fetchingPeers
            || status == .connectingPeers
            || status == .verifying
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

    var category: DownloadTaskCategory {
        get { DownloadTaskCategory(rawValue: categoryRawValue) ?? .uncategorized }
        set { categoryRawValue = newValue.rawValue }
    }

    var isArchived: Bool {
        archivedAt != nil
    }

    var effectiveFinishedAt: Date? {
        finishedAt ?? completedAt
    }

    var activeDurationSeconds: TimeInterval {
        guard let startedAt else { return 0 }
        let endDate = effectiveFinishedAt ?? Date()
        return max(0, endDate.timeIntervalSince(startedAt))
    }

    var normalizedTags: [String] {
        Self.normalizedTagList(tags)
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
        localContentDeletionURLs(requiresExisting: true)
    }

    var plannedTorrentContentURLs: [URL] {
        torrentContentURLs(requiresExisting: false)
    }

    func localContentDeletionURLs(requiresExisting: Bool) -> [URL] {
        guard isTorrent else {
            return FileSystemSafety.safeDeletionURLs(
                candidates: [URL(fileURLWithPath: savePath)]
                    + HTTPPartialDataStore(savePath: savePath).existingDataURLs,
                allowedRoot: URL(fileURLWithPath: savePath).deletingLastPathComponent(),
                allowsDirectories: false,
                requiresExisting: requiresExisting
            )
        }

        return torrentContentURLs(requiresExisting: requiresExisting)
    }

    private func torrentContentURLs(requiresExisting: Bool) -> [URL] {
        guard isTorrent else { return [] }
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
        return FileSystemSafety.safeDeletionURLs(
            candidates: [contentURL],
            allowedRoot: saveDirectoryURL,
            allowsDirectories: true,
            requiresExisting: requiresExisting
        )
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
        let redactedMessage = PrivacyRedactor.redactedText(message)
        logEntries.append("[\(formatter.string(from: .now))] \(redactedMessage)")
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
        set { browserContextJSON = Self.encodeBrowserContext(newValue) }
    }

    var httpResponseMetadata: HTTPResponseMetadata? {
        get { Self.decode(HTTPResponseMetadata.self, from: httpResponseMetadataJSON) }
        set { httpResponseMetadataJSON = Self.encode(newValue) }
    }

    var httpOptions: HTTPDownloadOptions? {
        get { Self.decode(HTTPDownloadOptions.self, from: httpOptionsJSON) }
        set { httpOptionsJSON = Self.encodeHTTPOptions(newValue) }
    }

    var httpSegments: [HTTPSegmentInfo] {
        get { Self.decode([HTTPSegmentInfo].self, from: httpSegmentsJSON) ?? [] }
        set { httpSegmentsJSON = Self.encode(newValue.sorted { $0.index < $1.index }) }
    }

    @discardableResult
    func repairInvalidJSONFields() -> [String] {
        var repaired = [String]()
        repairSensitiveTextField(\.errorMessage, name: "errorMessage", repaired: &repaired)
        repairSensitiveTextField(\.connectionSummary, name: "connectionSummary", repaired: &repaired)
        let redactedLogEntries = logEntries.map(PrivacyRedactor.redactedText)
        if redactedLogEntries != logEntries {
            logEntries = redactedLogEntries
            repaired.append("logEntries")
        }
        repairInvalidJSONField(
            \.torrentFilesJSON,
            as: [TorrentFile].self,
            name: "torrentFilesJSON",
            repaired: &repaired
        )
        repairInvalidJSONField(
            \.torrentConnectionJSON,
            as: TorrentConnectionInfo.self,
            name: "torrentConnectionJSON",
            repaired: &repaired
        )
        repairInvalidJSONField(
            \.torrentResumeStateJSON,
            as: TorrentResumeState.self,
            name: "torrentResumeStateJSON",
            repaired: &repaired
        )
        repairInvalidJSONField(
            \.torrentTrackersJSON,
            as: [TorrentTrackerInfo].self,
            name: "torrentTrackersJSON",
            repaired: &repaired
        )
        repairInvalidJSONField(
            \.torrentPeersJSON,
            as: [TorrentPeerInfo].self,
            name: "torrentPeersJSON",
            repaired: &repaired
        )
        repairInvalidJSONField(
            \.torrentRuntimeOptionsJSON,
            as: TorrentRuntimeOptions.self,
            name: "torrentRuntimeOptionsJSON",
            repaired: &repaired
        )
        repairInvalidJSONField(
            \.torrentHealthJSON,
            as: TorrentHealthInfo.self,
            name: "torrentHealthJSON",
            repaired: &repaired
        )
        repairInvalidJSONField(
            \.browserContextJSON,
            as: BrowserDownloadContext.self,
            name: "browserContextJSON",
            repaired: &repaired
        )
        sanitizeJSONField(
            \.browserContextJSON,
            as: BrowserDownloadContext.self,
            name: "browserContextJSON",
            repaired: &repaired
        ) { $0.persistable }
        repairInvalidJSONField(
            \.httpResponseMetadataJSON,
            as: HTTPResponseMetadata.self,
            name: "httpResponseMetadataJSON",
            repaired: &repaired
        )
        sanitizeJSONField(
            \.httpResponseMetadataJSON,
            as: HTTPResponseMetadata.self,
            name: "httpResponseMetadataJSON",
            repaired: &repaired,
            sanitize: Self.sanitizedHTTPResponseMetadata
        )
        repairInvalidJSONField(
            \.httpOptionsJSON,
            as: HTTPDownloadOptions.self,
            name: "httpOptionsJSON",
            repaired: &repaired
        )
        sanitizeJSONField(
            \.httpOptionsJSON,
            as: HTTPDownloadOptions.self,
            name: "httpOptionsJSON",
            repaired: &repaired
        ) { $0.persistable }
        repairInvalidJSONField(
            \.httpSegmentsJSON,
            as: [HTTPSegmentInfo].self,
            name: "httpSegmentsJSON",
            repaired: &repaired
        )
        return repaired
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

    private static func encodeBrowserContext(_ context: BrowserDownloadContext?) -> String? {
        guard let context else { return nil }
        return encode(context.persistable)
    }

    private static func encodeHTTPOptions(_ options: HTTPDownloadOptions?) -> String? {
        guard let persistable = options?.persistable, !persistable.isEmpty else {
            return nil
        }
        return encode(persistable)
    }

    private func repairSensitiveTextField(
        _ keyPath: ReferenceWritableKeyPath<DownloadTask, String?>,
        name: String,
        repaired: inout [String]
    ) {
        guard let value = self[keyPath: keyPath] else { return }
        let redacted = PrivacyRedactor.redactedText(value)
        if redacted != value {
            self[keyPath: keyPath] = redacted
            repaired.append(name)
        }
    }

    private func repairInvalidJSONField<Value: Decodable>(
        _ keyPath: ReferenceWritableKeyPath<DownloadTask, String?>,
        as type: Value.Type,
        name: String,
        repaired: inout [String]
    ) {
        guard let json = self[keyPath: keyPath]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !json.isEmpty,
              let data = json.data(using: .utf8),
              (try? JSONDecoder().decode(type, from: data)) == nil
        else {
            return
        }
        self[keyPath: keyPath] = nil
        repaired.append(name)
    }

    private func sanitizeJSONField<Value: Codable & Equatable>(
        _ keyPath: ReferenceWritableKeyPath<DownloadTask, String?>,
        as type: Value.Type,
        name: String,
        repaired: inout [String],
        sanitize: (Value) -> Value
    ) {
        guard let json = self[keyPath: keyPath]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !json.isEmpty,
              let value = Self.decode(type, from: json)
        else {
            return
        }
        let sanitized = sanitize(value)
        guard sanitized != value || Self.encode(sanitized) != json else { return }
        self[keyPath: keyPath] = Self.encode(sanitized)
        repaired.append("\(name).sanitized")
    }

    private static func sanitizedHTTPResponseMetadata(_ metadata: HTTPResponseMetadata) -> HTTPResponseMetadata {
        HTTPResponseMetadata(
            originalURL: metadata.originalURL,
            finalURL: metadata.finalURL,
            sourcePageURL: metadata.sourcePageURL,
            mimeType: metadata.mimeType,
            contentDisposition: metadata.contentDisposition,
            suggestedFilename: metadata.suggestedFilename,
            server: metadata.server,
            supportsResume: metadata.supportsResume,
            contentLength: metadata.contentLength,
            eTag: metadata.eTag,
            lastModified: metadata.lastModified,
            redirects: metadata.redirects.map {
                HTTPRedirectMetadata(statusCode: $0.statusCode, fromURL: $0.fromURL, toURL: $0.toURL)
            },
            checksumStatus: metadata.checksumStatus,
            checksumActualDigest: metadata.checksumActualDigest
        )
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

    static func normalizedTagList(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags
            .flatMap { tag in
                tag.components(separatedBy: CharacterSet(charactersIn: ",;"))
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
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
    case fetchingMetadata
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
        case .fetchingMetadata:
            L10n.string("download_status_fetching_metadata")
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
        case .fetchingMetadata:
            "doc.text.magnifyingglass"
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

    var usesActiveClock: Bool {
        switch self {
        case .running, .fetchingMetadata, .fetchingPeers, .connectingPeers, .verifying:
            true
        case .queued, .seeding, .paused, .completed, .failed, .cancelled:
            false
        }
    }

    var isTerminalForMetrics: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            true
        case .queued, .running, .fetchingMetadata, .fetchingPeers, .connectingPeers, .seeding, .paused, .verifying:
            false
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

enum DownloadTaskCategory: String, Codable, CaseIterable, Identifiable {
    case uncategorized
    case software
    case video
    case document
    case torrent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uncategorized:
            L10n.string("category_uncategorized")
        case .software:
            L10n.string("category_software")
        case .video:
            L10n.string("category_video")
        case .document:
            L10n.string("category_document")
        case .torrent:
            "BT"
        }
    }

    var symbolName: String {
        switch self {
        case .uncategorized:
            "tray"
        case .software:
            "shippingbox"
        case .video:
            "play.rectangle"
        case .document:
            "doc.text"
        case .torrent:
            "point.3.connected.trianglepath.dotted"
        }
    }

    static func inferred(kind: DownloadKind, source: String, filename: String) -> DownloadTaskCategory {
        if kind == .torrentMagnet || kind == .torrentFile {
            return .torrent
        }
        let extensionValue = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let lowerSource = source.lowercased()
        if ["dmg", "pkg", "app", "zip", "xip", "msi", "exe", "deb", "rpm"].contains(extensionValue) {
            return .software
        }
        if ["mp4", "mkv", "mov", "avi", "webm", "m4v", "mp3", "flac", "wav", "m3u8", "mpd"].contains(extensionValue) {
            return .video
        }
        if ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "epub"].contains(extensionValue) {
            return .document
        }
        if lowerSource.contains("github.com") || lowerSource.contains("gitlab.com") {
            return .software
        }
        return .uncategorized
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
    let httpSegments: [HTTPSegmentInfo]?
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
        httpSegments: [HTTPSegmentInfo]? = nil,
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
        self.httpSegments = httpSegments
        self.retryCount = retryCount
    }
}

struct HTTPSegmentInfo: Codable, Identifiable, Equatable, Sendable {
    var index: Int
    var startByte: Int64
    var endByte: Int64
    var downloadedBytes: Int64
    var speedBytesPerSecond: Int64
    var retryCount: Int

    var id: Int { index }

    init(
        index: Int,
        startByte: Int64,
        endByte: Int64,
        downloadedBytes: Int64 = 0,
        speedBytesPerSecond: Int64 = 0,
        retryCount: Int = 0
    ) {
        let boundedStart = max(0, startByte)
        let boundedEnd = max(boundedStart, endByte)
        let boundedLength = max(0, boundedEnd - boundedStart + 1)
        self.index = index
        self.startByte = boundedStart
        self.endByte = boundedEnd
        self.downloadedBytes = min(max(0, downloadedBytes), boundedLength)
        self.speedBytesPerSecond = max(0, speedBytesPerSecond)
        self.retryCount = max(0, retryCount)
    }

    var length: Int64 {
        max(0, endByte - startByte + 1)
    }

    var progress: Double {
        guard length > 0 else { return 0 }
        return min(max(Double(downloadedBytes) / Double(length), 0), 1)
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
        get { TorrentFilePriority(rawValue: priority) ?? TorrentFilePriority.fromEnginePriority(priority) }
        set { priority = newValue.rawValue }
    }

    var torrentFileInfo: TorrentFileInfo {
        TorrentFileInfo(index: index, path: path, length: size)
    }
}

enum TorrentFilePriority: Int, Codable, CaseIterable, Identifiable, Sendable {
    case skip = 0
    case low = -1
    case normal = 1
    case high = 2
    case maximum = 7

    var id: Int { rawValue }

    var isWanted: Bool {
        self != .skip
    }

    var enginePriority: Int {
        switch self {
        case .skip:
            0
        case .low:
            1
        case .normal:
            4
        case .high:
            6
        case .maximum:
            7
        }
    }

    static func fromEnginePriority(_ priority: Int) -> TorrentFilePriority {
        switch priority {
        case ...0:
            .skip
        case 1:
            .low
        case 2...5:
            .normal
        case 6:
            .high
        default:
            .maximum
        }
    }

    var title: String {
        switch self {
        case .low:
            L10n.string("torrent_file_priority_low")
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
    var seedingDurationSeconds: TimeInterval
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
        case seedingDurationSeconds
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
        seedingDurationSeconds: TimeInterval = 0,
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
        self.seedingDurationSeconds = max(0, seedingDurationSeconds)
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
        seedingDurationSeconds = max(
            0,
            try container.decodeIfPresent(TimeInterval.self, forKey: .seedingDurationSeconds) ?? 0
        )
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
    var source: String? = nil

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
    var trackerPeerCount: Int
    var dhtPeerCount: Int
    var pexPeerCount: Int
    var lsdPeerCount: Int
    var seedingDurationSeconds: TimeInterval
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
        case trackerPeerCount
        case dhtPeerCount
        case pexPeerCount
        case lsdPeerCount
        case seedingDurationSeconds
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
        trackerPeerCount: Int = 0,
        dhtPeerCount: Int = 0,
        pexPeerCount: Int = 0,
        lsdPeerCount: Int = 0,
        seedingDurationSeconds: TimeInterval = 0,
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
        self.trackerPeerCount = trackerPeerCount
        self.dhtPeerCount = dhtPeerCount
        self.pexPeerCount = pexPeerCount
        self.lsdPeerCount = lsdPeerCount
        self.seedingDurationSeconds = max(0, seedingDurationSeconds)
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
        trackerPeerCount = try container.decodeIfPresent(Int.self, forKey: .trackerPeerCount) ?? 0
        dhtPeerCount = try container.decodeIfPresent(Int.self, forKey: .dhtPeerCount) ?? 0
        pexPeerCount = try container.decodeIfPresent(Int.self, forKey: .pexPeerCount) ?? 0
        lsdPeerCount = try container.decodeIfPresent(Int.self, forKey: .lsdPeerCount) ?? 0
        seedingDurationSeconds = max(
            0,
            try container.decodeIfPresent(TimeInterval.self, forKey: .seedingDurationSeconds) ?? 0
        )
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
    case stopAfterTime
    case stopWhenComplete
    case neverStop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stopAtRatio:
            L10n.string("torrent_seeding_mode_ratio")
        case .stopAfterTime:
            L10n.string("torrent_seeding_mode_time")
        case .stopWhenComplete:
            L10n.string("torrent_seeding_mode_complete")
        case .neverStop:
            L10n.string("torrent_seeding_mode_never")
        }
    }
}

struct TorrentRuntimeOptions: Codable, Equatable, Sendable {
    static let defaultDHTBootstrapNodes = [
        "router.bittorrent.com:6881",
        "dht.transmissionbt.com:6881",
        "router.utorrent.com:6881"
    ]

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
    var stopSeedingAfterSeconds: TimeInterval
    var dhtBootstrapNodes: [String]

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
        case stopSeedingAfterSeconds
        case dhtBootstrapNodes
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
        stopSeedingAtRatio: Double = 1.0,
        stopSeedingAfterSeconds: TimeInterval = 3600,
        dhtBootstrapNodes: [String] = TorrentRuntimeOptions.defaultDHTBootstrapNodes
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
        self.stopSeedingAfterSeconds = max(0, stopSeedingAfterSeconds)
        self.dhtBootstrapNodes = Self.normalizedBootstrapNodes(dhtBootstrapNodes)
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
            stopSeedingAtRatio: try container.decodeIfPresent(Double.self, forKey: .stopSeedingAtRatio) ?? 1.0,
            stopSeedingAfterSeconds: try container.decodeIfPresent(TimeInterval.self, forKey: .stopSeedingAfterSeconds) ?? 3600,
            dhtBootstrapNodes: try container.decodeIfPresent([String].self, forKey: .dhtBootstrapNodes)
                ?? Self.defaultDHTBootstrapNodes
        )
    }

    func shouldStopSeeding(
        isSeeding: Bool,
        shareRatio: Double,
        completed: Bool,
        seedingDurationSeconds: TimeInterval = 0
    ) -> Bool {
        switch seedingLimitMode {
        case .stopAtRatio:
            return isSeeding && shareRatio >= stopSeedingAtRatio
        case .stopAfterTime:
            return isSeeding && seedingDurationSeconds >= stopSeedingAfterSeconds
        case .stopWhenComplete:
            return completed
        case .neverStop:
            return false
        }
    }

    var seedingPolicyDescription: String {
        switch seedingLimitMode {
        case .stopAtRatio:
            L10n.string("stop_seeding_ratio_message", stopSeedingAtRatio)
        case .stopAfterTime:
            L10n.string("stop_seeding_time_message", TimeFormatter.eta(stopSeedingAfterSeconds))
        case .stopWhenComplete:
            TorrentSeedingLimitMode.stopWhenComplete.title
        case .neverStop:
            TorrentSeedingLimitMode.neverStop.title
        }
    }

    private static func normalizedBootstrapNodes(_ nodes: [String]) -> [String] {
        var seen = Set<String>()
        return nodes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension DateFormatter {
    static let taskLogFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
