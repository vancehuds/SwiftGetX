import Foundation
import Testing
@testable import SwiftGetX

@Suite("MenuBarSnapshot")
struct MenuBarSnapshotTests {
    @Test("summarizes empty task list")
    func summarizesEmptyTaskList() {
        let snapshot = MenuBarSnapshot(tasks: [])

        #expect(snapshot.totalCount == 0)
        #expect(snapshot.totalDownloadSpeed == 0)
        #expect(snapshot.statusSymbolName == "arrow.down.circle")
        #expect(snapshot.recentTasks.isEmpty)
    }

    @Test("counts states and adds running speed")
    func countsStatesAndAddsRunningSpeed() {
        let tasks = [
            makeTask(status: .running, speed: 1_000, totalBytes: 100, downloadedBytes: 25),
            makeTask(status: .running, speed: 2_500, totalBytes: 300, downloadedBytes: 75),
            makeTask(status: .seeding, speed: 900),
            makeTask(status: .queued),
            makeTask(status: .completed),
            makeTask(status: .failed),
            makeTask(status: .cancelled)
        ]

        let snapshot = MenuBarSnapshot(tasks: tasks)

        #expect(snapshot.totalCount == 7)
        #expect(snapshot.runningCount == 2)
        #expect(snapshot.seedingCount == 1)
        #expect(snapshot.queuedCount == 1)
        #expect(snapshot.completedCount == 1)
        #expect(snapshot.failedCount == 1)
        #expect(snapshot.cancelledCount == 1)
        #expect(snapshot.totalDownloadSpeed == 3_500)
        #expect(snapshot.activeDownloadedBytes == 100)
        #expect(snapshot.activeTotalBytes == 400)
        #expect(snapshot.aggregateProgress == 0.25)
        #expect(snapshot.compactProgressTitle == "25%")
        #expect(snapshot.dockBadgeLabel == "25%")
        #expect(snapshot.statusSymbolName == "arrow.down.circle.fill")
    }

    @Test("dock badge falls back to non-progress states")
    func dockBadgeFallsBackToNonProgressStates() {
        #expect(MenuBarSnapshot(tasks: [makeTask(status: .seeding)]).dockBadgeLabel == "↑1")
        #expect(MenuBarSnapshot(tasks: [makeTask(status: .failed), makeTask(status: .failed)]).dockBadgeLabel == "!2")
        #expect(MenuBarSnapshot(tasks: [makeTask(status: .queued), makeTask(status: .queued)]).dockBadgeLabel == "2")
        #expect(MenuBarSnapshot(tasks: [makeTask(status: .completed)]).dockBadgeLabel == nil)
    }

    @Test("aggregate progress includes verifying tasks and ignores unknown sizes")
    func aggregateProgressIncludesVerifyingTasksAndIgnoresUnknownSizes() {
        let snapshot = MenuBarSnapshot(tasks: [
            makeTask(status: .running, totalBytes: 0, downloadedBytes: 50),
            makeTask(status: .verifying, totalBytes: 200, downloadedBytes: 160),
            makeTask(status: .completed, totalBytes: 100, downloadedBytes: 100)
        ])

        #expect(snapshot.activeProgressCount == 2)
        #expect(snapshot.activeDownloadedBytes == 160)
        #expect(snapshot.activeTotalBytes == 200)
        #expect(snapshot.aggregateProgress == 0.8)
        #expect(snapshot.compactProgressTitle == "80%")
    }

    @Test("cancelled tasks affect status when no active tasks exist")
    func cancelledTasksAffectStatusWhenNoActiveTasksExist() {
        let snapshot = MenuBarSnapshot(tasks: [
            makeTask(status: .completed),
            makeTask(status: .cancelled)
        ])

        #expect(snapshot.cancelledCount == 1)
        #expect(snapshot.statusSymbolName == "xmark.circle.fill")
    }

    @Test("recent tasks prioritize active statuses and respect limit")
    func recentTasksPrioritizeActiveStatusesAndRespectLimit() {
        let baseDate = Date(timeIntervalSince1970: 100)
        let completedNewest = makeTask(name: "completed", status: .completed, createdAt: baseDate.addingTimeInterval(60))
        let paused = makeTask(name: "paused", status: .paused, createdAt: baseDate.addingTimeInterval(10))
        let failed = makeTask(name: "failed", status: .failed, createdAt: baseDate.addingTimeInterval(20))
        let cancelled = makeTask(name: "cancelled", status: .cancelled, createdAt: baseDate.addingTimeInterval(25))
        let queued = makeTask(name: "queued", status: .queued, createdAt: baseDate.addingTimeInterval(30))
        let seeding = makeTask(name: "seeding", status: .seeding, createdAt: baseDate.addingTimeInterval(35))
        let verifying = makeTask(name: "verifying", status: .verifying, createdAt: baseDate.addingTimeInterval(40))
        let running = makeTask(name: "running", status: .running, createdAt: baseDate.addingTimeInterval(50))

        let snapshot = MenuBarSnapshot(
            tasks: [completedNewest, paused, failed, cancelled, queued, seeding, verifying, running],
            recentLimit: 7
        )

        #expect(snapshot.recentTasks.map(\.name) == [
            "running",
            "verifying",
            "seeding",
            "queued",
            "paused",
            "failed",
            "cancelled"
        ])
    }

    private func makeTask(
        name: String = UUID().uuidString,
        status: DownloadStatus,
        speed: Int64 = 0,
        createdAt: Date = .now,
        totalBytes: Int64 = 100,
        downloadedBytes: Int64? = nil
    ) -> DownloadTask {
        DownloadTask(
            name: name,
            source: "https://example.com/\(name)",
            kind: .http,
            status: status,
            savePath: "/tmp/\(name)",
            totalBytes: totalBytes,
            downloadedBytes: downloadedBytes ?? (status == .completed ? totalBytes : totalBytes / 2),
            speedBytesPerSecond: speed,
            createdAt: createdAt
        )
    }
}
