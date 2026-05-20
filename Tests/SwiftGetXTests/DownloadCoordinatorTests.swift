import Foundation
import SwiftData
import Testing
@testable import SwiftGetX

@Suite("DownloadCoordinator", .serialized)
@MainActor
struct DownloadCoordinatorTests {
    @Test("toolbar speed limit persists through AppSettings")
    func toolbarSpeedLimitPersistsThroughAppSettings() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DownloadTask.self,
            AppSettingsRecord.self,
            configurations: configuration
        )
        let settings = AppSettings()
        let coordinator = DownloadCoordinator()
        coordinator.attach(modelContext: container.mainContext, settings: settings)

        coordinator.setSpeedLimit(
            downloadBytesPerSecond: 5_000_000,
            uploadBytesPerSecond: 512_000,
            persistsToSettings: true
        )

        let descriptor = FetchDescriptor<AppSettingsRecord>(
            predicate: #Predicate { $0.id == "default" }
        )
        let record = try #require(container.mainContext.fetch(descriptor).first)

        #expect(settings.globalDownloadLimitBytes == 5_000_000)
        #expect(settings.globalUploadLimitBytes == 512_000)
        #expect(record.globalDownloadLimitBytes == 5_000_000)
        #expect(record.globalUploadLimitBytes == 512_000)
        #expect(coordinator.downloadLimitBytes == 5_000_000)
        #expect(coordinator.uploadLimitBytes == 512_000)
    }

    @Test("allTasks returns more than the old 500 task cap")
    func allTasksReturnsMoreThanOldFetchLimit() throws {
        let fixture = try makeFixture()
        for index in 0..<501 {
            fixture.context.insert(makeTask(name: "Task \(index)", queuePosition: Double(index + 1)))
        }
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        #expect(fixture.coordinator.allTasks().count == 501)
    }

    @Test("queue scheduling prefers priority then queue position")
    func queueSchedulingPrefersPriorityThenPosition() throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 1
        let low = makeTask(name: "Low", queuePosition: 1, queuePriority: .low)
        let high = makeTask(name: "High", queuePosition: 3, queuePriority: .high)
        let normal = makeTask(name: "Normal", queuePosition: 2, queuePriority: .normal)
        fixture.context.insert(low)
        fixture.context.insert(high)
        fixture.context.insert(normal)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.scheduleQueue()

        #expect(high.status == .running)
        #expect(normal.status == .queued)
        #expect(low.status == .queued)
    }

    @Test("reloadSettings fills newly available queue slots")
    func reloadSettingsFillsNewlyAvailableQueueSlots() throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 1
        let active = makeTask(name: "Active", status: .running, queuePosition: 1)
        let first = makeTask(name: "First", queuePosition: 2)
        let second = makeTask(name: "Second", queuePosition: 3)
        fixture.context.insert(active)
        fixture.context.insert(first)
        fixture.context.insert(second)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.settings.concurrentTaskLimit = 3
        fixture.coordinator.reloadSettings(fixture.settings)

        #expect(active.status == .running)
        #expect(first.status == .running)
        #expect(second.status == .running)
    }

    @Test("failed tasks can be requeued with backoff up to the retry limit")
    func failedTasksCanBeRequeuedWithBackoff() throws {
        let fixture = try makeFixture()
        fixture.settings.automaticallyRequeuesFailedTasks = true
        fixture.settings.queueFailureRetryLimit = 2
        fixture.settings.concurrentTaskLimit = 0
        let task = makeTask(name: "Retry", status: .running, queuePosition: 1)
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.apply(failureSnapshot(for: task, message: "Transient failure"))

        #expect(task.status == .queued)
        #expect(task.queueFailureCount == 1)
        #expect(task.errorMessage == "Transient failure")
        #expect(task.nextQueueRetryAt != nil)
        #expect(task.logEntries.contains { $0.contains("Retry 1") })

        task.status = .running
        fixture.coordinator.apply(failureSnapshot(for: task, message: "Still failing"))

        #expect(task.status == .queued)
        #expect(task.queueFailureCount == 2)
        #expect(task.nextQueueRetryAt != nil)

        task.status = .running
        fixture.coordinator.apply(failureSnapshot(for: task, message: "Limit reached"))

        #expect(task.status == .failed)
        #expect(task.queueFailureCount == 2)
        #expect(task.nextQueueRetryAt == nil)
        #expect(task.logEntries.contains { $0.contains("Limit reached") })
    }

    @Test("restart policy queues unfinished active tasks")
    func restartPolicyQueuesUnfinishedActiveTasks() throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 0
        fixture.settings.downloadRestartPolicy = .autoResume
        let running = makeTask(name: "Running", status: .running, queuePosition: 1)
        let verifying = makeTask(name: "Verifying", status: .verifying, queuePosition: 2)
        let seeding = makeTask(name: "Seeding", status: .seeding, queuePosition: 3)
        let completed = makeTask(name: "Completed", status: .completed, queuePosition: 4)
        for task in [running, verifying, seeding, completed] {
            fixture.context.insert(task)
        }
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.restoreIncompleteTasks()

        #expect(running.status == .queued)
        #expect(verifying.status == .queued)
        #expect(seeding.status == .queued)
        #expect(completed.status == .completed)
        #expect(running.nextQueueRetryAt == nil)
        #expect(running.logEntries.contains { $0.contains(L10n.string("log_restored_queued_after_restart")) })
    }

    @Test("queue move and priority controls update sorted order")
    func queueMoveAndPriorityControlsUpdateSortedOrder() throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 0
        let first = makeTask(name: "First", queuePosition: 1)
        let second = makeTask(name: "Second", queuePosition: 2)
        let third = makeTask(name: "Third", queuePosition: 3)
        for task in [first, second, third] {
            fixture.context.insert(task)
        }
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.moveQueueItemUp(third)
        #expect(queueNames(fixture.coordinator) == ["First", "Third", "Second"])

        fixture.coordinator.moveQueueItemToTop(second)
        #expect(queueNames(fixture.coordinator) == ["Second", "First", "Third"])

        fixture.coordinator.setQueuePriority(third, priority: .high)
        #expect(queueNames(fixture.coordinator) == ["Third", "Second", "First"])
        #expect(third.queuePriority == .high)
    }

    private func makeFixture() throws -> CoordinatorFixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: DownloadTask.self,
            AppSettingsRecord.self,
            configurations: configuration
        )
        return CoordinatorFixture(
            container: container,
            context: container.mainContext,
            settings: AppSettings(),
            coordinator: DownloadCoordinator()
        )
    }

    private func makeTask(
        name: String,
        status: DownloadStatus = .queued,
        queuePosition: Double,
        queuePriority: DownloadQueuePriority = .normal
    ) -> DownloadTask {
        DownloadTask(
            name: name,
            source: "http://127.0.0.1/\(name)",
            kind: .http,
            status: status,
            savePath: "/tmp/\(name)",
            queuePosition: queuePosition,
            queuePriority: queuePriority
        )
    }

    private func failureSnapshot(for task: DownloadTask, message: String) -> DownloadSnapshot {
        DownloadSnapshot(
            taskID: task.id,
            status: .failed,
            totalBytes: task.totalBytes,
            downloadedBytes: task.downloadedBytes,
            speedBytesPerSecond: 0,
            etaSeconds: nil,
            errorMessage: message,
            supportsResume: task.supportsResume,
            eTag: task.eTag,
            lastModified: task.lastModified
        )
    }

    private func queueNames(_ coordinator: DownloadCoordinator) -> [String] {
        coordinator.allTasks()
            .filter(\.isQueueManageable)
            .map(\.name)
    }
}

private struct CoordinatorFixture {
    let container: ModelContainer
    let context: ModelContext
    let settings: AppSettings
    let coordinator: DownloadCoordinator
}
