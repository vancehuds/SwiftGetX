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
    var stopSeedingAtRatio: Double = 1.0

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
        stopSeedingAtRatio = record.stopSeedingAtRatio
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
            stopSeedingAtRatio: stopSeedingAtRatio
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
        record.stopSeedingAtRatio = stopSeedingAtRatio
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
    var stopSeedingAtRatio: Double

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
        stopSeedingAtRatio: Double = 1.0
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
        self.stopSeedingAtRatio = stopSeedingAtRatio
    }
}
