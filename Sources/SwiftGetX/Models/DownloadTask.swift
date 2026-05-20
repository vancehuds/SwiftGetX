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
        torrentConnection: TorrentConnectionInfo? = nil
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

extension DateFormatter {
    static let taskLogFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
