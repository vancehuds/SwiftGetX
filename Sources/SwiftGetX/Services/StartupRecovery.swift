import Foundation
import SwiftData

enum StartupModelContainerState {
    case ready(ModelContainer)
    case failed(StartupRecoveryIssue)
}

struct StartupRecoveryIssue: Equatable {
    var occurredAt: Date
    var errorDescription: String
    var storeURL: URL
    var schemaVersion: String

    var canRebuildPersistentStore: Bool {
        storeURL.isFileURL && !storeURL.path.isEmpty && storeURL.deletingLastPathComponent().path != storeURL.path
    }

    var redactedStorePath: String {
        PrivacyRedactor.redactedText(storeURL.path)
    }
}

struct StartupStoreBackup: Equatable {
    var originalStoreURL: URL
    var backupDirectoryURL: URL
    var movedURLs: [URL]
}

enum StartupRecoveryError: LocalizedError, Equatable {
    case unsafeStoreURL(String)
    case noPersistentStoreFiles(String)

    var errorDescription: String? {
        switch self {
        case .unsafeStoreURL(let path):
            "SwiftGetX could not safely identify the persistent store at \(path)."
        case .noPersistentStoreFiles(let path):
            "SwiftGetX did not find existing persistent store files at \(path)."
        }
    }
}

enum StartupRecoveryService {
    static func openPersistentContainer(
        now: Date = .now,
        makeContainer: () throws -> ModelContainer = { try SwiftGetXPersistence.makeModelContainer() }
    ) -> StartupModelContainerState {
        do {
            return .ready(try makeContainer())
        } catch {
            return .failed(issue(for: error, now: now))
        }
    }

    static func makeTemporaryContainer() throws -> ModelContainer {
        try SwiftGetXPersistence.makeTemporaryModelContainer()
    }

    static func issue(for error: Error, now: Date = .now) -> StartupRecoveryIssue {
        StartupRecoveryIssue(
            occurredAt: now,
            errorDescription: PrivacyRedactor.redactedText(error.localizedDescription),
            storeURL: SwiftGetXPersistence.defaultStoreURL,
            schemaVersion: SwiftGetXPersistence.currentSchemaVersion
        )
    }

    static func diagnosticsText(
        for issue: StartupRecoveryIssue,
        backup: StartupStoreBackup? = nil
    ) -> String {
        var lines = [
            "SwiftGetX Startup Recovery",
            "Occurred: \(ISO8601DateFormatter().string(from: issue.occurredAt))",
            "Schema Version: \(issue.schemaVersion)",
            "Store Path: \(issue.redactedStorePath)",
            "Can Rebuild Persistent Store: \(issue.canRebuildPersistentStore ? "yes" : "no")",
            "Error: \(issue.errorDescription)"
        ]

        if let backup {
            lines.append("Backup Directory: \(PrivacyRedactor.redactedText(backup.backupDirectoryURL.path))")
            lines.append("Moved Store Files: \(backup.movedURLs.map(\.lastPathComponent).joined(separator: ", "))")
        }

        return PrivacyRedactor.redactedText(lines.joined(separator: "\n"))
    }

    @discardableResult
    static func backupAndResetPersistentStore(
        storeURL: URL = SwiftGetXPersistence.defaultStoreURL,
        backupParentDirectory: URL? = nil,
        now: Date = .now,
        fileManager: FileManager = .default
    ) throws -> StartupStoreBackup {
        let standardizedStoreURL = storeURL.standardizedFileURL
        guard standardizedStoreURL.isFileURL,
              !standardizedStoreURL.path.isEmpty,
              standardizedStoreURL.deletingLastPathComponent().path != standardizedStoreURL.path
        else {
            throw StartupRecoveryError.unsafeStoreURL(storeURL.path)
        }

        var isDirectory = ObjCBool(false)
        if fileManager.fileExists(atPath: standardizedStoreURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue
        {
            throw StartupRecoveryError.unsafeStoreURL(standardizedStoreURL.path)
        }

        let relatedURLs = persistentStoreRelatedURLs(
            for: standardizedStoreURL,
            fileManager: fileManager
        )
        guard !relatedURLs.isEmpty else {
            throw StartupRecoveryError.noPersistentStoreFiles(standardizedStoreURL.path)
        }

        let parentDirectory = backupParentDirectory?.standardizedFileURL
            ?? standardizedStoreURL.deletingLastPathComponent()
        let backupDirectory = uniqueBackupDirectory(
            in: parentDirectory,
            now: now,
            fileManager: fileManager
        )

        try fileManager.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )

        var movedURLs = [URL]()
        do {
            for url in relatedURLs {
                let destination = backupDirectory.appendingPathComponent(url.lastPathComponent)
                try fileManager.moveItem(at: url, to: destination)
                movedURLs.append(destination)
            }
        } catch {
            for movedURL in movedURLs.reversed() {
                let originalURL = standardizedStoreURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(movedURL.lastPathComponent)
                if fileManager.fileExists(atPath: movedURL.path),
                   !fileManager.fileExists(atPath: originalURL.path)
                {
                    try? fileManager.moveItem(at: movedURL, to: originalURL)
                }
            }
            throw error
        }

        return StartupStoreBackup(
            originalStoreURL: standardizedStoreURL,
            backupDirectoryURL: backupDirectory,
            movedURLs: movedURLs
        )
    }

    static func persistentStoreRelatedURLs(
        for storeURL: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        let standardizedStoreURL = storeURL.standardizedFileURL
        let sidecarPaths = [
            standardizedStoreURL.path,
            "\(standardizedStoreURL.path)-shm",
            "\(standardizedStoreURL.path)-wal",
            "\(standardizedStoreURL.path)-journal"
        ]

        var seen = Set<String>()
        return sidecarPaths.compactMap { path in
            guard !path.isEmpty, seen.insert(path).inserted else { return nil }
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else { return nil }
            return URL(fileURLWithPath: path).standardizedFileURL
        }
    }

    private static func uniqueBackupDirectory(
        in parentDirectory: URL,
        now: Date,
        fileManager: FileManager
    ) -> URL {
        let timestamp = Int(now.timeIntervalSince1970)
        let baseName = "SwiftGetX-Recovered-Store-\(timestamp)"
        var candidate = parentDirectory.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parentDirectory.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }
}
