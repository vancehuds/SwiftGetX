import AppKit
import Foundation
import SwiftData
import Testing
import SwiftGetXCore
@testable import SwiftGetX

@Suite("SupportDiagnostics", .serialized)
@MainActor
struct SupportDiagnosticsTests {
    @Test("diagnostics bundle redacts sensitive values and honors log level")
    func diagnosticsBundleRedactsSensitiveValuesAndHonorsLogLevel() throws {
        let settings = AppSettings()
        settings.diagnosticLogLevel = .normal
        settings.defaultDownloadDirectory = URL(fileURLWithPath: "/Users/tester/Downloads")

        let task = DownloadTask(
            name: "../release.zip",
            source: "https://example.com/release.zip?token=secret",
            kind: .http,
            status: .failed,
            savePath: "/Users/tester/Downloads/release.zip",
            totalBytes: 1_000,
            downloadedBytes: 128
        )
        task.errorMessage = "Authorization: BearerSecret https://example.com/release.zip?token=secret"
        task.connectionSummary = "Cookie: session=secret"
        task.logEntries = [
            "[2026-05-22] [debug] Authorization: BearerSecret",
            "[2026-05-22] failed https://example.com/release.zip?token=secret"
        ]

        let generatedAt = Date(timeIntervalSince1970: 0)
        let normalBundle = SupportDiagnosticsBuilder.makeBundle(
            settings: settings,
            tasks: [task],
            nativeHostDiagnostics: nil,
            generatedAt: generatedAt
        )
        let normalText = SupportDiagnosticsBuilder.text(for: normalBundle)

        #expect(normalBundle.diagnosticLogLevel == .normal)
        #expect(normalBundle.tasks.first?.recentLogs.contains { $0.contains("[debug]") } == false)
        #expect(normalText.contains("SwiftGetX Diagnostics"))
        #expect(normalText.contains("Crash Logs"))
        #expect(normalText.contains(BrowserIntegrationCompatibility.minimumChromeExtensionVersion))
        #expect(!normalText.contains("BearerSecret"))
        #expect(!normalText.contains("token=secret"))
        #expect(!normalText.contains("session=secret"))

        settings.diagnosticLogLevel = .verbose
        let verboseBundle = SupportDiagnosticsBuilder.makeBundle(
            settings: settings,
            tasks: [task],
            nativeHostDiagnostics: nil,
            generatedAt: generatedAt
        )
        let encoded = try SupportDiagnosticsBuilder.jsonData(for: verboseBundle)
        let decoded = try JSONDecoder.supportDiagnostics.decode(SupportDiagnosticsBundle.self, from: encoded)

        #expect(verboseBundle.diagnosticLogLevel == .verbose)
        #expect(verboseBundle.tasks.first?.recentLogs.contains { $0.contains("[debug]") } == true)
        #expect(verboseBundle.tasks.first?.recentLogs.joined().contains("BearerSecret") == false)
        #expect(decoded == verboseBundle)
    }

    @Test("coordinator copies and exports redacted diagnostics")
    func coordinatorCopiesAndExportsRedactedDiagnostics() throws {
        let fixture = try makeFixture()
        let settingsRecord = fixture.settings.makeRecord()
        fixture.context.insert(settingsRecord)
        let task = DownloadTask(
            name: "support.zip",
            source: "https://example.com/support.zip?token=secret",
            kind: .http,
            status: .failed,
            savePath: "/tmp/support.zip"
        )
        task.logEntries = ["failed Cookie: session=secret"]
        fixture.context.insert(task)
        try fixture.context.save()
        fixture.coordinator.attach(modelContext: fixture.context, settings: fixture.settings)

        fixture.coordinator.appendDebugLog("Authorization: BearerSecret", to: task)
        #expect(task.logEntries.count == 1)

        fixture.settings.diagnosticLogLevel = .verbose
        fixture.coordinator.appendDebugLog("Authorization: BearerSecret", to: task)
        #expect(task.logEntries.contains { $0.contains("[debug]") })
        #expect(task.logEntries.joined().contains("BearerSecret") == false)

        fixture.coordinator.copyDiagnostics()
        let pasted = try #require(NSPasteboard.general.string(forType: .string))
        #expect(pasted.contains("SwiftGetX Diagnostics"))
        #expect(!pasted.contains("secret"))
        #expect(fixture.coordinator.statusMessage == L10n.string("support_diagnostics_copied"))

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let exportedURL = try #require(fixture.coordinator.exportDiagnostics(to: directory))
        let exportedData = try Data(contentsOf: exportedURL)
        let exported = try JSONDecoder.supportDiagnostics.decode(SupportDiagnosticsBundle.self, from: exportedData)
        let exportedText = try String(contentsOf: exportedURL, encoding: .utf8)

        #expect(exported.tasks.count == 1)
        #expect(exported.diagnosticLogLevel == .verbose)
        #expect(!exportedText.contains("BearerSecret"))
        #expect(!exportedText.contains("token=secret"))
        #expect(!exportedText.contains("session=secret"))
        #expect(fixture.coordinator.statusMessage.contains(exportedURL.path))
    }

    @Test("diagnostic log level persists through settings records and archives")
    func diagnosticLogLevelPersistsThroughSettingsRecordsAndArchives() {
        let settings = AppSettings()
        settings.diagnosticLogLevel = .verbose

        let record = settings.makeRecord()
        let restored = AppSettings()
        restored.apply(record)
        let archive = AppSettingsArchive(record: record)
        let archivedRecord = archive.makeRecord()

        #expect(record.diagnosticLogLevelRawValue == DiagnosticLogLevel.verbose.rawValue)
        #expect(restored.diagnosticLogLevel == .verbose)
        #expect(archive.diagnosticLogLevel == .verbose)
        #expect(archivedRecord.diagnosticLogLevelRawValue == DiagnosticLogLevel.verbose.rawValue)
    }

    @Test("native host diagnostics are included in support snapshots")
    func nativeHostDiagnosticsAreIncludedInSupportSnapshots() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let profile = root.appendingPathComponent("Chrome")
        let manifestDirectory = root.appendingPathComponent("Chrome/NativeMessagingHosts")
        let nativeHost = root.appendingPathComponent("SwiftGetXNativeHost")
        let extensionID = "bcdefghijklmnopabcdefghijklmnopa"

        try writePreferences(
            to: profile.appendingPathComponent("Default/Secure Preferences"),
            extensions: [
                extensionID: [
                    "name": "SwiftGetX",
                    "permissions": ["nativeMessaging"]
                ]
            ]
        )
        try Data("#!/bin/sh\n".utf8).write(to: nativeHost)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: nativeHost.path
        )

        let registrar = ChromeNativeHostRegistrar(
            manifestDirectory: ChromeNativeHostRegistrar.defaultManifestDirectory(),
            extensionDiscovery: ChromeExtensionDiscovery(
                browserConfigurations: [
                    ChromiumBrowserConfiguration(
                        name: "Chrome",
                        userDataDirectory: profile,
                        nativeMessagingHostDirectory: manifestDirectory
                    )
                ],
                developmentExtensionDirectory: nil
            ),
            pairingStore: ChromeNativeHostPairingStore(pairedExtensionIDs: [extensionID]),
            nativeHostSearchPaths: [nativeHost]
        )
        #expect(registrar.register().status == .ok)

        let diagnostics = NativeHostDiagnostics(registrar: registrar)
        diagnostics.check()

        let bundle = SupportDiagnosticsBuilder.makeBundle(
            settings: nil,
            tasks: [],
            nativeHostDiagnostics: diagnostics
        )
        let browser = try #require(bundle.nativeHost.browsers.first)

        #expect(bundle.nativeHost.status == "ok")
        #expect(bundle.nativeHost.configuredBrowserCount == 1)
        #expect(bundle.nativeHost.discoveredExtensionCount == 1)
        #expect(browser.browserName == "Chrome")
        #expect(browser.isConfigured)
        #expect(browser.allowedOriginCount == 1)
        #expect(browser.nativeHostPath?.contains("SwiftGetXNativeHost") == true)
    }

    @Test("Task 30 support fixtures are bundled and schema-valid")
    func task30SupportFixturesAreBundledAndSchemaValid() throws {
        let browserScenarios = try loadFixture(
            [BrowserE2EScenario].self,
            subdirectory: "Fixtures/BrowserE2E",
            name: "native-host-scenarios",
            extension: "json"
        )
        let swarm = try loadFixture(
            MockSwarmFixture.self,
            subdirectory: "Fixtures/Torrent",
            name: "mock-swarm-fixtures",
            extension: "json"
        )

        #expect(browserScenarios.count >= 4)
        #expect(browserScenarios.contains { $0.expectedNativeHostState == "accepted" })
        #expect(browserScenarios.contains { $0.expectedNativeHostState == "incompatible" })
        #expect(browserScenarios.allSatisfy { URL(string: $0.url)?.scheme?.hasPrefix("http") == true })

        #expect(swarm.trackers.contains { $0.url.hasPrefix("https://") })
        #expect(swarm.trackers.contains { $0.url.hasPrefix("udp://") })
        #expect(Set(swarm.peers.map(\.source)).isSuperset(of: ["tracker", "pex", "dht"]))
        #expect(swarm.dhtNodes.count >= 2)
    }

    @Test("extension popup exposes recent native message error details")
    func extensionPopupExposesRecentNativeMessageErrorDetails() throws {
        let extensionDirectory = try #require(AppResources.url(forResource: "ChromeExtension"))
        let background = try String(
            contentsOf: extensionDirectory.appendingPathComponent("background.js"),
            encoding: .utf8
        )
        let popup = try String(
            contentsOf: extensionDirectory.appendingPathComponent("popup.js"),
            encoding: .utf8
        )
        let popupCSS = try String(
            contentsOf: extensionDirectory.appendingPathComponent("popup.css"),
            encoding: .utf8
        )

        #expect(background.contains("nativeMessageErrorDetail"))
        #expect(background.contains("hostName: NATIVE_HOST_NAME"))
        #expect(background.contains("runtimeError: result.runtimeError"))
        #expect(background.contains("rejectedReason: response.rejectedReason"))
        #expect(background.contains("requestID: response.requestID"))
        #expect(background.contains("markFailure(result.message, result.errorDetail)"))
        #expect(popup.contains("formatErrorDetail"))
        #expect(popup.contains("response.error.detail"))
        #expect(popup.contains("response?.errorDetail"))
        #expect(popupCSS.contains("white-space: pre-wrap"))
    }

    private func makeFixture() throws -> SupportDiagnosticsFixture {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try SwiftGetXPersistence.makeModelContainer(configurations: configuration)
        return SupportDiagnosticsFixture(
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

    private func writePreferences(
        to url: URL,
        extensions: [String: [String: Any]]
    ) throws {
        let root: [String: Any] = [
            "extensions": [
                "settings": extensions.mapValues { ["manifest": $0] }
            ]
        ]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func loadFixture<T: Decodable>(
        _ type: T.Type,
        subdirectory: String,
        name: String,
        extension fileExtension: String
    ) throws -> T {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ))
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }
}

private struct SupportDiagnosticsFixture {
    let container: ModelContainer
    let context: ModelContext
    let settings: AppSettings
    let coordinator: DownloadCoordinator
}

private struct BrowserE2EScenario: Codable {
    var name: String
    var source: String
    var url: String
    var expectedNativeHostState: String
    var expectedMessage: String
}

private struct MockSwarmFixture: Codable {
    var trackers: [MockTrackerFixture]
    var peers: [MockPeerFixture]
    var dhtNodes: [MockDHTNodeFixture]
}

private struct MockTrackerFixture: Codable {
    var url: String
    var tier: Int
    var peers: Int
    var seeds: Int
}

private struct MockPeerFixture: Codable {
    var ip: String
    var port: Int
    var source: String
    var pieces: [Int]
}

private struct MockDHTNodeFixture: Codable {
    var host: String
    var port: Int
}

private extension JSONDecoder {
    static var supportDiagnostics: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
