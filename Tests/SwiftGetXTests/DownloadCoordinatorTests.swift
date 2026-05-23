import Foundation
import SwiftData
import Testing
import SwiftGetXCore
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
        settings.torrentDHTBootstrapNodes = [
            "127.0.0.1:6881",
            " dht.example:6882 ",
            "127.0.0.1:6881"
        ]

        let record = settings.makeRecord()
        #expect(record.torrentEngineRawValue == TorrentEngineKind.libtorrent.rawValue)
        #expect(record.torrentDHTBootstrapNodes == ["127.0.0.1:6881", "dht.example:6882"])

        let restored = AppSettings()
        restored.apply(record)
        #expect(restored.torrentEngine == .libtorrent)
        #expect(restored.torrentRuntimeOptions.engine == .libtorrent)
        #expect(restored.torrentRuntimeOptions.dhtBootstrapNodes == ["127.0.0.1:6881", "dht.example:6882"])

        restored.torrentEngine = .swift
        restored.torrentDHTBootstrapNodes = ["dht2.example:6883"]
        restored.update(record)
        #expect(record.torrentEngineRawValue == TorrentEngineKind.swift.rawValue)
        #expect(record.torrentDHTBootstrapNodes == ["dht2.example:6883"])
    }

    @Test("download rule and system behavior settings persist through AppSettings records")
    func downloadRuleAndSystemBehaviorSettingsPersist() throws {
        let settings = AppSettings()
        settings.downloadRules = [
            DownloadRule(
                name: "Archives",
                domains: ["*.example.com"],
                fileExtensions: ["zip"],
                minSizeBytes: 1_024,
                saveDirectoryPath: "/tmp/Archives",
                segmentCount: 6,
                retryLimit: 4,
                autoStart: false,
                filenameTemplate: "{domain}/{filename}",
                headers: [
                    BrowserDownloadHeader(name: "Accept-Language", value: "en-US"),
                    BrowserDownloadHeader(name: "Authorization", value: "Bearer secret")
                ]
            )
        ]
        settings.browserTakeoverAllowedHosts = ["Example.com", "*.Example.org"]
        settings.browserTakeoverBlockedHosts = ["blocked.example.com"]
        settings.launchAtLoginEnabled = true
        settings.keepRunningInMenuBar = false
        settings.preventSleepDuringDownloads = false
        settings.promptBeforeQuittingWithActiveTasks = false
        settings.completionSoundEnabled = true
        settings.completionRevealInFinderEnabled = true
        settings.completionOpenFileEnabled = true
        settings.completionScriptPath = "/tmp/complete.sh"

        let record = settings.makeRecord()
        let restored = AppSettings()
        restored.apply(record)

        let restoredRule = try #require(restored.downloadRules.first)
        #expect(restoredRule.name == "Archives")
        #expect(restoredRule.domains == ["example.com"])
        #expect(restoredRule.fileExtensions == ["zip"])
        #expect(restoredRule.headers == [BrowserDownloadHeader(name: "Accept-Language", value: "en-US")])
        #expect(restored.browserTakeoverAllowedHosts == ["example.com", "example.org"])
        #expect(restored.browserTakeoverBlockedHosts == ["blocked.example.com"])
        #expect(restored.launchAtLoginEnabled)
        #expect(!restored.keepRunningInMenuBar)
        #expect(!restored.preventSleepDuringDownloads)
        #expect(!restored.promptBeforeQuittingWithActiveTasks)
        #expect(restored.completionSoundEnabled)
        #expect(restored.completionRevealInFinderEnabled)
        #expect(restored.completionOpenFileEnabled)
        #expect(restored.completionScriptPath == "/tmp/complete.sh")

        restored.downloadRulesText = "domain=cdn.example.net | ext=dmg | dir=/tmp/DMG | segments=9"
        restored.browserTakeoverAllowedHostsText = "cdn.example.net\ncdn.example.net"
        restored.update(record)

        let updated = AppSettings()
        updated.apply(record)
        #expect(updated.downloadRules.first?.domains == ["cdn.example.net"])
        #expect(updated.downloadRules.first?.segmentCount == 9)
        #expect(updated.browserTakeoverAllowedHosts == ["cdn.example.net"])
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

    @Test("system policy active count ignores archived and terminal tasks")
    func systemPolicyActiveCountIgnoresArchivedAndTerminalTasks() throws {
        let fixture = try makeFixture()
        let archivedRunning = makeTask(name: "Archived Running", status: .running, queuePosition: 1)
        archivedRunning.archivedAt = .now
        let queued = makeTask(name: "Queued", status: .queued, queuePosition: 2)
        let completed = makeTask(name: "Completed", status: .completed, queuePosition: 3)
        for task in [archivedRunning, queued, completed] {
            fixture.context.insert(task)
        }
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        #expect(!fixture.coordinator.hasActiveDownloadsForSystemPolicy)

        let seeding = makeTask(name: "Seeding", status: .seeding, queuePosition: 4)
        fixture.context.insert(seeding)
        try fixture.context.save()

        #expect(fixture.coordinator.hasActiveDownloadsForSystemPolicy)

        seeding.archivedAt = .now
        try fixture.context.save()

        #expect(!fixture.coordinator.hasActiveDownloadsForSystemPolicy)

        let verifying = makeTask(name: "Verifying", status: .verifying, queuePosition: 5)
        fixture.context.insert(verifying)
        try fixture.context.save()

        #expect(fixture.coordinator.hasActiveDownloadsForSystemPolicy)

        verifying.status = .paused
        try fixture.context.save()

        #expect(!fixture.coordinator.hasActiveDownloadsForSystemPolicy)
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

    @Test("same-session browser credential tasks can retry with runtime context")
    func sameSessionBrowserCredentialTasksCanRetryWithRuntimeContext() throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 0
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)
        let context = BrowserDownloadContext(
            method: "GET",
            headers: [
                BrowserDownloadHeader(name: "Authorization", value: "Bearer session-secret", sensitive: true)
            ],
            finalURL: "https://example.com/protected.zip"
        )

        let task = try #require(fixture.coordinator.add(
            source: "https://example.com/protected.zip",
            browserContext: context
        ).first)
        task.status = .failed
        task.errorMessage = "HTTP 401"

        fixture.coordinator.retry(task)

        #expect(task.status == .queued)
        #expect(task.errorMessage == nil)
        #expect(fixture.coordinator.browserRecoveryBlockReason(for: task) == nil)
        #expect(task.browserContext?.runtimeCredentialNames == ["Authorization"])
        #expect(task.browserContextJSON?.contains("session-secret") == false)
    }

    @Test("browser credential tasks stop after restart and do not block later queue items")
    func browserCredentialTasksStopAfterRestartAndDoNotBlockQueue() throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 1
        let protected = makeTask(name: "Protected", queuePosition: 1)
        protected.browserContext = BrowserDownloadContext(
            method: "GET",
            finalURL: "https://example.com/protected.zip",
            runtimeCredentialNames: ["Authorization", "Cookie"]
        )
        let next = makeTask(name: "Next", queuePosition: 2)
        fixture.context.insert(protected)
        fixture.context.insert(next)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.scheduleQueue()

        #expect(protected.status == .failed)
        #expect(protected.errorMessage?.contains("Authorization") == true)
        #expect(protected.errorMessage?.contains("Cookie") == true)
        #expect(protected.nextQueueRetryAt == nil)
        #expect(next.status == .running)
    }

    @Test("restore stops active browser credential tasks after app restart")
    func restoreStopsActiveBrowserCredentialTasksAfterRestart() throws {
        let fixture = try makeFixture()
        fixture.settings.downloadRestartPolicy = .autoResume
        let task = makeTask(name: "Protected", status: .running, queuePosition: 1)
        task.browserContext = BrowserDownloadContext(
            method: "GET",
            finalURL: "https://example.com/protected.zip",
            runtimeCredentialNames: ["Authorization"]
        )
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.restoreIncompleteTasks()

        #expect(task.status == .failed)
        #expect(task.errorMessage?.contains("Authorization") == true)
        #expect(task.logEntries.contains { $0.contains(L10n.string("browser_recovery_session_required_short")) || $0.contains("Authorization") })
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

    @Test("failed snapshots redact persisted messages and connection text")
    func failedSnapshotsRedactPersistedMessagesAndConnectionText() throws {
        let fixture = try makeFixture()
        let task = makeTask(name: "Sensitive", status: .running, queuePosition: 1)
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.apply(DownloadSnapshot(
            taskID: task.id,
            status: .failed,
            totalBytes: 1024,
            downloadedBytes: 128,
            speedBytesPerSecond: 0,
            etaSeconds: nil,
            errorMessage: "Failed https://example.com/file.zip?token=secret Authorization: BearerSecret",
            supportsResume: false,
            eTag: nil,
            lastModified: nil,
            connectionSummary: "tracker=https://example.com/announce?passkey=secret"
        ))

        let persistedText = ([task.errorMessage, task.connectionSummary].compactMap(\.self) + task.logEntries)
            .joined(separator: "\n")
        #expect(task.status == .failed)
        #expect(persistedText.contains("secret") == false)
        #expect(persistedText.contains("BearerSecret") == false)
        #expect(persistedText.contains(BrowserDownloadContext.redactedValue))
        #expect(task.errorMessage?.contains(BrowserDownloadContext.redactedValue) == true)
        #expect(task.connectionSummary?.contains("%3Credacted%3E") == true)
        #expect(task.logEntries.contains { $0.contains(BrowserDownloadContext.redactedValue) })
    }

    @Test("snapshots update metrics segments and log export")
    func snapshotsUpdateMetricsSegmentsAndLogExport() throws {
        let fixture = try makeFixture()
        let task = makeTask(name: "Metrics", status: .running, queuePosition: 1)
        task.startedAt = Date().addingTimeInterval(-10)
        task.logEntries = [
            "[00:00:00] First",
            "[00:00:01] Second"
        ]
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.apply(DownloadSnapshot(
            taskID: task.id,
            status: .running,
            totalBytes: 1000,
            downloadedBytes: 500,
            speedBytesPerSecond: 250,
            etaSeconds: 2,
            errorMessage: nil,
            supportsResume: true,
            eTag: nil,
            lastModified: nil,
            httpSegments: [
                HTTPSegmentInfo(index: 0, startByte: 0, endByte: 499, downloadedBytes: 250, speedBytesPerSecond: 125),
                HTTPSegmentInfo(index: 1, startByte: 500, endByte: 999, downloadedBytes: 250, speedBytesPerSecond: 125)
            ]
        ))

        #expect(task.startedAt != nil)
        #expect(task.finishedAt == nil)
        #expect(task.peakSpeedBytesPerSecond == 250)
        #expect(task.averageSpeedBytesPerSecond > 0)
        #expect(task.httpSegments.count == 2)

        fixture.coordinator.apply(DownloadSnapshot(
            taskID: task.id,
            status: .completed,
            totalBytes: 1000,
            downloadedBytes: 1000,
            speedBytesPerSecond: 0,
            etaSeconds: 0,
            errorMessage: nil,
            supportsResume: true,
            eTag: nil,
            lastModified: nil,
            httpSegments: [
                HTTPSegmentInfo(index: 0, startByte: 0, endByte: 499, downloadedBytes: 500),
                HTTPSegmentInfo(index: 1, startByte: 500, endByte: 999, downloadedBytes: 500)
            ]
        ))

        #expect(task.finishedAt != nil)
        #expect(task.completedAt == task.finishedAt)
        #expect(task.httpSegments.allSatisfy { $0.progress == 1 })

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let exportedURL = try #require(fixture.coordinator.exportLogs(task, to: directory))
        let exportedText = try String(contentsOf: exportedURL, encoding: .utf8)
        #expect(exportedText.contains("First"))
        #expect(exportedText.contains("Second"))
        #expect(task.logEntries.contains { $0.contains(L10n.string("log_exported_logs", exportedURL.path)) })

        fixture.coordinator.clearLogs(task)
        #expect(task.logEntries.isEmpty)
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

    @Test("HTTP local deletion excludes destination directories")
    func httpLocalDeletionExcludesDestinationDirectories() throws {
        let fixture = try makeFixture()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destinationDirectory = directory.appendingPathComponent("payload.bin", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let nestedFile = destinationDirectory.appendingPathComponent("keep.txt")
        let partURL = URL(fileURLWithPath: destinationDirectory.path + ".part")
        try Data([1]).write(to: nestedFile)
        try Data([2]).write(to: partURL)

        let task = makeTask(
            name: "Directory",
            status: .failed,
            queuePosition: 1,
            savePath: destinationDirectory.path
        )
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        #expect(task.localContentDeletionURLs == [partURL.standardizedFileURL])

        fixture.coordinator.remove(task, deletingFiles: true)

        #expect(FileManager.default.fileExists(atPath: destinationDirectory.path))
        #expect(FileManager.default.fileExists(atPath: nestedFile.path))
        #expect(!FileManager.default.fileExists(atPath: partURL.path))
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

    @Test("torrent folder and extension priority updates keep low priority selected")
    func torrentFolderAndExtensionPriorityUpdatesKeepLowPrioritySelected() throws {
        let fixture = try makeFixture()
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = DownloadTask(
            name: "album",
            source: "file:///tmp/album.torrent",
            kind: .torrentFile,
            savePath: directory.path,
            torrentSaveDirectoryPath: directory.path,
            torrentOutputName: "album",
            torrentContentRootPath: directory.appendingPathComponent("album").path
        )
        task.torrentFiles = [
            TorrentFile(index: 0, path: "album/video.mkv", size: 10, priority: TorrentFilePriority.normal.rawValue),
            TorrentFile(index: 1, path: "album/extras/clip.mkv", size: 20, priority: TorrentFilePriority.normal.rawValue),
            TorrentFile(index: 2, path: "album/extras/readme.txt", size: 5, priority: TorrentFilePriority.normal.rawValue)
        ]
        task.selectedFileIndexes = [0, 1, 2]
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.setTorrentFolderPriority(task, folderPath: "album/extras", priority: .skip)

        #expect(task.torrentFiles.map(\.priorityLevel) == [.normal, .skip, .skip])
        #expect(task.selectedFileIndexes == [0])

        fixture.coordinator.setTorrentExtensionPriority(task, extensionFilter: "*.mkv, zip", priority: .low)

        #expect(task.torrentFiles.map(\.priorityLevel) == [.low, .low, .skip])
        #expect(task.selectedFileIndexes == [0, 1])
        #expect(task.logEntries.contains { $0.contains(L10n.string("torrent_file_priority_low")) })
    }

    @Test("batch tracker operations validate dedupe and remove trackers")
    func batchTrackerOperationsValidateDedupeAndRemoveTrackers() throws {
        let fixture = try makeFixture()
        let task = DownloadTask(
            name: "Magnet",
            source: "magnet:?xt=urn:btih:abcdef",
            kind: .torrentMagnet,
            savePath: "/tmp/Magnet"
        )
        task.torrentTrackers = [
            TorrentTrackerInfo(url: "udp://tracker.example:80", tier: 0, status: "working")
        ]
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.addTorrentTrackers(
            task,
            urlsText: """
            udp://tracker.example:80
            http://tracker.example/announce, ftp://invalid.example/announce
            https://tracker.example/announce http://tracker.example/announce
            """
        )

        #expect(task.torrentTrackers.map(\.url) == [
            "udp://tracker.example:80",
            "http://tracker.example/announce",
            "https://tracker.example/announce"
        ])
        #expect(task.logEntries.contains { $0.contains(L10n.string("log_added_trackers", 2)) })

        fixture.coordinator.removeTorrentTrackers(
            task,
            urls: [
                "udp://tracker.example:80",
                "https://missing.example/announce",
                "https://tracker.example/announce"
            ]
        )

        #expect(task.torrentTrackers.map(\.url) == ["http://tracker.example/announce"])
        #expect(task.logEntries.contains { $0.contains(L10n.string("log_removed_trackers", 2)) })
    }

    @Test("single tracker operations ignore duplicate add and missing remove")
    func singleTrackerOperationsIgnoreDuplicateAddAndMissingRemove() throws {
        let fixture = try makeFixture()
        let task = DownloadTask(
            name: "Magnet",
            source: "magnet:?xt=urn:btih:abcdef",
            kind: .torrentMagnet,
            savePath: "/tmp/Magnet"
        )
        task.torrentTrackers = [
            TorrentTrackerInfo(url: "udp://tracker.example:80", tier: 0, status: "working")
        ]
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)
        let initialLogCount = task.logEntries.count

        fixture.coordinator.addTorrentTracker(task, url: "udp://tracker.example:80")
        fixture.coordinator.removeTorrentTracker(task, url: "https://missing.example/announce")

        #expect(task.torrentTrackers.map(\.url) == ["udp://tracker.example:80"])
        #expect(task.logEntries.count == initialLogCount)
    }

    @Test("relocating torrent updates paths and moves exact known content")
    func relocatingTorrentUpdatesPathsAndMovesExactKnownContent() throws {
        let fixture = try makeFixture()
        let oldDirectory = try makeTemporaryDirectory()
        let newDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: oldDirectory)
            try? FileManager.default.removeItem(at: newDirectory)
        }
        let oldRoot = oldDirectory.appendingPathComponent("album", isDirectory: true)
        try FileManager.default.createDirectory(at: oldRoot, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: oldRoot.appendingPathComponent("a.bin"))
        try Data([4]).write(to: oldDirectory.appendingPathComponent("keep.txt"))
        let task = DownloadTask(
            name: "album",
            source: "file:///tmp/album.torrent",
            kind: .torrentFile,
            status: .running,
            savePath: oldDirectory.path,
            torrentSaveDirectoryPath: oldDirectory.path,
            torrentOutputName: "album",
            torrentContentRootPath: oldRoot.path,
            torrentFinalFilePath: nil
        )
        task.torrentFiles = [
            TorrentFile(index: 0, path: "album/a.bin", size: 3)
        ]
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.relocateTorrent(task, toSaveDirectory: newDirectory)

        let newRoot = newDirectory.appendingPathComponent("album", isDirectory: true)
        #expect(task.status == .paused)
        #expect(task.savePath == newDirectory.path)
        #expect(task.torrentSaveDirectoryPath == newDirectory.path)
        #expect(task.torrentContentRootPath == newRoot.path)
        #expect(task.torrentFinalFilePath == nil)
        #expect(try Data(contentsOf: newRoot.appendingPathComponent("a.bin")) == Data([1, 2, 3]))
        #expect(!FileManager.default.fileExists(atPath: oldRoot.path))
        #expect(FileManager.default.fileExists(atPath: oldDirectory.appendingPathComponent("keep.txt").path))
        #expect(task.logEntries.contains { $0.contains(L10n.string("log_paused_for_relocation")) })
        #expect(task.logEntries.contains { $0.contains(L10n.string("log_moved_torrent_content", 1)) })
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

    @Test("categories tags smart filters and archive behavior are consistent")
    func categoriesTagsSmartFiltersAndArchiveBehaviorAreConsistent() throws {
        let fixture = try makeFixture()
        let now = Date()
        let software = DownloadTask(
            name: "Tool.dmg",
            source: "https://github.com/example/tool/releases/download/v1/Tool.dmg",
            kind: .http,
            savePath: "/tmp/Tool.dmg",
            totalBytes: 2_000_000_000,
            createdAt: now,
            category: .software,
            tags: ["Release, Urgent", "urgent"]
        )
        let document = DownloadTask(
            name: "Manual.pdf",
            source: "https://example.com/manual.pdf",
            kind: .http,
            status: .failed,
            savePath: "/tmp/Manual.pdf",
            createdAt: now.addingTimeInterval(-3 * 24 * 60 * 60),
            category: .document,
            tags: ["Docs"]
        )
        let archived = DownloadTask(
            name: "Old.zip",
            source: "https://example.com/old.zip",
            kind: .http,
            status: .completed,
            savePath: "/tmp/Old.zip",
            createdAt: now.addingTimeInterval(-20 * 24 * 60 * 60),
            category: .software,
            archivedAt: now
        )
        for task in [software, document, archived] {
            fixture.context.insert(task)
        }
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.selectCategory(.software)
        #expect(fixture.coordinator.filteredTasks(from: [software, document, archived]).map(\.id) == [software.id])

        fixture.coordinator.selectTag("urgent")
        #expect(fixture.coordinator.filteredTasks(from: [software, document, archived]).map(\.id) == [software.id])
        #expect(software.normalizedTags == ["Release", "Urgent"])

        fixture.coordinator.selectFilter(.large)
        #expect(fixture.coordinator.filteredTasks(from: [software, document, archived]).map(\.id) == [software.id])

        fixture.coordinator.selectFilter(.needsAttention)
        #expect(fixture.coordinator.filteredTasks(from: [software, document, archived]).map(\.id) == [document.id])

        fixture.coordinator.selectFilter(.archived)
        #expect(fixture.coordinator.filteredTasks(from: [software, document, archived]).map(\.id) == [archived.id])

        fixture.coordinator.searchText = "software"
        fixture.coordinator.selectFilter(.all)
        #expect(fixture.coordinator.filteredTasks(from: [software, document, archived]).map(\.id) == [software.id])
    }

    @Test("added tasks infer categories from source and kind")
    func addedTasksInferCategoriesFromSourceAndKind() throws {
        let fixture = try makeFixture()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        let tasks = fixture.coordinator.add(
            source: """
            https://github.com/example/tool/releases/download/v1/tool.zip
            https://example.com/movie.mp4
            magnet:?xt=urn:btih:0123456789012345678901234567890123456789
            """
        )

        #expect(tasks.map(\.category) == [.software, .video, .torrent])
    }

    @Test("multi selection supports batch pause resume recheck archive and remove")
    func multiSelectionSupportsBatchOperations() throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 0
        let running = makeTask(name: "Running", status: .running, queuePosition: 1)
        let queued = makeTask(name: "Queued", status: .queued, queuePosition: 2)
        let failed = makeTask(name: "Failed", status: .failed, queuePosition: 3)
        for task in [running, queued, failed] {
            fixture.context.insert(task)
        }
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.selectOnly(running)
        fixture.coordinator.toggleSelection(queued)
        fixture.coordinator.pauseSelected()

        #expect(running.status == .paused)
        #expect(queued.status == .paused)
        #expect(failed.status == .failed)

        fixture.coordinator.toggleSelection(failed)
        fixture.coordinator.resumeSelected()

        #expect(running.status == .queued)
        #expect(queued.status == .queued)
        #expect(failed.status == .queued)

        fixture.coordinator.recheckSelected()

        #expect(running.status == .verifying)
        #expect(queued.status == .verifying)
        #expect(failed.status == .verifying)

        fixture.coordinator.archiveSelected()

        #expect(running.isArchived)
        #expect(queued.isArchived)
        #expect(failed.isArchived)
        #expect(running.status == .paused)
        #expect(fixture.coordinator.selectedTasks.isEmpty)

        fixture.coordinator.selectAllVisible([running, queued, failed])
        fixture.coordinator.unarchiveSelected()
        fixture.coordinator.removeSelected(deletingFiles: false)

        #expect(fixture.coordinator.allTasks().isEmpty)
    }

    @Test("cleanup completed and failed removes only terminal cleanup targets")
    func cleanupCompletedAndFailedRemovesOnlyTerminalCleanupTargets() throws {
        let fixture = try makeFixture()
        let completed = makeTask(name: "Completed", status: .completed, queuePosition: 1)
        let failed = makeTask(name: "Failed", status: .failed, queuePosition: 2)
        let cancelled = makeTask(name: "Cancelled", status: .cancelled, queuePosition: 3)
        let paused = makeTask(name: "Paused", status: .paused, queuePosition: 4)
        let seeding = makeTask(name: "Seeding", status: .seeding, queuePosition: 5)
        for task in [completed, failed, cancelled, paused, seeding] {
            fixture.context.insert(task)
        }
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.cleanupCompletedAndFailed(deletingFiles: false)

        #expect(fixture.coordinator.allTasks().map(\.name).sorted() == ["Paused", "Seeding"])
    }

    @Test("batch speed limit persists generic fields and HTTP fallback options")
    func batchSpeedLimitPersistsGenericFieldsAndHTTPFallbackOptions() throws {
        let fixture = try makeFixture()
        let http = makeTask(name: "HTTP", queuePosition: 1)
        let torrent = DownloadTask(
            name: "Magnet",
            source: "magnet:?xt=urn:btih:0123456789012345678901234567890123456789",
            kind: .torrentMagnet,
            savePath: "/tmp/Magnet"
        )
        fixture.context.insert(http)
        fixture.context.insert(torrent)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.selectAllVisible([http, torrent])
        fixture.coordinator.setSelectedSpeedLimit(
            downloadBytesPerSecond: 5_000_000,
            uploadBytesPerSecond: 512_000
        )

        #expect(http.perTaskDownloadLimitBytes == 5_000_000)
        #expect(http.perTaskUploadLimitBytes == 512_000)
        #expect(http.httpOptions?.perTaskDownloadLimitBytes == 5_000_000)
        #expect(torrent.perTaskDownloadLimitBytes == 5_000_000)
        #expect(torrent.perTaskUploadLimitBytes == 512_000)
        #expect(DownloadRequest(task: http).perTaskDownloadLimitBytes == 5_000_000)
        #expect(DownloadRequest(task: torrent).perTaskUploadLimitBytes == 512_000)
    }

    @Test("moving selected HTTP tasks moves final and partial local data")
    func movingSelectedHTTPTasksMovesFinalAndPartialLocalData() throws {
        let fixture = try makeFixture()
        let oldDirectory = try makeTemporaryDirectory()
        let newDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: oldDirectory)
            try? FileManager.default.removeItem(at: newDirectory)
        }
        let oldFinal = oldDirectory.appendingPathComponent("payload.bin")
        let oldPart = URL(fileURLWithPath: oldFinal.path + ".part")
        try Data([1, 2, 3]).write(to: oldFinal)
        try Data([4, 5]).write(to: oldPart)
        let task = makeTask(
            name: "payload.bin",
            status: .paused,
            queuePosition: 1,
            savePath: oldFinal.path
        )
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.selectOnly(task)
        fixture.coordinator.moveSelected(toSaveDirectory: newDirectory)

        let newFinal = newDirectory.appendingPathComponent("payload.bin")
        let newPart = URL(fileURLWithPath: newFinal.path + ".part")
        #expect(task.savePath == newFinal.path)
        #expect(task.name == "payload.bin")
        #expect(!FileManager.default.fileExists(atPath: oldFinal.path))
        #expect(!FileManager.default.fileExists(atPath: oldPart.path))
        #expect(try Data(contentsOf: newFinal) == Data([1, 2, 3]))
        #expect(try Data(contentsOf: newPart) == Data([4, 5]))
        #expect(task.logEntries.contains { $0.contains(L10n.string("log_moved_task_file", newFinal.path)) })
    }

    @Test("download rules apply save path options and auto start during task creation")
    func downloadRulesApplyToTaskCreation() throws {
        let fixture = try makeFixture()
        fixture.settings.concurrentTaskLimit = 2
        fixture.settings.downloadRules = [
            DownloadRule(
                domains: ["example.com"],
                fileExtensions: ["zip"],
                saveDirectoryPath: "/tmp/SwiftGetX Rules",
                segmentCount: 7,
                retryLimit: 2,
                autoStart: false,
                filenameTemplate: "{domain}/{filename}",
                headers: [BrowserDownloadHeader(name: "Accept-Language", value: "en-US")]
            )
        ]
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        let tasks = fixture.coordinator.add(source: "https://cdn.example.com/releases/archive.zip")
        let task = try #require(tasks.first)

        #expect(task.status == .paused)
        #expect(task.name == "archive.zip")
        #expect(task.savePath == "/tmp/SwiftGetX Rules/cdn.example.com/archive.zip")
        #expect(task.httpOptions?.segmentCountOverride == 7)
        #expect(task.httpOptions?.retryLimitOverride == 2)
        #expect(task.httpOptions?.additionalHeaders == [BrowserDownloadHeader(name: "Accept-Language", value: "en-US")])
    }

    @Test("download rules apply to HTTP metadata previews by size")
    func downloadRulesApplyToHTTPPreviewsBySize() throws {
        let fixture = try makeFixture()
        fixture.settings.downloadRules = [
            DownloadRule(
                domains: ["example.com"],
                fileExtensions: ["zip"],
                minSizeBytes: 100,
                saveDirectoryPath: "/tmp/Large",
                autoStart: false
            )
        ]
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)
        let preview = TorrentMetadataPreview(
            source: "https://example.com/archive.zip",
            kind: .http,
            displayName: "archive.zip",
            resolvedTorrentFilePath: nil,
            files: [],
            totalBytes: 512,
            metadataStatus: .available,
            errorMessage: nil,
            httpResponseMetadata: HTTPResponseMetadata(contentLength: 512),
            supportsResume: true,
            savePath: "/tmp/Fallback/archive.zip",
            duplicateStrategy: .none,
            browserContext: nil
        )

        let task = try #require(fixture.coordinator.add(previews: [preview]).first)

        #expect(task.status == DownloadStatus.paused)
        #expect(task.savePath == "/tmp/Large/archive.zip")
        #expect(task.totalBytes == 512)
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
