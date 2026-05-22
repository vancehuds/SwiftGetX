import Foundation
import SwiftGetXCore

struct SupportDiagnosticsBundle: Codable, Equatable {
    var generatedAt: Date
    var appVersion: String
    var nativeHostVersion: String
    var browserProtocolVersion: Int
    var minimumExtensionVersion: String
    var minimumNativeHostVersion: String
    var diagnosticLogLevel: DiagnosticLogLevel
    var settings: SupportSettingsSnapshot
    var nativeHost: SupportNativeHostSnapshot
    var tasks: [SupportTaskSnapshot]
    var recentErrors: [String]
    var crashLogGuidance: String
}

struct SupportSettingsSnapshot: Codable, Equatable {
    var concurrentTaskLimit: Int
    var defaultDownloadDirectoryPath: String
    var globalDownloadLimitBytes: Int64
    var globalUploadLimitBytes: Int64
    var retryLimit: Int
    var httpMultithreadingEnabled: Bool
    var httpSegmentCount: Int
    var torrentEngine: TorrentEngineKind
    var language: AppLanguage
}

struct SupportNativeHostSnapshot: Codable, Equatable {
    var status: String
    var statusMessage: String
    var detailMessage: String
    var supportedBrowserCount: Int
    var detectedBrowserCount: Int
    var configuredBrowserCount: Int
    var discoveredExtensionCount: Int
    var pairedExtensionCount: Int
    var browsers: [SupportBrowserDiagnosticSnapshot]
}

struct SupportBrowserDiagnosticSnapshot: Codable, Equatable {
    var browserName: String
    var status: String
    var statusMessage: String
    var detailMessage: String
    var hasBrowserProfile: Bool
    var isConfigured: Bool
    var discoveredExtensionIDs: [String]
    var pairedExtensionIDs: [String]
    var manifestPath: String
    var nativeHostPath: String?
    var allowedOriginCount: Int?
}

struct SupportTaskSnapshot: Codable, Equatable {
    var id: UUID
    var name: String
    var kind: DownloadKind
    var status: DownloadStatus
    var source: String
    var savePath: String
    var totalBytes: Int64
    var downloadedBytes: Int64
    var errorMessage: String?
    var connectionSummary: String?
    var recentLogs: [String]
}

@MainActor
enum SupportDiagnosticsBuilder {
    static func makeBundle(
        settings: AppSettings?,
        tasks: [DownloadTask],
        nativeHostDiagnostics: NativeHostDiagnostics?,
        generatedAt: Date = .now
    ) -> SupportDiagnosticsBundle {
        let settingsSnapshot = SupportSettingsSnapshot(settings: settings)
        let nativeSnapshot = SupportNativeHostSnapshot(diagnostics: nativeHostDiagnostics)
        let logLevel = settings?.diagnosticLogLevel ?? .normal
        let taskSnapshots = tasks
            .filter { !$0.isArchived }
            .prefix(50)
            .map { SupportTaskSnapshot(task: $0, logLevel: logLevel) }
        let recentErrors = tasks
            .flatMap { task -> [String] in
                var values = [String]()
                if let error = task.errorMessage?.nonEmptyTrimmed {
                    values.append(error)
                }
                values.append(contentsOf: task.logEntries.filter { $0.localizedCaseInsensitiveContains("error") || $0.localizedCaseInsensitiveContains("failed") })
                return values
            }
            .suffix(20)
            .map(PrivacyRedactor.redactedText)

        return SupportDiagnosticsBundle(
            generatedAt: generatedAt,
            appVersion: appVersion(),
            nativeHostVersion: BrowserIntegrationCompatibility.nativeHostVersion,
            browserProtocolVersion: BrowserIntegrationCompatibility.protocolVersion,
            minimumExtensionVersion: BrowserIntegrationCompatibility.minimumChromeExtensionVersion,
            minimumNativeHostVersion: BrowserIntegrationCompatibility.minimumNativeHostVersion,
            diagnosticLogLevel: logLevel,
            settings: settingsSnapshot,
            nativeHost: nativeSnapshot,
            tasks: Array(taskSnapshots),
            recentErrors: Array(recentErrors),
            crashLogGuidance: crashLogGuidance
        )
    }

    static func text(
        for bundle: SupportDiagnosticsBundle,
        dateFormatter: ISO8601DateFormatter = ISO8601DateFormatter()
    ) -> String {
        var lines = [
            "SwiftGetX Diagnostics",
            "Generated: \(dateFormatter.string(from: bundle.generatedAt))",
            "App Version: \(bundle.appVersion)",
            "Native Host Version: \(bundle.nativeHostVersion)",
            "Browser Protocol: \(bundle.browserProtocolVersion)",
            "Minimum Extension Version: \(bundle.minimumExtensionVersion)",
            "Minimum Native Host Version: \(bundle.minimumNativeHostVersion)",
            "Diagnostic Log Level: \(bundle.diagnosticLogLevel.rawValue)",
            "",
            "Settings",
            "- Concurrent Tasks: \(bundle.settings.concurrentTaskLimit)",
            "- Default Directory: \(PrivacyRedactor.redactedText(bundle.settings.defaultDownloadDirectoryPath))",
            "- Download Limit: \(bundle.settings.globalDownloadLimitBytes)",
            "- Upload Limit: \(bundle.settings.globalUploadLimitBytes)",
            "- HTTP Segments: \(bundle.settings.httpSegmentCount)",
            "- Retry Limit: \(bundle.settings.retryLimit)",
            "- Torrent Engine: \(bundle.settings.torrentEngine.rawValue)",
            "- Language: \(bundle.settings.language.rawValue)",
            "",
            "Native Host",
            "- Status: \(bundle.nativeHost.status)",
            "- Message: \(bundle.nativeHost.statusMessage)",
            "- Detail: \(bundle.nativeHost.detailMessage)",
            "- Browsers: \(bundle.nativeHost.configuredBrowserCount)/\(bundle.nativeHost.supportedBrowserCount) configured, \(bundle.nativeHost.detectedBrowserCount) detected",
            "- Extensions: \(bundle.nativeHost.discoveredExtensionCount) discovered, \(bundle.nativeHost.pairedExtensionCount) paired"
        ]

        for browser in bundle.nativeHost.browsers {
            lines.append("- \(browser.browserName): \(browser.statusMessage)")
            lines.append("  manifest=\(browser.manifestPath)")
            if let nativeHostPath = browser.nativeHostPath {
                lines.append("  nativeHost=\(nativeHostPath)")
            }
            if !browser.discoveredExtensionIDs.isEmpty {
                lines.append("  discoveredExtensions=\(browser.discoveredExtensionIDs.joined(separator: ","))")
            }
            if !browser.pairedExtensionIDs.isEmpty {
                lines.append("  pairedExtensions=\(browser.pairedExtensionIDs.joined(separator: ","))")
            }
        }

        lines.append(contentsOf: ["", "Tasks"])
        if bundle.tasks.isEmpty {
            lines.append("- none")
        } else {
            for task in bundle.tasks {
                lines.append("- \(task.name) [\(task.kind.rawValue)/\(task.status.rawValue)] \(task.downloadedBytes)/\(task.totalBytes)")
                lines.append("  source=\(task.source)")
                lines.append("  savePath=\(task.savePath)")
                if let error = task.errorMessage {
                    lines.append("  error=\(error)")
                }
                if let connection = task.connectionSummary {
                    lines.append("  connection=\(connection)")
                }
                for entry in task.recentLogs.suffix(3) {
                    lines.append("  log=\(entry)")
                }
            }
        }

        lines.append(contentsOf: ["", "Recent Errors"])
        if bundle.recentErrors.isEmpty {
            lines.append("- none")
        } else {
            lines.append(contentsOf: bundle.recentErrors.map { "- \($0)" })
        }

        lines.append(contentsOf: ["", "Crash Logs", bundle.crashLogGuidance])
        return PrivacyRedactor.redactedText(lines.joined(separator: "\n"))
    }

    static func jsonData(for bundle: SupportDiagnosticsBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    private static func appVersion(bundle: Bundle = .main) -> String {
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return [shortVersion, build].compactMap { $0?.nonEmptyTrimmed }.joined(separator: " ")
            .nonEmptyTrimmed ?? "development"
    }

    private static var crashLogGuidance: String {
        "Open Console.app and filter for SwiftGetX, or inspect ~/Library/Logs/DiagnosticReports for SwiftGetX crash reports. Attach this diagnostics bundle with any crash log you share."
    }
}

@MainActor
private extension SupportSettingsSnapshot {
    init(settings: AppSettings?) {
        concurrentTaskLimit = settings?.concurrentTaskLimit ?? 0
        defaultDownloadDirectoryPath = PrivacyRedactor.redactedText(settings?.defaultDownloadDirectory.path ?? "")
        globalDownloadLimitBytes = settings?.globalDownloadLimitBytes ?? 0
        globalUploadLimitBytes = settings?.globalUploadLimitBytes ?? 0
        retryLimit = settings?.retryLimit ?? 0
        httpMultithreadingEnabled = settings?.httpMultithreadingEnabled ?? false
        httpSegmentCount = settings?.httpSegmentCount ?? 0
        torrentEngine = settings?.torrentEngine ?? .swift
        language = settings?.language ?? .system
    }
}

@MainActor
private extension SupportNativeHostSnapshot {
    init(diagnostics: NativeHostDiagnostics?) {
        status = diagnostics?.status.rawValue ?? "unchecked"
        statusMessage = PrivacyRedactor.redactedText(diagnostics?.statusMessage ?? L10n.string("diagnostics_unchecked"))
        detailMessage = PrivacyRedactor.redactedText(diagnostics?.detailMessage ?? "")
        supportedBrowserCount = diagnostics?.supportedBrowserCount ?? 0
        detectedBrowserCount = diagnostics?.detectedBrowserCount ?? 0
        configuredBrowserCount = diagnostics?.configuredBrowserCount ?? 0
        discoveredExtensionCount = diagnostics?.discoveredExtensionCount ?? 0
        pairedExtensionCount = diagnostics?.pairedExtensionCount ?? 0
        browsers = diagnostics?.browserDiagnostics.map(SupportBrowserDiagnosticSnapshot.init(diagnostic:)) ?? []
    }
}

private extension SupportBrowserDiagnosticSnapshot {
    init(diagnostic: ChromeNativeHostBrowserDiagnostic) {
        browserName = diagnostic.browserName
        status = diagnostic.status.rawValue
        statusMessage = PrivacyRedactor.redactedText(diagnostic.statusMessage)
        detailMessage = PrivacyRedactor.redactedText(diagnostic.detailMessage)
        hasBrowserProfile = diagnostic.hasBrowserProfile
        isConfigured = diagnostic.isConfigured
        discoveredExtensionIDs = diagnostic.discoveredExtensionIDs
        pairedExtensionIDs = diagnostic.pairedExtensionIDs
        manifestPath = PrivacyRedactor.redactedText(diagnostic.manifestURL.path)
        nativeHostPath = diagnostic.nativeHostPath.map(PrivacyRedactor.redactedText)
        allowedOriginCount = diagnostic.allowedOriginCount
    }
}

private extension SupportTaskSnapshot {
    init(task: DownloadTask, logLevel: DiagnosticLogLevel) {
        id = task.id
        name = SourceParser.sanitizeFilename(task.name)
        kind = task.kind
        status = task.status
        source = PrivacyRedactor.redactedText(task.displaySource)
        savePath = PrivacyRedactor.redactedText(task.displaySavePath)
        totalBytes = task.totalBytes
        downloadedBytes = task.downloadedBytes
        errorMessage = task.errorMessage.map(PrivacyRedactor.redactedText)
        connectionSummary = task.connectionSummary.map(PrivacyRedactor.redactedText)
        recentLogs = task.logEntries
            .filter { logLevel.includesDebugEntries || !$0.localizedCaseInsensitiveContains("[debug]") }
            .suffix(10)
            .map(PrivacyRedactor.redactedText)
    }
}

private extension NativeHostDiagnostics.DiagnosticStatus {
    var rawValue: String {
        switch self {
        case .unchecked:
            "unchecked"
        case .checking:
            "checking"
        case .ok:
            "ok"
        case .warning:
            "warning"
        case .error:
            "error"
        }
    }
}

private extension ChromeNativeHostRegistrationStatus {
    var rawValue: String {
        switch self {
        case .ok:
            "ok"
        case .warning:
            "warning"
        case .error:
            "error"
        }
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
