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
            makeTask(status: .running, speed: 1_000),
            makeTask(status: .running, speed: 2_500),
            makeTask(status: .queued),
            makeTask(status: .completed),
            makeTask(status: .failed)
        ]

        let snapshot = MenuBarSnapshot(tasks: tasks)

        #expect(snapshot.totalCount == 5)
        #expect(snapshot.runningCount == 2)
        #expect(snapshot.queuedCount == 1)
        #expect(snapshot.completedCount == 1)
        #expect(snapshot.failedCount == 1)
        #expect(snapshot.totalDownloadSpeed == 3_500)
        #expect(snapshot.statusSymbolName == "arrow.down.circle.fill")
    }

    @Test("recent tasks prioritize active statuses and respect limit")
    func recentTasksPrioritizeActiveStatusesAndRespectLimit() {
        let baseDate = Date(timeIntervalSince1970: 100)
        let completedNewest = makeTask(name: "completed", status: .completed, createdAt: baseDate.addingTimeInterval(60))
        let paused = makeTask(name: "paused", status: .paused, createdAt: baseDate.addingTimeInterval(10))
        let failed = makeTask(name: "failed", status: .failed, createdAt: baseDate.addingTimeInterval(20))
        let queued = makeTask(name: "queued", status: .queued, createdAt: baseDate.addingTimeInterval(30))
        let verifying = makeTask(name: "verifying", status: .verifying, createdAt: baseDate.addingTimeInterval(40))
        let running = makeTask(name: "running", status: .running, createdAt: baseDate.addingTimeInterval(50))

        let snapshot = MenuBarSnapshot(
            tasks: [completedNewest, paused, failed, queued, verifying, running],
            recentLimit: 5
        )

        #expect(snapshot.recentTasks.map(\.name) == [
            "running",
            "verifying",
            "queued",
            "paused",
            "failed"
        ])
    }

    private func makeTask(
        name: String = UUID().uuidString,
        status: DownloadStatus,
        speed: Int64 = 0,
        createdAt: Date = .now
    ) -> DownloadTask {
        DownloadTask(
            name: name,
            source: "https://example.com/\(name)",
            kind: .http,
            status: status,
            savePath: "/tmp/\(name)",
            totalBytes: 100,
            downloadedBytes: status == .completed ? 100 : 50,
            speedBytesPerSecond: speed,
            createdAt: createdAt
        )
    }
}
