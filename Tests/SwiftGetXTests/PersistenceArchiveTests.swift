import Foundation
import SwiftData
import Testing
import SwiftGetXCore
@testable import SwiftGetX

@Suite("PersistenceArchive", .serialized)
@MainActor
struct PersistenceArchiveTests {
    @Test("versioned SwiftData container opens with current schema")
    func versionedSwiftDataContainerOpensWithCurrentSchema() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try SwiftGetXPersistence.makeModelContainer(configurations: configuration)

        #expect(SwiftGetXPersistence.currentSchemaVersion == "2.0.0")
        #expect(container.mainContext.container === container)
    }

    @Test("versioned SwiftData container opens legacy unversioned stores")
    func versionedSwiftDataContainerOpensLegacyUnversionedStores() throws {
        let storeURL = try makeTemporaryDirectory().appendingPathComponent("legacy.store")
        do {
            let legacyConfiguration = ModelConfiguration(url: storeURL)
            let legacyContainer = try ModelContainer(
                for: DownloadTask.self,
                AppSettingsRecord.self,
                configurations: legacyConfiguration
            )
            legacyContainer.mainContext.insert(DownloadTask(
                name: "legacy",
                source: "https://example.com/legacy.zip",
                kind: .http,
                savePath: "/tmp/legacy.zip"
            ))
            try legacyContainer.mainContext.save()
        }

        let configuration = ModelConfiguration(url: storeURL)
        let migratedContainer = try SwiftGetXPersistence.makeModelContainer(configurations: configuration)
        let tasks = try migratedContainer.mainContext.fetch(FetchDescriptor<DownloadTask>())

        #expect(tasks.map(\.name) == ["legacy"])
    }

    @Test("repairs invalid optional JSON fields and settings schema")
    func repairsInvalidOptionalJSONFieldsAndSettingsSchema() throws {
        let fixture = try makeFixture()
        let record = fixture.settings.makeRecord()
        record.schemaVersion = 1
        record.downloadRulesJSON = "{not-json"
        fixture.context.insert(record)
        let task = DownloadTask(
            name: "corrupt",
            source: "https://example.com/file.zip",
            kind: .http,
            savePath: "/tmp/file.zip"
        )
        task.errorMessage = "Failed https://example.com/file.zip?token=secret Authorization: BearerSecret"
        task.connectionSummary = "tracker=https://example.com/announce?passkey=secret"
        task.logEntries = ["GET https://example.com/file.zip?session=secret Cookie: session=secret"]
        task.browserContextJSON = "{not-json"
        task.httpOptionsJSON = "{not-json"
        task.httpSegmentsJSON = "{not-json"
        task.torrentTrackersJSON = "[]"
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        #expect(record.schemaVersion == SwiftGetXDataSchema.currentModelVersion)
        #expect(record.downloadRulesJSON == "[]")
        #expect(task.browserContextJSON == nil)
        #expect(task.httpOptionsJSON == nil)
        #expect(task.httpSegmentsJSON == nil)
        #expect(task.torrentTrackersJSON == "[]")
        #expect(task.errorMessage?.contains("secret") == false)
        #expect(task.connectionSummary?.contains("secret") == false)
        #expect(task.logEntries.joined().contains("secret") == false)

        record.schemaVersion = 1
        record.downloadRulesJSON = "{not-json"
        task.browserContextJSON = "{not-json"
        task.errorMessage = "Authorization: BearerSecret"
        try fixture.context.save()
        let repairs = fixture.coordinator.repairPersistedData()

        #expect(repairs.contains { $0.contains("settings.schemaVersion") })
        #expect(repairs.contains { $0.contains("settings.downloadRulesJSON") })
        #expect(repairs.contains { $0.contains("browserContextJSON") })
        #expect(repairs.contains { $0.contains("errorMessage") })
    }

    @Test("repairs valid legacy JSON that persisted sensitive headers")
    func repairsValidLegacyJSONWithSensitiveHeaders() throws {
        let fixture = try makeFixture()
        let record = fixture.settings.makeRecord()
        record.downloadRulesJSON = """
        [
          {
            "domains": ["example.com"],
            "headers": [
              {"name": "Authorization", "value": "Bearer rule-secret", "sensitive": true},
              {"name": "Accept-Language", "value": "en-US", "sensitive": false}
            ]
          }
        ]
        """
        fixture.context.insert(record)
        let task = DownloadTask(
            name: "legacy",
            source: "https://example.com/file.zip",
            kind: .http,
            savePath: "/tmp/legacy.zip"
        )
        task.browserContextJSON = """
        {
          "headers": [
            {"name": "Authorization", "value": "Bearer browser-secret", "sensitive": true},
            {"name": "Accept-Language", "value": "en-US", "sensitive": false}
          ],
          "finalURL": "https://cdn.example.com/file.zip?token=browser-secret"
        }
        """
        task.httpOptionsJSON = """
        {
          "additionalHeaders": [
            {"name": "Cookie", "value": "session=http-secret", "sensitive": true},
            {"name": "Accept-Language", "value": "en-US", "sensitive": false}
          ],
          "segmentCountOverride": 4
        }
        """
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        let rules = try JSONDecoder().decode([DownloadRule].self, from: Data(record.downloadRulesJSON.utf8))

        #expect(rules.first?.headers == [BrowserDownloadHeader(name: "Accept-Language", value: "en-US")])
        #expect(task.browserContext?.headers == [BrowserDownloadHeader(name: "Accept-Language", value: "en-US")])
        #expect(task.browserContext?.finalURL == "https://cdn.example.com/file.zip?token=%3Credacted%3E")
        #expect(task.httpOptions?.additionalHeaders == [BrowserDownloadHeader(name: "Accept-Language", value: "en-US")])
        #expect(task.httpOptions?.segmentCountOverride == 4)
        #expect(record.downloadRulesJSON.contains("rule-secret") == false)
        #expect(task.browserContextJSON?.contains("browser-secret") == false)
        #expect(task.httpOptionsJSON?.contains("http-secret") == false)
    }

    @Test("data archive redacts sensitive task values and imports sanitized records")
    func dataArchiveRedactsSensitiveTaskValuesAndImports() throws {
        let fixture = try makeFixture()
        let settingsRecord = fixture.settings.makeRecord()
        fixture.context.insert(settingsRecord)
        let task = DownloadTask(
            name: "file.zip",
            source: "https://example.com/file.zip?token=secret&ok=1",
            kind: .http,
            savePath: "/tmp/file.zip",
            browserContext: BrowserDownloadContext(
                referrer: "https://example.com/page?auth=secret",
                headers: [
                    BrowserDownloadHeader(name: "Authorization", value: "Bearer secret", sensitive: true),
                    BrowserDownloadHeader(name: "Accept-Language", value: "en-US")
                ],
                finalURL: "https://cdn.example.com/file.zip?signature=secret"
            ).persistable,
            httpOptions: HTTPDownloadOptions(
                additionalHeaders: [
                    BrowserDownloadHeader(name: "Authorization", value: "Bearer secret", sensitive: true),
                    BrowserDownloadHeader(name: "Accept-Language", value: "en-US")
                ]
            )
        )
        task.logEntries = [
            "GET https://example.com/file.zip?token=secret Authorization: BearerSecret"
        ]
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        let exportURL = try makeTemporaryDirectory().appendingPathComponent("swiftgetx-export.json")
        try fixture.coordinator.exportDataArchive(to: exportURL)
        let exportedText = try String(contentsOf: exportURL, encoding: .utf8)

        #expect(!exportedText.contains("token=secret"))
        #expect(!exportedText.contains("signature=secret"))
        #expect(!exportedText.contains("Bearer secret"))
        #expect(!exportedText.contains("BearerSecret"))
        #expect(exportedText.contains("%3Credacted%3E"))

        let imported = try makeFixture()
        imported.coordinator.attach(modelContext: imported.context, settings: imported.settings)
        let importedCount = try imported.coordinator.importDataArchive(from: exportURL)
        let importedTask = try #require(imported.coordinator.allTasks().first)

        #expect(importedCount == 1)
        #expect(importedTask.source == "https://example.com/file.zip?token=%3Credacted%3E&ok=1")
        #expect(importedTask.browserContext?.headers == [
            BrowserDownloadHeader(name: "Accept-Language", value: "en-US")
        ])
        #expect(importedTask.httpOptions?.additionalHeaders == [
            BrowserDownloadHeader(name: "Accept-Language", value: "en-US")
        ])
        #expect(importedTask.logEntries.first?.contains("secret") == false)
    }

    @Test("import rejects unsupported archive versions")
    func importRejectsUnsupportedArchiveVersions() throws {
        let fixture = try makeFixture()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)
        let archive = SwiftGetXDataArchive(
            archiveVersion: SwiftGetXDataSchema.currentArchiveVersion + 1,
            settings: nil,
            tasks: []
        )

        #expect(throws: PersistenceArchiveError.unsupportedArchiveVersion(archive.archiveVersion)) {
            try fixture.coordinator.importDataArchive(archive)
        }
    }

    @Test("appends and exports logs with redacted tokens")
    func appendsAndExportsLogsWithRedactedTokens() throws {
        let fixture = try makeFixture()
        let task = DownloadTask(
            name: "logs",
            source: "https://example.com/file.zip",
            kind: .http,
            savePath: "/tmp/logs.zip"
        )
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        task.appendLog("Failed https://example.com/file.zip?token=secret Authorization: BearerSecret")
        let exportDirectory = try makeTemporaryDirectory()
        let logURL = try #require(fixture.coordinator.exportLogs(task, to: exportDirectory))
        let exportedText = try String(contentsOf: logURL, encoding: .utf8)

        #expect(!task.logEntries.joined().contains("secret"))
        #expect(!exportedText.contains("secret"))
        #expect(!exportedText.contains("BearerSecret"))
        #expect(exportedText.contains("<redacted>"))
    }

    @Test("menu bar snapshot summarizes large task sets")
    func menuBarSnapshotSummarizesLargeTaskSets() throws {
        let fixture = try makeFixture()
        for index in 0..<650 {
            fixture.context.insert(DownloadTask(
                name: "Complete \(index)",
                source: "https://example.com/complete-\(index).zip",
                kind: .http,
                status: .completed,
                savePath: "/tmp/complete-\(index).zip",
                totalBytes: 100,
                downloadedBytes: 100,
                createdAt: Date(timeIntervalSince1970: Double(index))
            ))
        }
        fixture.context.insert(DownloadTask(
            name: "Running",
            source: "https://example.com/running.zip",
            kind: .http,
            status: .running,
            savePath: "/tmp/running.zip",
            totalBytes: 200,
            downloadedBytes: 50,
            speedBytesPerSecond: 12_000,
            createdAt: Date(timeIntervalSince1970: 2_000)
        ))
        fixture.context.insert(DownloadTask(
            name: "Queued",
            source: "https://example.com/queued.zip",
            kind: .http,
            status: .queued,
            savePath: "/tmp/queued.zip",
            createdAt: Date(timeIntervalSince1970: 1_900)
        ))
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        let snapshot = fixture.coordinator.menuBarSnapshot(recentLimit: 3)

        #expect(snapshot.totalCount == 652)
        #expect(snapshot.completedCount == 650)
        #expect(snapshot.runningCount == 1)
        #expect(snapshot.queuedCount == 1)
        #expect(snapshot.totalDownloadSpeed == 12_000)
        #expect(snapshot.aggregateProgress == 0.25)
        #expect(snapshot.recentTasks.map(\.name).prefix(2) == ["Running", "Queued"])
        #expect(snapshot.recentTasks.count == 3)
    }

    @Test("active system policy summarizes large task sets")
    func activeSystemPolicySummarizesLargeTaskSets() throws {
        let fixture = try makeFixture()
        for index in 0..<650 {
            fixture.context.insert(DownloadTask(
                name: "Complete \(index)",
                source: "https://example.com/complete-\(index).zip",
                kind: .http,
                status: .completed,
                savePath: "/tmp/complete-\(index).zip",
                totalBytes: 100,
                downloadedBytes: 100,
                createdAt: Date(timeIntervalSince1970: Double(index))
            ))
        }
        fixture.context.insert(DownloadTask(
            name: "Seeding",
            source: "magnet:?xt=urn:btih:0123456789012345678901234567890123456789",
            kind: .torrentMagnet,
            status: .seeding,
            savePath: "/tmp/seeding",
            createdAt: Date(timeIntervalSince1970: 2_000)
        ))
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        #expect(fixture.coordinator.hasActiveDownloadsForSystemPolicy)
    }

    private func makeFixture() throws -> PersistenceFixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try SwiftGetXPersistence.makeModelContainer(configurations: configuration)
        return PersistenceFixture(
            container: container,
            context: container.mainContext,
            settings: AppSettings(),
            coordinator: DownloadCoordinator(runsEngines: false)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct PersistenceFixture {
    let container: ModelContainer
    let context: ModelContext
    let settings: AppSettings
    let coordinator: DownloadCoordinator
}
