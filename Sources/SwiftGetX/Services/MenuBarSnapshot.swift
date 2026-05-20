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
    let totalDownloadSpeed: Int64
    let recentTasks: [MenuBarTaskSnapshot]

    init(tasks: [DownloadTask], recentLimit: Int = 5) {
        totalCount = tasks.count
        runningCount = tasks.count { $0.status == .running }
        seedingCount = tasks.count { $0.status == .seeding }
        queuedCount = tasks.count { $0.status == .queued }
        pausedCount = tasks.count { $0.status == .paused }
        verifyingCount = tasks.count { $0.status == .verifying }
        completedCount = tasks.count { $0.status == .completed }
        failedCount = tasks.count { $0.status == .failed }
        totalDownloadSpeed = tasks
            .filter { $0.status == .running }
            .reduce(Int64(0)) { $0 + $1.speedBytesPerSecond }

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
                    savePath: $0.savePath,
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
        if completedCount > 0 {
            return "checkmark.circle.fill"
        }
        return "arrow.down.circle"
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
        case .verifying:
            1
        case .seeding:
            2
        case .queued:
            3
        case .paused:
            4
        case .failed:
            5
        case .completed:
            6
        }
    }
}
