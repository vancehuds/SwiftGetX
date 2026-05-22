import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppSettings {
    nonisolated static let languageUserDefaultsKey = "app_language"
    @ObservationIgnored private let userDefaults: UserDefaults

    var defaultDownloadDirectory: URL = FileManager.default.urls(
        for: .downloadsDirectory,
        in: .userDomainMask
    ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")

    var concurrentTaskLimit: Int = 3
    var httpMultithreadingEnabled = true
    var httpSegmentCount: Int = 8
    var hideHTTPTemporaryFiles = true
    var retryLimit: Int = 3
    var globalDownloadLimitBytes: Int64 = 0
    var globalUploadLimitBytes: Int64 = 0
    var completionNotificationsEnabled = true
    var completionSoundEnabled = false
    var completionRevealInFinderEnabled = false
    var completionOpenFileEnabled = false
    var completionScriptPath = ""
    var clipboardDetectionEnabled = true
    var confirmBrowserTakeoverDownloads = true
    var browserTakeoverAllowedHosts: [String] = []
    var browserTakeoverBlockedHosts: [String] = []
    var downloadRules: [DownloadRule] = []
    var launchAtLoginEnabled = false
    var keepRunningInMenuBar = true
    var preventSleepDuringDownloads = true
    var promptBeforeQuittingWithActiveTasks = true
    var downloadRestartPolicy: DownloadRestartPolicy = .restorePaused
    var automaticallyRequeuesFailedTasks = false
    var queueFailureRetryLimit: Int = 3
    var stopSeedingAtRatio: Double = 1.0
    var stopSeedingAfterSeconds: TimeInterval = 3600
    var torrentDHTEnabled = true
    var torrentPEXEnabled = true
    var torrentLSDEnabled = true
    var torrentSequentialDownloadEnabled = false
    var torrentMagnetMetadataTimeoutSeconds = 12
    var torrentMaxConnections = 200
    var torrentMaxUploadSlots = 8
    var torrentSeedingLimitMode: TorrentSeedingLimitMode = .stopAtRatio
    var torrentEngine: TorrentEngineKind = .swift
    var torrentDHTBootstrapNodes: [String] = TorrentRuntimeOptions.defaultDHTBootstrapNodes
    var diagnosticLogLevel: DiagnosticLogLevel = .normal
    var language: AppLanguage = .system {
        didSet {
            userDefaults.set(language.rawValue, forKey: Self.languageUserDefaultsKey)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        language = AppLanguage.storedPreference(in: userDefaults)
    }

    func apply(_ record: AppSettingsRecord) {
        defaultDownloadDirectory = URL(fileURLWithPath: record.defaultDownloadDirectoryPath)
        concurrentTaskLimit = record.concurrentTaskLimit
        httpMultithreadingEnabled = record.httpMultithreadingEnabled
        httpSegmentCount = record.httpSegmentCount
        hideHTTPTemporaryFiles = record.hideHTTPTemporaryFiles
        retryLimit = record.retryLimit
        globalDownloadLimitBytes = record.globalDownloadLimitBytes
        globalUploadLimitBytes = record.globalUploadLimitBytes
        completionNotificationsEnabled = record.completionNotificationsEnabled
        completionSoundEnabled = record.completionSoundEnabled
        completionRevealInFinderEnabled = record.completionRevealInFinderEnabled
        completionOpenFileEnabled = record.completionOpenFileEnabled
        completionScriptPath = record.completionScriptPath
        clipboardDetectionEnabled = record.clipboardDetectionEnabled
        confirmBrowserTakeoverDownloads = record.confirmBrowserTakeoverDownloads
        browserTakeoverAllowedHosts = HostPattern.normalized(record.browserTakeoverAllowedHosts)
        browserTakeoverBlockedHosts = HostPattern.normalized(record.browserTakeoverBlockedHosts)
        downloadRules = Self.decodeDownloadRules(from: record.downloadRulesJSON)
        launchAtLoginEnabled = record.launchAtLoginEnabled
        keepRunningInMenuBar = record.keepRunningInMenuBar
        preventSleepDuringDownloads = record.preventSleepDuringDownloads
        promptBeforeQuittingWithActiveTasks = record.promptBeforeQuittingWithActiveTasks
        downloadRestartPolicy = DownloadRestartPolicy(rawValue: record.downloadRestartPolicyRawValue) ?? .restorePaused
        automaticallyRequeuesFailedTasks = record.automaticallyRequeuesFailedTasks
        queueFailureRetryLimit = record.queueFailureRetryLimit
        stopSeedingAtRatio = record.stopSeedingAtRatio
        stopSeedingAfterSeconds = record.stopSeedingAfterSeconds
        torrentDHTEnabled = record.torrentDHTEnabled
        torrentPEXEnabled = record.torrentPEXEnabled
        torrentLSDEnabled = record.torrentLSDEnabled
        torrentSequentialDownloadEnabled = record.torrentSequentialDownloadEnabled
        torrentMagnetMetadataTimeoutSeconds = record.torrentMagnetMetadataTimeoutSeconds
        torrentMaxConnections = record.torrentMaxConnections
        torrentMaxUploadSlots = record.torrentMaxUploadSlots
        torrentSeedingLimitMode = TorrentSeedingLimitMode(rawValue: record.torrentSeedingLimitModeRawValue) ?? .stopAtRatio
        torrentEngine = TorrentEngineKind(rawValue: record.torrentEngineRawValue) ?? .swift
        torrentDHTBootstrapNodes = Self.normalizedTorrentDHTBootstrapNodes(record.torrentDHTBootstrapNodes)
        diagnosticLogLevel = DiagnosticLogLevel(rawValue: record.diagnosticLogLevelRawValue) ?? .normal
        language = AppLanguage.storedPreference(from: record.languageRawValue, in: userDefaults)
    }

    func makeRecord() -> AppSettingsRecord {
        AppSettingsRecord(
            defaultDownloadDirectoryPath: defaultDownloadDirectory.path,
            concurrentTaskLimit: concurrentTaskLimit,
            httpMultithreadingEnabled: httpMultithreadingEnabled,
            httpSegmentCount: httpSegmentCount,
            hideHTTPTemporaryFiles: hideHTTPTemporaryFiles,
            retryLimit: retryLimit,
            globalDownloadLimitBytes: globalDownloadLimitBytes,
            globalUploadLimitBytes: globalUploadLimitBytes,
            completionNotificationsEnabled: completionNotificationsEnabled,
            completionSoundEnabled: completionSoundEnabled,
            completionRevealInFinderEnabled: completionRevealInFinderEnabled,
            completionOpenFileEnabled: completionOpenFileEnabled,
            completionScriptPath: completionScriptPath,
            clipboardDetectionEnabled: clipboardDetectionEnabled,
            confirmBrowserTakeoverDownloads: confirmBrowserTakeoverDownloads,
            browserTakeoverAllowedHosts: HostPattern.normalized(browserTakeoverAllowedHosts),
            browserTakeoverBlockedHosts: HostPattern.normalized(browserTakeoverBlockedHosts),
            downloadRulesJSON: Self.encodeDownloadRules(downloadRules),
            launchAtLoginEnabled: launchAtLoginEnabled,
            keepRunningInMenuBar: keepRunningInMenuBar,
            preventSleepDuringDownloads: preventSleepDuringDownloads,
            promptBeforeQuittingWithActiveTasks: promptBeforeQuittingWithActiveTasks,
            downloadRestartPolicyRawValue: downloadRestartPolicy.rawValue,
            automaticallyRequeuesFailedTasks: automaticallyRequeuesFailedTasks,
            queueFailureRetryLimit: queueFailureRetryLimit,
            stopSeedingAtRatio: stopSeedingAtRatio,
            stopSeedingAfterSeconds: stopSeedingAfterSeconds,
            torrentDHTEnabled: torrentDHTEnabled,
            torrentPEXEnabled: torrentPEXEnabled,
            torrentLSDEnabled: torrentLSDEnabled,
            torrentSequentialDownloadEnabled: torrentSequentialDownloadEnabled,
            torrentMagnetMetadataTimeoutSeconds: torrentMagnetMetadataTimeoutSeconds,
            torrentMaxConnections: torrentMaxConnections,
            torrentMaxUploadSlots: torrentMaxUploadSlots,
            torrentSeedingLimitModeRawValue: torrentSeedingLimitMode.rawValue,
            torrentEngineRawValue: torrentEngine.rawValue,
            torrentDHTBootstrapNodes: Self.normalizedTorrentDHTBootstrapNodes(torrentDHTBootstrapNodes),
            diagnosticLogLevelRawValue: diagnosticLogLevel.rawValue,
            languageRawValue: language.rawValue
        )
    }

    func update(_ record: AppSettingsRecord) {
        record.schemaVersion = SwiftGetXDataSchema.currentModelVersion
        record.defaultDownloadDirectoryPath = defaultDownloadDirectory.path
        record.concurrentTaskLimit = concurrentTaskLimit
        record.httpMultithreadingEnabled = httpMultithreadingEnabled
        record.httpSegmentCount = httpSegmentCount
        record.hideHTTPTemporaryFiles = hideHTTPTemporaryFiles
        record.retryLimit = retryLimit
        record.globalDownloadLimitBytes = globalDownloadLimitBytes
        record.globalUploadLimitBytes = globalUploadLimitBytes
        record.completionNotificationsEnabled = completionNotificationsEnabled
        record.completionSoundEnabled = completionSoundEnabled
        record.completionRevealInFinderEnabled = completionRevealInFinderEnabled
        record.completionOpenFileEnabled = completionOpenFileEnabled
        record.completionScriptPath = completionScriptPath
        record.clipboardDetectionEnabled = clipboardDetectionEnabled
        record.confirmBrowserTakeoverDownloads = confirmBrowserTakeoverDownloads
        record.browserTakeoverAllowedHosts = HostPattern.normalized(browserTakeoverAllowedHosts)
        record.browserTakeoverBlockedHosts = HostPattern.normalized(browserTakeoverBlockedHosts)
        record.downloadRulesJSON = Self.encodeDownloadRules(downloadRules)
        record.launchAtLoginEnabled = launchAtLoginEnabled
        record.keepRunningInMenuBar = keepRunningInMenuBar
        record.preventSleepDuringDownloads = preventSleepDuringDownloads
        record.promptBeforeQuittingWithActiveTasks = promptBeforeQuittingWithActiveTasks
        record.downloadRestartPolicyRawValue = downloadRestartPolicy.rawValue
        record.automaticallyRequeuesFailedTasks = automaticallyRequeuesFailedTasks
        record.queueFailureRetryLimit = queueFailureRetryLimit
        record.stopSeedingAtRatio = stopSeedingAtRatio
        record.stopSeedingAfterSeconds = stopSeedingAfterSeconds
        record.torrentDHTEnabled = torrentDHTEnabled
        record.torrentPEXEnabled = torrentPEXEnabled
        record.torrentLSDEnabled = torrentLSDEnabled
        record.torrentSequentialDownloadEnabled = torrentSequentialDownloadEnabled
        record.torrentMagnetMetadataTimeoutSeconds = torrentMagnetMetadataTimeoutSeconds
        record.torrentMaxConnections = torrentMaxConnections
        record.torrentMaxUploadSlots = torrentMaxUploadSlots
        record.torrentSeedingLimitModeRawValue = torrentSeedingLimitMode.rawValue
        record.torrentEngineRawValue = torrentEngine.rawValue
        record.torrentDHTBootstrapNodes = Self.normalizedTorrentDHTBootstrapNodes(torrentDHTBootstrapNodes)
        record.diagnosticLogLevelRawValue = diagnosticLogLevel.rawValue
        record.languageRawValue = language.rawValue
    }

    var torrentRuntimeOptions: TorrentRuntimeOptions {
        TorrentRuntimeOptions(
            engine: torrentEngine,
            isDHTEnabled: torrentDHTEnabled,
            isPEXEnabled: torrentPEXEnabled,
            isLSDEnabled: torrentLSDEnabled,
            isSequentialDownloadEnabled: torrentSequentialDownloadEnabled,
            magnetMetadataTimeoutSeconds: torrentMagnetMetadataTimeoutSeconds,
            maxConnections: torrentMaxConnections,
            maxUploadSlots: torrentMaxUploadSlots,
            seedingLimitMode: torrentSeedingLimitMode,
            stopSeedingAtRatio: stopSeedingAtRatio,
            stopSeedingAfterSeconds: stopSeedingAfterSeconds,
            dhtBootstrapNodes: torrentDHTBootstrapNodes
        )
    }

    var downloadRulesText: String {
        get { DownloadRuleTextFormat.format(downloadRules) }
        set { downloadRules = DownloadRuleTextFormat.parse(newValue) }
    }

    var browserTakeoverAllowedHostsText: String {
        get { browserTakeoverAllowedHosts.joined(separator: "\n") }
        set { browserTakeoverAllowedHosts = HostPattern.normalized(newValue.components(separatedBy: .newlines)) }
    }

    var browserTakeoverBlockedHostsText: String {
        get { browserTakeoverBlockedHosts.joined(separator: "\n") }
        set { browserTakeoverBlockedHosts = HostPattern.normalized(newValue.components(separatedBy: .newlines)) }
    }

    private static func decodeDownloadRules(from json: String?) -> [DownloadRule] {
        guard let json,
              let data = json.data(using: .utf8),
              let rules = try? JSONDecoder().decode([DownloadRule].self, from: data)
        else {
            return []
        }
        return Array(rules.prefix(DownloadRule.maximumRuleCount))
    }

    private static func encodeDownloadRules(_ rules: [DownloadRule]) -> String {
        let rules = Array(rules.prefix(DownloadRule.maximumRuleCount))
        guard let data = try? JSONEncoder().encode(rules),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }

    private static func normalizedTorrentDHTBootstrapNodes(_ nodes: [String]) -> [String] {
        TorrentRuntimeOptions(dhtBootstrapNodes: nodes).dhtBootstrapNodes
    }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case en
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    static var storedPreference: AppLanguage {
        storedPreference(in: .standard)
    }

    static func storedPreference(in userDefaults: UserDefaults) -> AppLanguage {
        guard let rawValue = userDefaults.string(forKey: AppSettings.languageUserDefaultsKey) else {
            return .system
        }
        return AppLanguage(rawValue: rawValue) ?? .system
    }

    static func storedPreference(from recordRawValue: String, in userDefaults: UserDefaults = .standard) -> AppLanguage {
        let recordLanguage = AppLanguage(rawValue: recordRawValue) ?? .system
        guard let rawValue = userDefaults.string(forKey: AppSettings.languageUserDefaultsKey),
              let userDefaultsLanguage = AppLanguage(rawValue: rawValue),
              userDefaultsLanguage != recordLanguage
        else {
            return recordLanguage
        }
        return userDefaultsLanguage
    }

    var title: String {
        switch self {
        case .system:
            return L10n.string("language_system")
        case .en:
            return "English"
        case .zhHans:
            return "简体中文"
        }
    }
}

enum DownloadRestartPolicy: String, Codable, CaseIterable, Identifiable {
    case restorePaused
    case autoResume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .restorePaused:
            L10n.string("restart_policy_restore_paused")
        case .autoResume:
            L10n.string("restart_policy_auto_resume")
        }
    }
}

@Model
final class AppSettingsRecord {
    @Attribute(.unique) var id: String
    var schemaVersion: Int = SwiftGetXDataSchema.currentModelVersion
    var defaultDownloadDirectoryPath: String
    var concurrentTaskLimit: Int
    var httpMultithreadingEnabled: Bool = true
    var httpSegmentCount: Int
    var hideHTTPTemporaryFiles: Bool = true
    var retryLimit: Int
    var globalDownloadLimitBytes: Int64
    var globalUploadLimitBytes: Int64
    var completionNotificationsEnabled: Bool
    var completionSoundEnabled: Bool = false
    var completionRevealInFinderEnabled: Bool = false
    var completionOpenFileEnabled: Bool = false
    var completionScriptPath: String = ""
    var clipboardDetectionEnabled: Bool
    var confirmBrowserTakeoverDownloads: Bool = true
    var browserTakeoverAllowedHosts: [String] = []
    var browserTakeoverBlockedHosts: [String] = []
    var downloadRulesJSON: String = "[]"
    var launchAtLoginEnabled: Bool = false
    var keepRunningInMenuBar: Bool = true
    var preventSleepDuringDownloads: Bool = true
    var promptBeforeQuittingWithActiveTasks: Bool = true
    var downloadRestartPolicyRawValue: String = DownloadRestartPolicy.restorePaused.rawValue
    var automaticallyRequeuesFailedTasks: Bool = false
    var queueFailureRetryLimit: Int = 3
    var stopSeedingAtRatio: Double
    var stopSeedingAfterSeconds: TimeInterval = 3600
    var torrentDHTEnabled: Bool = true
    var torrentPEXEnabled: Bool = true
    var torrentLSDEnabled: Bool = true
    var torrentSequentialDownloadEnabled: Bool = false
    var torrentMagnetMetadataTimeoutSeconds: Int = 12
    var torrentMaxConnections: Int = 200
    var torrentMaxUploadSlots: Int = 8
    var torrentSeedingLimitModeRawValue: String = TorrentSeedingLimitMode.stopAtRatio.rawValue
    var torrentEngineRawValue: String = TorrentEngineKind.swift.rawValue
    var torrentDHTBootstrapNodes: [String] = TorrentRuntimeOptions.defaultDHTBootstrapNodes
    var diagnosticLogLevelRawValue: String = DiagnosticLogLevel.normal.rawValue
    var languageRawValue: String = AppLanguage.system.rawValue


    init(
        id: String = "default",
        schemaVersion: Int = SwiftGetXDataSchema.currentModelVersion,
        defaultDownloadDirectoryPath: String,
        concurrentTaskLimit: Int = 3,
        httpMultithreadingEnabled: Bool = true,
        httpSegmentCount: Int = 8,
        hideHTTPTemporaryFiles: Bool = true,
        retryLimit: Int = 3,
        globalDownloadLimitBytes: Int64 = 0,
        globalUploadLimitBytes: Int64 = 0,
        completionNotificationsEnabled: Bool = true,
        completionSoundEnabled: Bool = false,
        completionRevealInFinderEnabled: Bool = false,
        completionOpenFileEnabled: Bool = false,
        completionScriptPath: String = "",
        clipboardDetectionEnabled: Bool = true,
        confirmBrowserTakeoverDownloads: Bool = true,
        browserTakeoverAllowedHosts: [String] = [],
        browserTakeoverBlockedHosts: [String] = [],
        downloadRulesJSON: String = "[]",
        launchAtLoginEnabled: Bool = false,
        keepRunningInMenuBar: Bool = true,
        preventSleepDuringDownloads: Bool = true,
        promptBeforeQuittingWithActiveTasks: Bool = true,
        downloadRestartPolicyRawValue: String = DownloadRestartPolicy.restorePaused.rawValue,
        automaticallyRequeuesFailedTasks: Bool = false,
        queueFailureRetryLimit: Int = 3,
        stopSeedingAtRatio: Double = 1.0,
        stopSeedingAfterSeconds: TimeInterval = 3600,
        torrentDHTEnabled: Bool = true,
        torrentPEXEnabled: Bool = true,
        torrentLSDEnabled: Bool = true,
        torrentSequentialDownloadEnabled: Bool = false,
        torrentMagnetMetadataTimeoutSeconds: Int = 12,
        torrentMaxConnections: Int = 200,
        torrentMaxUploadSlots: Int = 8,
        torrentSeedingLimitModeRawValue: String = TorrentSeedingLimitMode.stopAtRatio.rawValue,
        torrentEngineRawValue: String = TorrentEngineKind.swift.rawValue,
        torrentDHTBootstrapNodes: [String] = TorrentRuntimeOptions.defaultDHTBootstrapNodes,
        diagnosticLogLevelRawValue: String = DiagnosticLogLevel.normal.rawValue,
        languageRawValue: String = AppLanguage.system.rawValue
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.defaultDownloadDirectoryPath = defaultDownloadDirectoryPath
        self.concurrentTaskLimit = concurrentTaskLimit
        self.httpMultithreadingEnabled = httpMultithreadingEnabled
        self.httpSegmentCount = httpSegmentCount
        self.hideHTTPTemporaryFiles = hideHTTPTemporaryFiles
        self.retryLimit = retryLimit
        self.globalDownloadLimitBytes = globalDownloadLimitBytes
        self.globalUploadLimitBytes = globalUploadLimitBytes
        self.completionNotificationsEnabled = completionNotificationsEnabled
        self.completionSoundEnabled = completionSoundEnabled
        self.completionRevealInFinderEnabled = completionRevealInFinderEnabled
        self.completionOpenFileEnabled = completionOpenFileEnabled
        self.completionScriptPath = completionScriptPath
        self.clipboardDetectionEnabled = clipboardDetectionEnabled
        self.confirmBrowserTakeoverDownloads = confirmBrowserTakeoverDownloads
        self.browserTakeoverAllowedHosts = HostPattern.normalized(browserTakeoverAllowedHosts)
        self.browserTakeoverBlockedHosts = HostPattern.normalized(browserTakeoverBlockedHosts)
        self.downloadRulesJSON = downloadRulesJSON
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.keepRunningInMenuBar = keepRunningInMenuBar
        self.preventSleepDuringDownloads = preventSleepDuringDownloads
        self.promptBeforeQuittingWithActiveTasks = promptBeforeQuittingWithActiveTasks
        self.downloadRestartPolicyRawValue = downloadRestartPolicyRawValue
        self.automaticallyRequeuesFailedTasks = automaticallyRequeuesFailedTasks
        self.queueFailureRetryLimit = queueFailureRetryLimit
        self.stopSeedingAtRatio = stopSeedingAtRatio
        self.stopSeedingAfterSeconds = max(1, stopSeedingAfterSeconds)
        self.torrentDHTEnabled = torrentDHTEnabled
        self.torrentPEXEnabled = torrentPEXEnabled
        self.torrentLSDEnabled = torrentLSDEnabled
        self.torrentSequentialDownloadEnabled = torrentSequentialDownloadEnabled
        self.torrentMagnetMetadataTimeoutSeconds = torrentMagnetMetadataTimeoutSeconds
        self.torrentMaxConnections = torrentMaxConnections
        self.torrentMaxUploadSlots = torrentMaxUploadSlots
        self.torrentSeedingLimitModeRawValue = torrentSeedingLimitModeRawValue
        self.torrentEngineRawValue = torrentEngineRawValue
        self.torrentDHTBootstrapNodes = TorrentRuntimeOptions(
            dhtBootstrapNodes: torrentDHTBootstrapNodes
        ).dhtBootstrapNodes
        self.diagnosticLogLevelRawValue = DiagnosticLogLevel(rawValue: diagnosticLogLevelRawValue)?.rawValue
            ?? DiagnosticLogLevel.normal.rawValue
        self.languageRawValue = languageRawValue
    }
}
