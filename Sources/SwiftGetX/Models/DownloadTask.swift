import Foundation
import SwiftData

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
    var selectedFileIndexes: [Int]
    var torrentFilesJSON: String?
    var connectionSummary: String?
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
        selectedFileIndexes: [Int] = [],
        torrentFilesJSON: String? = nil,
        connectionSummary: String? = nil,
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
        self.selectedFileIndexes = selectedFileIndexes
        self.torrentFilesJSON = torrentFilesJSON
        self.connectionSummary = connectionSummary
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
        status == .completed || status == .failed
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
    case paused
    case verifying
    case completed
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queued:
            L10n.string("download_status_queued")
        case .running:
            L10n.string("download_status_running")
        case .paused:
            L10n.string("download_status_paused")
        case .verifying:
            L10n.string("download_status_verifying")
        case .completed:
            L10n.string("download_status_completed")
        case .failed:
            L10n.string("download_status_failed")
        }
    }

    var symbolName: String {
        switch self {
        case .queued:
            "clock"
        case .running:
            "arrow.down.circle.fill"
        case .paused:
            "pause.circle"
        case .verifying:
            "checkmark.seal"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }
}

struct DownloadSnapshot: Sendable {
    let taskID: UUID
    let status: DownloadStatus
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
    let retryCount: Int?

    init(
        taskID: UUID,
        status: DownloadStatus,
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

    init(
        metadataStatus: TorrentMetadataStatus = .unknown,
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
        guard nativeEngineAvailable else {
            return L10n.string("torrent_native_engine_unavailable")
        }
        return L10n.string(
            "torrent_connection_summary",
            peerCount,
            Self.speedLabel(downloadRate),
            Self.speedLabel(uploadRate),
            shareRatio
        )
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

    init(
        nativeEngineAvailable: Bool = false,
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
    var isDHTEnabled: Bool
    var isPEXEnabled: Bool
    var isLSDEnabled: Bool
    var isSequentialDownloadEnabled: Bool
    var magnetMetadataTimeoutSeconds: Int
    var maxConnections: Int
    var maxUploadSlots: Int
    var seedingLimitMode: TorrentSeedingLimitMode
    var stopSeedingAtRatio: Double

    init(
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

extension DateFormatter {
    static let taskLogFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
