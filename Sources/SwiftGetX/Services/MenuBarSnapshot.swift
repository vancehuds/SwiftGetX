import Foundation

struct MenuBarTaskSnapshot: Equatable, Identifiable {
    let id: UUID
    let name: String
    let status: DownloadStatus
    let progress: Double
    let speedBytesPerSecond: Int64
    let savePath: String
    let createdAt: Date
}

struct MenuBarSnapshot: Equatable {
    let totalCount: Int
    let runningCount: Int
    let seedingCount: Int
    let queuedCount: Int
    let pausedCount: Int
    let verifyingCount: Int
    let completedCount: Int
    let failedCount: Int
    let cancelledCount: Int
    let totalDownloadSpeed: Int64
    let activeDownloadedBytes: Int64
    let activeTotalBytes: Int64
    let aggregateProgress: Double?
    let recentTasks: [MenuBarTaskSnapshot]

    init(tasks: [DownloadTask], recentLimit: Int = 5) {
        let activeProgressTasks = tasks.filter(Self.contributesToAggregateProgress)
        totalCount = tasks.count
        runningCount = tasks.count { $0.status == .running || $0.status == .fetchingMetadata || $0.status == .fetchingPeers || $0.status == .connectingPeers }
        seedingCount = tasks.count { $0.status == .seeding }
        queuedCount = tasks.count { $0.status == .queued }
        pausedCount = tasks.count { $0.status == .paused }
        verifyingCount = tasks.count { $0.status == .verifying }
        completedCount = tasks.count { $0.status == .completed }
        failedCount = tasks.count { $0.status == .failed }
        cancelledCount = tasks.count { $0.status == .cancelled }
        totalDownloadSpeed = tasks
            .filter { $0.status == .running || $0.status == .fetchingMetadata || $0.status == .fetchingPeers || $0.status == .connectingPeers }
            .reduce(Int64(0)) { $0 + $1.speedBytesPerSecond }
        activeDownloadedBytes = activeProgressTasks.reduce(Int64(0)) { $0 + max(0, $1.downloadedBytes) }
        activeTotalBytes = activeProgressTasks.reduce(Int64(0)) { $0 + max(0, $1.totalBytes) }
        if activeTotalBytes > 0 {
            aggregateProgress = min(max(Double(activeDownloadedBytes) / Double(activeTotalBytes), 0), 1)
        } else {
            aggregateProgress = nil
        }

        recentTasks = tasks
            .sorted(by: Self.sortTasks)
            .prefix(max(0, recentLimit))
            .map {
                MenuBarTaskSnapshot(
                    id: $0.id,
                    name: $0.name,
                    status: $0.status,
                    progress: $0.progress,
                    speedBytesPerSecond: $0.speedBytesPerSecond,
                    savePath: $0.displaySavePath,
                    createdAt: $0.createdAt
                )
            }
    }

    var statusSymbolName: String {
        if runningCount > 0 {
            return "arrow.down.circle.fill"
        }
        if seedingCount > 0 {
            return "arrow.up.circle.fill"
        }
        if verifyingCount > 0 {
            return "checkmark.seal"
        }
        if queuedCount > 0 {
            return "clock"
        }
        if pausedCount > 0 {
            return "pause.circle"
        }
        if failedCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        if cancelledCount > 0 {
            return "xmark.circle.fill"
        }
        if completedCount > 0 {
            return "checkmark.circle.fill"
        }
        return "arrow.down.circle"
    }

    var activeProgressCount: Int {
        runningCount + verifyingCount
    }

    var dockBadgeLabel: String? {
        if activeProgressCount > 0 {
            return compactProgressTitle ?? "\(activeProgressCount)"
        }
        if seedingCount > 0 {
            return "↑\(seedingCount)"
        }
        if failedCount > 0 {
            return "!\(failedCount)"
        }
        if queuedCount > 0 {
            return "\(queuedCount)"
        }
        return nil
    }

    var compactProgressTitle: String? {
        guard let aggregateProgress else { return nil }
        return "\(Int((aggregateProgress * 100).rounded()))%"
    }

    private static func sortTasks(_ lhs: DownloadTask, _ rhs: DownloadTask) -> Bool {
        let lhsPriority = statusPriority(lhs.status)
        let rhsPriority = statusPriority(rhs.status)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.createdAt > rhs.createdAt
    }

    private static func statusPriority(_ status: DownloadStatus) -> Int {
        switch status {
        case .running:
            0
        case .fetchingMetadata:
            1
        case .fetchingPeers:
            2
        case .connectingPeers:
            3
        case .verifying:
            4
        case .seeding:
            5
        case .queued:
            6
        case .paused:
            7
        case .failed:
            8
        case .cancelled:
            9
        case .completed:
            10
        }
    }

    private static func contributesToAggregateProgress(_ task: DownloadTask) -> Bool {
        task.totalBytes > 0
            && (
                task.status == .running
                    || task.status == .fetchingMetadata
                    || task.status == .fetchingPeers
                    || task.status == .connectingPeers
                    || task.status == .verifying
            )
    }
}
