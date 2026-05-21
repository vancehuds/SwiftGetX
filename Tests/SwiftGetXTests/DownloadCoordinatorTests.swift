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

    @Test("queue policy settings persist through AppSettings records")
    func queuePolicySettingsPersistThroughAppSettingsRecords() {
        let settings = AppSettings()
        settings.downloadRestartPolicy = .autoResume
        settings.automaticallyRequeuesFailedTasks = true
        settings.queueFailureRetryLimit = 7

        let record = settings.makeRecord()
        #expect(record.downloadRestartPolicyRawValue == DownloadRestartPolicy.autoResume.rawValue)
        #expect(record.automaticallyRequeuesFailedTasks)
        #expect(record.queueFailureRetryLimit == 7)

        let restored = AppSettings()
        restored.apply(record)
        #expect(restored.downloadRestartPolicy == .autoResume)
        #expect(restored.automaticallyRequeuesFailedTasks)
        #expect(restored.queueFailureRetryLimit == 7)

        restored.downloadRestartPolicy = .restorePaused
        restored.automaticallyRequeuesFailedTasks = false
        restored.queueFailureRetryLimit = 1
        restored.update(record)

        #expect(record.downloadRestartPolicyRawValue == DownloadRestartPolicy.restorePaused.rawValue)
        #expect(!record.automaticallyRequeuesFailedTasks)
        #expect(record.queueFailureRetryLimit == 1)
    }

    @Test("torrent engine setting persists through AppSettings records")
    func torrentEngineSettingPersistsThroughAppSettingsRecords() {
        let settings = AppSettings()
        settings.torrentEngine = .libtorrent

        let record = settings.makeRecord()
        #expect(record.torrentEngineRawValue == TorrentEngineKind.libtorrent.rawValue)

        let restored = AppSettings()
        restored.apply(record)
        #expect(restored.torrentEngine == .libtorrent)
        #expect(restored.torrentRuntimeOptions.engine == .libtorrent)

        restored.torrentEngine = .swift
        restored.update(record)
        #expect(record.torrentEngineRawValue == TorrentEngineKind.swift.rawValue)
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
        fixture.settings.concurrentTaskLimit = 0
        fixture.coordinator.cancel(high)
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
        fixture.settings.concurrentTaskLimit = 0
        fixture.coordinator.cancel(active)
        fixture.coordinator.cancel(first)
        fixture.coordinator.cancel(second)
    }

    @Test("pausing active task fills the next queue slot")
    func pausingActiveTaskFillsNextQueueSlot() async throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 1
        let active = makeTask(name: "Active", status: .running, queuePosition: 1)
        let next = makeTask(name: "Next", queuePosition: 2)
        fixture.context.insert(active)
        fixture.context.insert(next)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.pause(active)
        await waitForStatus(next, .running)

        #expect(active.status == .paused)
        #expect(next.status == .running)
        fixture.settings.concurrentTaskLimit = 0
        fixture.coordinator.cancel(next)
    }

    @Test("cancelling active task fills the next queue slot")
    func cancellingActiveTaskFillsNextQueueSlot() async throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 1
        let active = makeTask(name: "Active", status: .running, queuePosition: 1)
        let next = makeTask(name: "Next", queuePosition: 2)
        fixture.context.insert(active)
        fixture.context.insert(next)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.cancel(active)
        await waitForStatus(next, .running)

        #expect(active.status == .cancelled)
        #expect(active.errorMessage == L10n.string("error_task_cancelled"))
        #expect(next.status == .running)
        fixture.settings.concurrentTaskLimit = 0
        fixture.coordinator.cancel(next)
    }

    @Test("removing active task fills the next queue slot")
    func removingActiveTaskFillsNextQueueSlot() async throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 1
        let active = makeTask(name: "Active", status: .running, queuePosition: 1)
        let next = makeTask(name: "Next", queuePosition: 2)
        fixture.context.insert(active)
        fixture.context.insert(next)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.remove(active, deletingFiles: false)
        await waitForStatus(next, .running)

        #expect(fixture.coordinator.allTasks().map(\.id).contains(active.id) == false)
        #expect(next.status == .running)
        fixture.settings.concurrentTaskLimit = 0
        fixture.coordinator.cancel(next)
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

    @Test("retry queues recoverable tasks and clears failure state")
    func retryQueuesRecoverableTasksAndClearsFailureState() throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 0
        let failed = makeTask(name: "Failed", status: .failed, queuePosition: 1)
        let cancelled = makeTask(name: "Cancelled", status: .cancelled, queuePosition: 2)
        let paused = makeTask(name: "Paused", status: .paused, queuePosition: 3)
        for task in [failed, cancelled, paused] {
            task.errorMessage = "Authentication expired"
            task.queueFailureCount = 2
            task.nextQueueRetryAt = .now.addingTimeInterval(60)
            fixture.context.insert(task)
        }
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        for task in [failed, cancelled, paused] {
            fixture.coordinator.retry(task)
        }

        for task in [failed, cancelled, paused] {
            #expect(task.status == .queued)
            #expect(task.errorMessage == nil)
            #expect(task.queueFailureCount == 0)
            #expect(task.nextQueueRetryAt == nil)
            #expect(task.logEntries.contains { $0.contains(L10n.string("log_retry_task")) })
            #expect(task.logEntries.contains { $0.contains(L10n.string("log_queued_for_resume")) })
        }
    }

    @Test("cancelled tasks ignore stale engine snapshots")
    func cancelledTasksIgnoreStaleEngineSnapshots() throws {
        let fixture = try makeFixture()
        let task = makeTask(name: "Cancelled", status: .cancelled, queuePosition: 1)
        task.downloadedBytes = 128
        task.errorMessage = L10n.string("error_task_cancelled")
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.apply(DownloadSnapshot(
            taskID: task.id,
            status: .failed,
            totalBytes: 4096,
            downloadedBytes: 1024,
            speedBytesPerSecond: 900,
            etaSeconds: 10,
            errorMessage: "Late failure",
            supportsResume: true,
            eTag: "\"late\"",
            lastModified: "late"
        ))

        #expect(task.status == .cancelled)
        #expect(task.downloadedBytes == 1024)
        #expect(task.speedBytesPerSecond == 0)
        #expect(task.errorMessage == L10n.string("error_task_cancelled"))
        #expect(task.totalBytes == 0)
        #expect(task.eTag == nil)
    }

    @Test("partial data actions retain delete and rename HTTP data")
    func partialDataActionsRetainDeleteAndRenameHTTPData() throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 0
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        let partURL = URL(fileURLWithPath: destination.path + ".part")
        try Data(repeating: 7, count: 2_048).write(to: partURL)
        let task = makeTask(
            name: "Payload",
            status: .failed,
            queuePosition: 1,
            savePath: destination.path
        )
        task.downloadedBytes = 128
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.retainPartialData(task)

        #expect(task.downloadedBytes == 2_048)
        #expect(FileManager.default.fileExists(atPath: partURL.path))

        fixture.coordinator.renameAndContinue(task)

        let renamedDestination = directory.appendingPathComponent("payload 2.bin")
        let renamedPartURL = URL(fileURLWithPath: renamedDestination.path + ".part")
        #expect(task.status == .queued)
        #expect(task.name == "payload 2.bin")
        #expect(task.savePath == renamedDestination.path)
        #expect(!FileManager.default.fileExists(atPath: partURL.path))
        #expect(FileManager.default.fileExists(atPath: renamedPartURL.path))

        fixture.coordinator.deletePartialData(task)

        #expect(!FileManager.default.fileExists(atPath: renamedPartURL.path))
        #expect(task.downloadedBytes == 0)
        #expect(task.logEntries.contains { $0.contains(L10n.string("log_deleted_partial_data")) })
    }

    @Test("removing task only retains HTTP partial data while deleting files removes it")
    func removingTaskOnlyRetainsHTTPPartialDataWhileDeletingFilesRemovesIt() throws {
        let retainedFixture = try makeFixture()
        let retainedDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: retainedDirectory) }
        let retainedDestination = retainedDirectory.appendingPathComponent("payload.bin")
        let retainedPartURL = URL(fileURLWithPath: retainedDestination.path + ".part")
        try Data(repeating: 3, count: 1024).write(to: retainedPartURL)
        let retainedTask = makeTask(
            name: "Retained",
            status: .failed,
            queuePosition: 1,
            savePath: retainedDestination.path
        )
        retainedFixture.context.insert(retainedTask)
        try retainedFixture.context.save()
        retainedFixture.coordinator.attach(modelContext: retainedFixture.context, settings: retainedFixture.settings)

        retainedFixture.coordinator.remove(retainedTask, deletingFiles: false)

        #expect(FileManager.default.fileExists(atPath: retainedPartURL.path))

        let deletedFixture = try makeFixture()
        let deletedDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: deletedDirectory) }
        let deletedDestination = deletedDirectory.appendingPathComponent("payload.bin")
        let deletedPartURL = URL(fileURLWithPath: deletedDestination.path + ".part")
        try Data(repeating: 4, count: 1024).write(to: deletedPartURL)
        let deletedTask = makeTask(
            name: "Deleted",
            status: .failed,
            queuePosition: 1,
            savePath: deletedDestination.path
        )
        deletedFixture.context.insert(deletedTask)
        try deletedFixture.context.save()
        deletedFixture.coordinator.attach(modelContext: deletedFixture.context, settings: deletedFixture.settings)

        deletedFixture.coordinator.remove(deletedTask, deletingFiles: true)

        #expect(!FileManager.default.fileExists(atPath: deletedPartURL.path))
    }

    @Test("torrent preview tasks persist save directory and content paths")
    func torrentPreviewTasksPersistSaveDirectoryAndContentPaths() throws {
        let fixture = try makeFixture()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        let singlePreview = TorrentMetadataPreview(
            source: "file:///tmp/single.torrent",
            kind: .torrentFile,
            displayName: "payload.bin",
            resolvedTorrentFilePath: nil,
            files: [
                TorrentFile(index: 0, path: "payload.bin", size: 42)
            ],
            totalBytes: 42,
            metadataStatus: .available,
            errorMessage: nil
        )
        let multiPreview = TorrentMetadataPreview(
            source: "file:///tmp/album.torrent",
            kind: .torrentFile,
            displayName: "album",
            resolvedTorrentFilePath: nil,
            files: [
                TorrentFile(index: 0, path: "album/a.txt", size: 10),
                TorrentFile(index: 1, path: "album/nested/b.txt", size: 20)
            ],
            totalBytes: 30,
            metadataStatus: .available,
            errorMessage: nil
        )

        let tasks = fixture.coordinator.add(
            previews: [singlePreview, multiPreview],
            saveDirectory: directory
        )
        let single = try #require(tasks.first { $0.source == singlePreview.source })
        let multi = try #require(tasks.first { $0.source == multiPreview.source })

        #expect(single.savePath == directory.path)
        #expect(single.torrentSaveDirectoryPath == directory.path)
        #expect(single.torrentOutputName == "payload.bin")
        #expect(single.torrentContentRootPath == directory.path)
        #expect(single.torrentFinalFilePath == directory.appendingPathComponent("payload.bin").path)
        #expect(single.displaySavePath == directory.appendingPathComponent("payload.bin").path)

        #expect(multi.savePath == directory.path)
        #expect(multi.torrentSaveDirectoryPath == directory.path)
        #expect(multi.torrentOutputName == "album")
        #expect(multi.torrentContentRootPath == directory.appendingPathComponent("album", isDirectory: true).path)
        #expect(multi.torrentFinalFilePath == nil)
        #expect(multi.displaySavePath == directory.appendingPathComponent("album", isDirectory: true).path)
        #expect(DownloadRequest(task: multi).savePath == directory.path)
        #expect(DownloadRequest(task: multi).torrentContentRootPath == directory.appendingPathComponent("album", isDirectory: true).path)
    }

    @Test("torrent file deletion is bounded to exact content paths")
    func torrentFileDeletionIsBoundedToExactContentPaths() throws {
        let singleFixture = try makeFixture()
        let singleDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: singleDirectory) }
        let singlePayload = singleDirectory.appendingPathComponent("payload.bin")
        let singleSibling = singleDirectory.appendingPathComponent("keep.txt")
        try Data([1]).write(to: singlePayload)
        try Data([2]).write(to: singleSibling)
        let single = DownloadTask(
            name: "payload.bin",
            source: "file:///tmp/single.torrent",
            kind: .torrentFile,
            status: .completed,
            savePath: singleDirectory.path,
            torrentSaveDirectoryPath: singleDirectory.path,
            torrentOutputName: "payload.bin",
            torrentContentRootPath: singleDirectory.path,
            torrentFinalFilePath: singlePayload.path
        )
        singleFixture.context.insert(single)
        try singleFixture.context.save()
        singleFixture.coordinator.attach(modelContext: singleFixture.context, settings: singleFixture.settings)

        singleFixture.coordinator.remove(single, deletingFiles: true)

        #expect(!FileManager.default.fileExists(atPath: singlePayload.path))
        #expect(FileManager.default.fileExists(atPath: singleSibling.path))
        #expect(FileManager.default.fileExists(atPath: singleDirectory.path))

        let multiFixture = try makeFixture()
        let multiDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: multiDirectory) }
        let contentRoot = multiDirectory.appendingPathComponent("album", isDirectory: true)
        let multiSibling = multiDirectory.appendingPathComponent("keep.txt")
        try FileManager.default.createDirectory(at: contentRoot, withIntermediateDirectories: true)
        try Data([3]).write(to: contentRoot.appendingPathComponent("a.txt"))
        try Data([4]).write(to: multiSibling)
        let multi = DownloadTask(
            name: "album",
            source: "file:///tmp/album.torrent",
            kind: .torrentFile,
            status: .completed,
            savePath: multiDirectory.path,
            torrentSaveDirectoryPath: multiDirectory.path,
            torrentOutputName: "album",
            torrentContentRootPath: contentRoot.path,
            torrentFinalFilePath: nil
        )
        multiFixture.context.insert(multi)
        try multiFixture.context.save()
        multiFixture.coordinator.attach(modelContext: multiFixture.context, settings: multiFixture.settings)

        multiFixture.coordinator.remove(multi, deletingFiles: true)

        #expect(!FileManager.default.fileExists(atPath: contentRoot.path))
        #expect(FileManager.default.fileExists(atPath: multiSibling.path))
        #expect(FileManager.default.fileExists(atPath: multiDirectory.path))
    }

    @Test("unresolved torrent deletion does not remove save directory")
    func unresolvedTorrentDeletionDoesNotRemoveSaveDirectory() throws {
        let fixture = try makeFixture()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sibling = directory.appendingPathComponent("keep.txt")
        try Data([5]).write(to: sibling)
        let task = DownloadTask(
            name: "Magnet",
            source: "magnet:?xt=urn:btih:abcdef",
            kind: .torrentMagnet,
            status: .failed,
            savePath: directory.path,
            torrentSaveDirectoryPath: directory.path,
            torrentOutputName: "Magnet"
        )
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        #expect(task.localContentDeletionURLs.isEmpty)
        #expect(task.localContentDeletionPathSummary == L10n.string("delete_task_no_known_local_content"))

        fixture.coordinator.remove(task, deletingFiles: true)

        #expect(FileManager.default.fileExists(atPath: sibling.path))
        #expect(FileManager.default.fileExists(atPath: directory.path))
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

    @Test("pauseAll and resumeAll ignore current filter and search")
    func pauseAllAndResumeAllIgnoreCurrentFilterAndSearch() throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 0
        let running = makeTask(name: "Running", status: .running, queuePosition: 1)
        let queued = makeTask(name: "Queued", status: .queued, queuePosition: 2)
        let verifying = makeTask(name: "Verifying", status: .verifying, queuePosition: 3)
        let failed = makeTask(name: "Failed", status: .failed, queuePosition: 4)
        let cancelled = makeTask(name: "Cancelled", status: .cancelled, queuePosition: 5)
        let completed = makeTask(name: "Completed", status: .completed, queuePosition: 6)
        for task in [running, queued, verifying, failed, cancelled, completed] {
            fixture.context.insert(task)
        }
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)
        fixture.coordinator.activeFilter = .completed
        fixture.coordinator.searchText = "does-not-match-any-task"

        fixture.coordinator.pauseAll()

        #expect(running.status == .paused)
        #expect(queued.status == .paused)
        #expect(verifying.status == .paused)
        #expect(failed.status == .failed)
        #expect(cancelled.status == .cancelled)
        #expect(completed.status == .completed)

        fixture.coordinator.resumeAll()

        #expect(running.status == .queued)
        #expect(queued.status == .queued)
        #expect(verifying.status == .queued)
        #expect(failed.status == .queued)
        #expect(cancelled.status == .queued)
        #expect(completed.status == .completed)
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
            coordinator: DownloadCoordinator(runsEngines: false)
        )
    }

    private func makeTask(
        name: String,
        status: DownloadStatus = .queued,
        queuePosition: Double,
        queuePriority: DownloadQueuePriority = .normal,
        savePath: String? = nil
    ) -> DownloadTask {
        DownloadTask(
            name: name,
            source: "http://127.0.0.1:1/\(name)",
            kind: .http,
            status: status,
            savePath: savePath ?? "/tmp/\(name)",
            queuePosition: queuePosition,
            queuePriority: queuePriority
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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

    private func waitForStatus(_ task: DownloadTask, _ status: DownloadStatus) async {
        for _ in 0..<20 {
            if task.status == status {
                return
            }
            await Task.yield()
        }
    }
}

private struct CoordinatorFixture {
    let container: ModelContainer
    let context: ModelContext
    let settings: AppSettings
    let coordinator: DownloadCoordinator
}
