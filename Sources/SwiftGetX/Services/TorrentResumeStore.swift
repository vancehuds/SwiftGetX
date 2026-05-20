import Foundation

enum TorrentResumeStore {
    static func resumeDataPath(for taskID: UUID, fileManager: FileManager = .default) -> String? {
        guard let directory = try? resumeDirectory(fileManager: fileManager) else { return nil }
        return directory.appendingPathComponent("\(taskID.uuidString).fastresume").path
    }

    static func removeResumeData(for taskID: UUID, fileManager: FileManager = .default) {
        guard let path = resumeDataPath(for: taskID, fileManager: fileManager) else { return }
        try? fileManager.removeItem(atPath: path)
    }

    private static func resumeDirectory(fileManager: FileManager) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("SwiftGetX/Torrents/Resume", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
