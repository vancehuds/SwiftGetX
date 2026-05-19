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
            "磁力"
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
            "等待中"
        case .running:
            "下载中"
        case .paused:
            "已暂停"
        case .verifying:
            "校验中"
        case .completed:
            "已完成"
        case .failed:
            "失败"
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
    let totalBytes: Int64
    let downloadedBytes: Int64
    let speedBytesPerSecond: Int64
    let etaSeconds: TimeInterval?
    let errorMessage: String?
    let supportsResume: Bool
    let eTag: String?
    let lastModified: String?
    let torrentFiles: [TorrentFile]
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
        retryCount: Int? = nil
    ) {
        self.taskID = taskID
        self.status = status
        self.savePath = savePath
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.etaSeconds = etaSeconds
        self.errorMessage = errorMessage
        self.supportsResume = supportsResume
        self.eTag = eTag
        self.lastModified = lastModified
        self.torrentFiles = torrentFiles
        self.connectionSummary = connectionSummary
        self.retryCount = retryCount
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

extension DateFormatter {
    static let taskLogFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
