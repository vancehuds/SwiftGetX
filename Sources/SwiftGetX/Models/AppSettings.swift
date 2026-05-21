import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppSettings {
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
    var clipboardDetectionEnabled = true
    var confirmBrowserTakeoverDownloads = true
    var downloadRestartPolicy: DownloadRestartPolicy = .restorePaused
    var automaticallyRequeuesFailedTasks = false
    var queueFailureRetryLimit: Int = 3
    var stopSeedingAtRatio: Double = 1.0
    var torrentDHTEnabled = true
    var torrentPEXEnabled = true
    var torrentLSDEnabled = true
    var torrentSequentialDownloadEnabled = false
    var torrentMagnetMetadataTimeoutSeconds = 12
    var torrentMaxConnections = 200
    var torrentMaxUploadSlots = 8
    var torrentSeedingLimitMode: TorrentSeedingLimitMode = .stopAtRatio
    var torrentEngine: TorrentEngineKind = .swift

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
        clipboardDetectionEnabled = record.clipboardDetectionEnabled
        confirmBrowserTakeoverDownloads = record.confirmBrowserTakeoverDownloads
        downloadRestartPolicy = DownloadRestartPolicy(rawValue: record.downloadRestartPolicyRawValue) ?? .restorePaused
        automaticallyRequeuesFailedTasks = record.automaticallyRequeuesFailedTasks
        queueFailureRetryLimit = record.queueFailureRetryLimit
        stopSeedingAtRatio = record.stopSeedingAtRatio
        torrentDHTEnabled = record.torrentDHTEnabled
        torrentPEXEnabled = record.torrentPEXEnabled
        torrentLSDEnabled = record.torrentLSDEnabled
        torrentSequentialDownloadEnabled = record.torrentSequentialDownloadEnabled
        torrentMagnetMetadataTimeoutSeconds = record.torrentMagnetMetadataTimeoutSeconds
        torrentMaxConnections = record.torrentMaxConnections
        torrentMaxUploadSlots = record.torrentMaxUploadSlots
        torrentSeedingLimitMode = TorrentSeedingLimitMode(rawValue: record.torrentSeedingLimitModeRawValue) ?? .stopAtRatio
        torrentEngine = TorrentEngineKind(rawValue: record.torrentEngineRawValue) ?? .swift
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
            clipboardDetectionEnabled: clipboardDetectionEnabled,
            confirmBrowserTakeoverDownloads: confirmBrowserTakeoverDownloads,
            downloadRestartPolicyRawValue: downloadRestartPolicy.rawValue,
            automaticallyRequeuesFailedTasks: automaticallyRequeuesFailedTasks,
            queueFailureRetryLimit: queueFailureRetryLimit,
            stopSeedingAtRatio: stopSeedingAtRatio,
            torrentDHTEnabled: torrentDHTEnabled,
            torrentPEXEnabled: torrentPEXEnabled,
            torrentLSDEnabled: torrentLSDEnabled,
            torrentSequentialDownloadEnabled: torrentSequentialDownloadEnabled,
            torrentMagnetMetadataTimeoutSeconds: torrentMagnetMetadataTimeoutSeconds,
            torrentMaxConnections: torrentMaxConnections,
            torrentMaxUploadSlots: torrentMaxUploadSlots,
            torrentSeedingLimitModeRawValue: torrentSeedingLimitMode.rawValue,
            torrentEngineRawValue: torrentEngine.rawValue
        )
    }

    func update(_ record: AppSettingsRecord) {
        record.defaultDownloadDirectoryPath = defaultDownloadDirectory.path
        record.concurrentTaskLimit = concurrentTaskLimit
        record.httpMultithreadingEnabled = httpMultithreadingEnabled
        record.httpSegmentCount = httpSegmentCount
        record.hideHTTPTemporaryFiles = hideHTTPTemporaryFiles
        record.retryLimit = retryLimit
        record.globalDownloadLimitBytes = globalDownloadLimitBytes
        record.globalUploadLimitBytes = globalUploadLimitBytes
        record.completionNotificationsEnabled = completionNotificationsEnabled
        record.clipboardDetectionEnabled = clipboardDetectionEnabled
        record.confirmBrowserTakeoverDownloads = confirmBrowserTakeoverDownloads
        record.downloadRestartPolicyRawValue = downloadRestartPolicy.rawValue
        record.automaticallyRequeuesFailedTasks = automaticallyRequeuesFailedTasks
        record.queueFailureRetryLimit = queueFailureRetryLimit
        record.stopSeedingAtRatio = stopSeedingAtRatio
        record.torrentDHTEnabled = torrentDHTEnabled
        record.torrentPEXEnabled = torrentPEXEnabled
        record.torrentLSDEnabled = torrentLSDEnabled
        record.torrentSequentialDownloadEnabled = torrentSequentialDownloadEnabled
        record.torrentMagnetMetadataTimeoutSeconds = torrentMagnetMetadataTimeoutSeconds
        record.torrentMaxConnections = torrentMaxConnections
        record.torrentMaxUploadSlots = torrentMaxUploadSlots
        record.torrentSeedingLimitModeRawValue = torrentSeedingLimitMode.rawValue
        record.torrentEngineRawValue = torrentEngine.rawValue
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
            stopSeedingAtRatio: stopSeedingAtRatio
        )
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
    var defaultDownloadDirectoryPath: String
    var concurrentTaskLimit: Int
    var httpMultithreadingEnabled: Bool = true
    var httpSegmentCount: Int
    var hideHTTPTemporaryFiles: Bool = true
    var retryLimit: Int
    var globalDownloadLimitBytes: Int64
    var globalUploadLimitBytes: Int64
    var completionNotificationsEnabled: Bool
    var clipboardDetectionEnabled: Bool
    var confirmBrowserTakeoverDownloads: Bool = true
    var downloadRestartPolicyRawValue: String = DownloadRestartPolicy.restorePaused.rawValue
    var automaticallyRequeuesFailedTasks: Bool = false
    var queueFailureRetryLimit: Int = 3
    var stopSeedingAtRatio: Double
    var torrentDHTEnabled: Bool = true
    var torrentPEXEnabled: Bool = true
    var torrentLSDEnabled: Bool = true
    var torrentSequentialDownloadEnabled: Bool = false
    var torrentMagnetMetadataTimeoutSeconds: Int = 12
    var torrentMaxConnections: Int = 200
    var torrentMaxUploadSlots: Int = 8
    var torrentSeedingLimitModeRawValue: String = TorrentSeedingLimitMode.stopAtRatio.rawValue
    var torrentEngineRawValue: String = TorrentEngineKind.swift.rawValue

    init(
        id: String = "default",
        defaultDownloadDirectoryPath: String,
        concurrentTaskLimit: Int = 3,
        httpMultithreadingEnabled: Bool = true,
        httpSegmentCount: Int = 8,
        hideHTTPTemporaryFiles: Bool = true,
        retryLimit: Int = 3,
        globalDownloadLimitBytes: Int64 = 0,
        globalUploadLimitBytes: Int64 = 0,
        completionNotificationsEnabled: Bool = true,
        clipboardDetectionEnabled: Bool = true,
        confirmBrowserTakeoverDownloads: Bool = true,
        downloadRestartPolicyRawValue: String = DownloadRestartPolicy.restorePaused.rawValue,
        automaticallyRequeuesFailedTasks: Bool = false,
        queueFailureRetryLimit: Int = 3,
        stopSeedingAtRatio: Double = 1.0,
        torrentDHTEnabled: Bool = true,
        torrentPEXEnabled: Bool = true,
        torrentLSDEnabled: Bool = true,
        torrentSequentialDownloadEnabled: Bool = false,
        torrentMagnetMetadataTimeoutSeconds: Int = 12,
        torrentMaxConnections: Int = 200,
        torrentMaxUploadSlots: Int = 8,
        torrentSeedingLimitModeRawValue: String = TorrentSeedingLimitMode.stopAtRatio.rawValue,
        torrentEngineRawValue: String = TorrentEngineKind.swift.rawValue
    ) {
        self.id = id
        self.defaultDownloadDirectoryPath = defaultDownloadDirectoryPath
        self.concurrentTaskLimit = concurrentTaskLimit
        self.httpMultithreadingEnabled = httpMultithreadingEnabled
        self.httpSegmentCount = httpSegmentCount
        self.hideHTTPTemporaryFiles = hideHTTPTemporaryFiles
        self.retryLimit = retryLimit
        self.globalDownloadLimitBytes = globalDownloadLimitBytes
        self.globalUploadLimitBytes = globalUploadLimitBytes
        self.completionNotificationsEnabled = completionNotificationsEnabled
        self.clipboardDetectionEnabled = clipboardDetectionEnabled
        self.confirmBrowserTakeoverDownloads = confirmBrowserTakeoverDownloads
        self.downloadRestartPolicyRawValue = downloadRestartPolicyRawValue
        self.automaticallyRequeuesFailedTasks = automaticallyRequeuesFailedTasks
        self.queueFailureRetryLimit = queueFailureRetryLimit
        self.stopSeedingAtRatio = stopSeedingAtRatio
        self.torrentDHTEnabled = torrentDHTEnabled
        self.torrentPEXEnabled = torrentPEXEnabled
        self.torrentLSDEnabled = torrentLSDEnabled
        self.torrentSequentialDownloadEnabled = torrentSequentialDownloadEnabled
        self.torrentMagnetMetadataTimeoutSeconds = torrentMagnetMetadataTimeoutSeconds
        self.torrentMaxConnections = torrentMaxConnections
        self.torrentMaxUploadSlots = torrentMaxUploadSlots
        self.torrentSeedingLimitModeRawValue = torrentSeedingLimitModeRawValue
        self.torrentEngineRawValue = torrentEngineRawValue
    }
}
