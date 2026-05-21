import Foundation
import SwiftGetXCore

enum SwiftGetXDataSchema {
    static let currentModelVersion = 2
    static let currentArchiveVersion = 1
    static let minimumSupportedArchiveVersion = 1

    static let migrationPlan = [
        "v1: Initial SwiftData task and settings records.",
        "v2: Optional additive fields for browser context, HTTP metadata/options, queue state, torrent runtime data, task organization, system behavior, and download rules. Invalid optional JSON blobs are dropped during repair instead of blocking app startup."
    ]
}

struct SwiftGetXDataArchive: Codable, Equatable {
    var archiveVersion: Int
    var modelVersion: Int
    var exportedAt: Date
    var settings: AppSettingsArchive?
    var tasks: [DownloadTaskArchive]

    init(
        archiveVersion: Int = SwiftGetXDataSchema.currentArchiveVersion,
        modelVersion: Int = SwiftGetXDataSchema.currentModelVersion,
        exportedAt: Date = .now,
        settings: AppSettingsArchive?,
        tasks: [DownloadTaskArchive]
    ) {
        self.archiveVersion = archiveVersion
        self.modelVersion = modelVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.tasks = tasks
    }

    init(settingsRecord: AppSettingsRecord?, tasks: [DownloadTask], redactsSensitiveData: Bool = true) {
        self.init(
            settings: settingsRecord.map(AppSettingsArchive.init(record:)),
            tasks: tasks.map { DownloadTaskArchive(task: $0, redactsSensitiveData: redactsSensitiveData) }
        )
    }

    func validateSupportedVersion() throws {
        guard archiveVersion >= SwiftGetXDataSchema.minimumSupportedArchiveVersion,
              archiveVersion <= SwiftGetXDataSchema.currentArchiveVersion
        else {
            throw PersistenceArchiveError.unsupportedArchiveVersion(archiveVersion)
        }
    }
}

enum PersistenceArchiveError: LocalizedError, Equatable {
    case unsupportedArchiveVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedArchiveVersion(let version):
            "Unsupported SwiftGetX archive version \(version)"
        }
    }
}

extension AppSettingsRecord {
    @discardableResult
    func repairInvalidJSONFields() -> [String] {
        var repaired = [String]()
        if schemaVersion < SwiftGetXDataSchema.currentModelVersion {
            schemaVersion = SwiftGetXDataSchema.currentModelVersion
            repaired.append("schemaVersion")
        }
        if (try? JSONDecoder().decode([DownloadRule].self, from: Data(downloadRulesJSON.utf8))) == nil {
            downloadRulesJSON = "[]"
            repaired.append("downloadRulesJSON")
        } else {
            let sanitized = Self.sanitizedDownloadRulesJSON(downloadRulesJSON)
            if sanitized != downloadRulesJSON {
                downloadRulesJSON = sanitized
                repaired.append("downloadRulesJSON.sanitized")
            }
        }
        return repaired
    }

    private static func sanitizedDownloadRulesJSON(_ json: String) -> String {
        guard let rules = try? JSONDecoder().decode([DownloadRule].self, from: Data(json.utf8)),
              let data = try? JSONEncoder().encode(Array(rules.prefix(DownloadRule.maximumRuleCount))),
              let sanitized = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return sanitized
    }
}

struct AppSettingsArchive: Codable, Equatable {
    var schemaVersion: Int
    var defaultDownloadDirectoryPath: String
    var concurrentTaskLimit: Int
    var httpMultithreadingEnabled: Bool
    var httpSegmentCount: Int
    var hideHTTPTemporaryFiles: Bool
    var retryLimit: Int
    var globalDownloadLimitBytes: Int64
    var globalUploadLimitBytes: Int64
    var completionNotificationsEnabled: Bool
    var completionSoundEnabled: Bool
    var completionRevealInFinderEnabled: Bool
    var completionOpenFileEnabled: Bool
    var completionScriptPath: String
    var clipboardDetectionEnabled: Bool
    var confirmBrowserTakeoverDownloads: Bool
    var browserTakeoverAllowedHosts: [String]
    var browserTakeoverBlockedHosts: [String]
    var downloadRules: [DownloadRule]
    var launchAtLoginEnabled: Bool
    var keepRunningInMenuBar: Bool
    var preventSleepDuringDownloads: Bool
    var promptBeforeQuittingWithActiveTasks: Bool
    var downloadRestartPolicy: DownloadRestartPolicy
    var automaticallyRequeuesFailedTasks: Bool
    var queueFailureRetryLimit: Int
    var stopSeedingAtRatio: Double
    var stopSeedingAfterSeconds: TimeInterval
    var torrentDHTEnabled: Bool
    var torrentPEXEnabled: Bool
    var torrentLSDEnabled: Bool
    var torrentSequentialDownloadEnabled: Bool
    var torrentMagnetMetadataTimeoutSeconds: Int
    var torrentMaxConnections: Int
    var torrentMaxUploadSlots: Int
    var torrentSeedingLimitMode: TorrentSeedingLimitMode
    var torrentEngine: TorrentEngineKind
    var torrentDHTBootstrapNodes: [String]
    var language: AppLanguage

    init(record: AppSettingsRecord) {
        schemaVersion = record.schemaVersion
        defaultDownloadDirectoryPath = record.defaultDownloadDirectoryPath
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
        downloadRules = Self.decodeDownloadRules(record.downloadRulesJSON)
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
        torrentDHTBootstrapNodes = TorrentRuntimeOptions(
            dhtBootstrapNodes: record.torrentDHTBootstrapNodes
        ).dhtBootstrapNodes
        language = AppLanguage(rawValue: record.languageRawValue) ?? .system
    }

    func makeRecord(id: String = "default") -> AppSettingsRecord {
        AppSettingsRecord(
            id: id,
            schemaVersion: SwiftGetXDataSchema.currentModelVersion,
            defaultDownloadDirectoryPath: defaultDownloadDirectoryPath,
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
            browserTakeoverAllowedHosts: browserTakeoverAllowedHosts,
            browserTakeoverBlockedHosts: browserTakeoverBlockedHosts,
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
            torrentDHTBootstrapNodes: torrentDHTBootstrapNodes,
            languageRawValue: language.rawValue
        )
    }

    private static func encodeDownloadRules(_ rules: [DownloadRule]) -> String {
        guard let data = try? JSONEncoder().encode(Array(rules.prefix(DownloadRule.maximumRuleCount))),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }

    private static func decodeDownloadRules(_ json: String) -> [DownloadRule] {
        guard let rules = try? JSONDecoder().decode([DownloadRule].self, from: Data(json.utf8)) else {
            return []
        }
        return Array(rules.prefix(DownloadRule.maximumRuleCount))
    }
}

struct DownloadTaskArchive: Codable, Equatable {
    var id: UUID
    var name: String
    var source: String
    var kind: DownloadKind
    var status: DownloadStatus
    var savePath: String
    var totalBytes: Int64
    var downloadedBytes: Int64
    var speedBytesPerSecond: Int64
    var etaSeconds: TimeInterval?
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var finishedAt: Date?
    var averageSpeedBytesPerSecond: Int64
    var peakSpeedBytesPerSecond: Int64
    var errorMessage: String?
    var retryCount: Int
    var supportsResume: Bool
    var eTag: String?
    var lastModified: String?
    var resolvedTorrentFilePath: String?
    var torrentMetadataStatus: TorrentMetadataStatus
    var torrentConnection: TorrentConnectionInfo?
    var torrentResumeState: TorrentResumeState?
    var torrentTrackers: [TorrentTrackerInfo]
    var torrentPeers: [TorrentPeerInfo]
    var torrentRuntimeOptions: TorrentRuntimeOptions?
    var torrentHealth: TorrentHealthInfo?
    var torrentSaveDirectoryPath: String?
    var torrentOutputName: String?
    var torrentContentRootPath: String?
    var torrentFinalFilePath: String?
    var selectedFileIndexes: [Int]
    var torrentFiles: [TorrentFile]
    var connectionSummary: String?
    var browserContext: BrowserDownloadContext?
    var httpResponseMetadata: HTTPResponseMetadata?
    var httpOptions: HTTPDownloadOptions?
    var httpSegments: [HTTPSegmentInfo]
    var queuePosition: Double
    var queuePriority: DownloadQueuePriority
    var queueFailureCount: Int
    var nextQueueRetryAt: Date?
    var category: DownloadTaskCategory
    var tags: [String]
    var archivedAt: Date?
    var perTaskDownloadLimitBytes: Int64
    var perTaskUploadLimitBytes: Int64
    var logEntries: [String]

    init(task: DownloadTask, redactsSensitiveData: Bool = true) {
        id = task.id
        name = task.name
        source = redactsSensitiveData
            ? PrivacyRedactor.redactedURLString(task.source) ?? task.source
            : task.source
        kind = task.kind
        status = task.status
        savePath = task.savePath
        totalBytes = task.totalBytes
        downloadedBytes = task.downloadedBytes
        speedBytesPerSecond = task.speedBytesPerSecond
        etaSeconds = task.etaSeconds
        createdAt = task.createdAt
        startedAt = task.startedAt
        completedAt = task.completedAt
        finishedAt = task.finishedAt
        averageSpeedBytesPerSecond = task.averageSpeedBytesPerSecond
        peakSpeedBytesPerSecond = task.peakSpeedBytesPerSecond
        errorMessage = task.errorMessage.map(PrivacyRedactor.redactedText)
        retryCount = task.retryCount
        supportsResume = task.supportsResume
        eTag = task.eTag
        lastModified = task.lastModified
        resolvedTorrentFilePath = task.resolvedTorrentFilePath
        torrentMetadataStatus = task.torrentMetadataStatus
        torrentConnection = task.torrentConnection
        torrentResumeState = task.torrentResumeState
        torrentTrackers = Self.redactedTrackers(task.torrentTrackers, redactsSensitiveData: redactsSensitiveData)
        torrentPeers = task.torrentPeers
        torrentRuntimeOptions = task.torrentRuntimeOptions
        torrentHealth = task.torrentHealth
        torrentSaveDirectoryPath = task.torrentSaveDirectoryPath
        torrentOutputName = task.torrentOutputName
        torrentContentRootPath = task.torrentContentRootPath
        torrentFinalFilePath = task.torrentFinalFilePath
        selectedFileIndexes = task.selectedFileIndexes
        torrentFiles = task.torrentFiles
        connectionSummary = task.connectionSummary.map(PrivacyRedactor.redactedText)
        browserContext = redactsSensitiveData ? task.browserContext?.persistable : task.browserContext
        httpResponseMetadata = task.httpResponseMetadata
        httpOptions = redactsSensitiveData ? task.httpOptions?.persistable : task.httpOptions
        httpSegments = task.httpSegments
        queuePosition = task.queuePosition
        queuePriority = task.queuePriority
        queueFailureCount = task.queueFailureCount
        nextQueueRetryAt = task.nextQueueRetryAt
        category = task.category
        tags = task.normalizedTags
        archivedAt = task.archivedAt
        perTaskDownloadLimitBytes = task.perTaskDownloadLimitBytes
        perTaskUploadLimitBytes = task.perTaskUploadLimitBytes
        logEntries = task.logEntries.map(PrivacyRedactor.redactedText)
    }

    func makeTask() -> DownloadTask {
        DownloadTask(
            id: id,
            name: name,
            source: source,
            kind: kind,
            status: status,
            savePath: savePath,
            totalBytes: totalBytes,
            downloadedBytes: downloadedBytes,
            speedBytesPerSecond: speedBytesPerSecond,
            etaSeconds: etaSeconds,
            createdAt: createdAt,
            startedAt: startedAt,
            completedAt: completedAt,
            finishedAt: finishedAt,
            averageSpeedBytesPerSecond: averageSpeedBytesPerSecond,
            peakSpeedBytesPerSecond: peakSpeedBytesPerSecond,
            errorMessage: errorMessage.map(PrivacyRedactor.redactedText),
            retryCount: retryCount,
            supportsResume: supportsResume,
            eTag: eTag,
            lastModified: lastModified,
            resolvedTorrentFilePath: resolvedTorrentFilePath,
            torrentMetadataStatus: torrentMetadataStatus,
            torrentSaveDirectoryPath: torrentSaveDirectoryPath,
            torrentOutputName: torrentOutputName,
            torrentContentRootPath: torrentContentRootPath,
            torrentFinalFilePath: torrentFinalFilePath,
            selectedFileIndexes: selectedFileIndexes,
            connectionSummary: connectionSummary.map(PrivacyRedactor.redactedText),
            browserContext: browserContext?.persistable,
            httpResponseMetadata: httpResponseMetadata,
            httpOptions: httpOptions?.persistable,
            httpSegments: httpSegments,
            queuePosition: queuePosition,
            queuePriority: queuePriority,
            queueFailureCount: queueFailureCount,
            nextQueueRetryAt: nextQueueRetryAt,
            category: category,
            tags: tags,
            archivedAt: archivedAt,
            perTaskDownloadLimitBytes: perTaskDownloadLimitBytes,
            perTaskUploadLimitBytes: perTaskUploadLimitBytes,
            logEntries: logEntries.map(PrivacyRedactor.redactedText)
        ).configured { task in
            task.torrentConnection = torrentConnection
            task.torrentResumeState = torrentResumeState
            task.torrentTrackers = torrentTrackers
            task.torrentPeers = torrentPeers
            task.torrentRuntimeOptions = torrentRuntimeOptions
            task.torrentHealth = torrentHealth
            task.torrentFiles = torrentFiles
        }
    }

    private static func redactedTrackers(
        _ trackers: [TorrentTrackerInfo],
        redactsSensitiveData: Bool
    ) -> [TorrentTrackerInfo] {
        guard redactsSensitiveData else { return trackers }
        return trackers.map { tracker in
            var redacted = tracker
            redacted.url = PrivacyRedactor.redactedURLString(tracker.url) ?? tracker.url
            redacted.errorMessage = tracker.errorMessage.map(PrivacyRedactor.redactedText)
            return redacted
        }
    }
}

private extension DownloadTask {
    func configured(_ update: (DownloadTask) -> Void) -> DownloadTask {
        update(self)
        return self
    }
}
