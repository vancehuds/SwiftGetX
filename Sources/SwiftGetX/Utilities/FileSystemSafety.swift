import Darwin
import Foundation

enum FileSystemSafety {
    @discardableResult
    static func removeSafely(
        _ url: URL,
        allowedRoot: URL,
        allowsDirectories: Bool
    ) throws -> Bool {
        let targetURL = url.standardizedFileURL
        let rootURL = allowedRoot.standardizedFileURL
        guard isUsableRoot(rootURL),
              targetURL.resolvedForBoundaryCheck.isDescendant(of: rootURL.resolvedForBoundaryCheck)
        else {
            throw SafetyError.unsafeDeletionTarget(targetURL.path)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory) else {
            return false
        }
        guard allowsDirectories || !isDirectory.boolValue else {
            throw SafetyError.unsafeDeletionTarget(targetURL.path)
        }

        try FileManager.default.removeItem(at: targetURL)
        return true
    }

    static func safeDeletionURLs(
        candidates: [URL],
        allowedRoot: URL,
        allowsDirectories: Bool,
        requiresExisting: Bool = true
    ) -> [URL] {
        let rootURL = allowedRoot.standardizedFileURL
        guard isUsableRoot(rootURL) else { return [] }

        var seen = Set<String>()
        var safeURLs = [URL]()
        for candidate in candidates {
            let url = candidate.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard url.resolvedForBoundaryCheck.isDescendant(of: rootURL.resolvedForBoundaryCheck),
                  seen.insert(url.path).inserted
            else {
                continue
            }
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                guard allowsDirectories || !isDirectory.boolValue else { continue }
            } else if requiresExisting {
                continue
            }
            safeURLs.append(url)
        }
        return safeURLs
    }

    static func preflightDownloadDestination(
        _ destination: URL,
        expectedBytes: Int64,
        existingBytes: Int64,
        additionalScratchBytes: Int64 = 0
    ) throws {
        let destinationURL = destination.standardizedFileURL
        let directory = destinationURL.deletingLastPathComponent()
        try preflightDirectory(directory)

        guard destinationURL.resolvedForBoundaryCheck.isDescendant(of: directory.resolvedForBoundaryCheck) else {
            throw SafetyError.pathEscapesDirectory(destinationURL.path)
        }

        var destinationIsDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: destinationURL.path, isDirectory: &destinationIsDirectory),
           destinationIsDirectory.boolValue
        {
            throw SafetyError.destinationIsDirectory(destinationURL.path)
        }

        try checkAvailableCapacity(
            directory: directory,
            expectedBytes: expectedBytes,
            existingBytes: existingBytes,
            additionalScratchBytes: additionalScratchBytes
        )
    }

    static func preflightTorrentLayout(
        saveDirectory: URL,
        contentRoot: URL,
        fileURLs: [URL],
        expectedBytes: Int64,
        existingBytes: Int64
    ) throws {
        let saveDirectoryURL = saveDirectory.standardizedFileURL
        let contentRootURL = contentRoot.standardizedFileURL
        try preflightDirectory(saveDirectoryURL)
        let resolvedSaveDirectory = saveDirectoryURL.resolvedForBoundaryCheck
        let resolvedContentRoot = contentRootURL.resolvedForBoundaryCheck

        guard resolvedContentRoot.path == resolvedSaveDirectory.path
            || resolvedContentRoot.isDescendant(of: resolvedSaveDirectory)
        else {
            throw SafetyError.pathEscapesDirectory(contentRootURL.path)
        }

        for fileURL in fileURLs {
            let standardizedFileURL = fileURL.standardizedFileURL
            let resolvedFileURL = standardizedFileURL.resolvedForBoundaryCheck
            guard resolvedFileURL.isDescendant(of: resolvedSaveDirectory),
                  resolvedContentRoot.path == resolvedSaveDirectory.path
                    || resolvedFileURL.isDescendant(of: resolvedContentRoot)
            else {
                throw SafetyError.pathEscapesDirectory(standardizedFileURL.path)
            }
        }

        try checkAvailableCapacity(
            directory: saveDirectoryURL,
            expectedBytes: expectedBytes,
            existingBytes: existingBytes
        )
    }

    static func preallocateFile(at url: URL, byteCount: Int64) throws {
        guard byteCount > 0 else { return }
        let fileURL = url.standardizedFileURL
        let parent = fileURL.deletingLastPathComponent()
        guard fileURL.resolvedForBoundaryCheck.isDescendant(of: parent.resolvedForBoundaryCheck) else {
            throw SafetyError.pathEscapesDirectory(fileURL.path)
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        let fd = open(fileURL.path, O_RDWR)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }

        var store = fstore_t(
            fst_flags: UInt32(F_ALLOCATECONTIG),
            fst_posmode: Int32(F_PEOFPOSMODE),
            fst_offset: 0,
            fst_length: off_t(byteCount),
            fst_bytesalloc: 0
        )
        if fcntl(fd, F_PREALLOCATE, &store) == -1 {
            store.fst_flags = UInt32(F_ALLOCATEALL)
            guard fcntl(fd, F_PREALLOCATE, &store) != -1 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOSPC)
            }
        }
    }

    private static func preflightDirectory(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) else {
            throw SafetyError.directoryMissing(directory.path)
        }
        guard isDirectory.boolValue else {
            throw SafetyError.directoryNotFolder(directory.path)
        }
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw SafetyError.directoryNotWritable(directory.path)
        }

        let probeURL = directory.appendingPathComponent(".swiftgetx-write-\(UUID().uuidString)")
        do {
            try Data().write(to: probeURL, options: .withoutOverwriting)
            try? FileManager.default.removeItem(at: probeURL)
        } catch {
            try? FileManager.default.removeItem(at: probeURL)
            throw SafetyError.writeProbeFailed(directory.path, error.localizedDescription)
        }
    }

    private static func checkAvailableCapacity(
        directory: URL,
        expectedBytes: Int64,
        existingBytes: Int64,
        additionalScratchBytes: Int64 = 0
    ) throws {
        let remainingBytes = max(0, expectedBytes - max(0, existingBytes))
            + max(0, additionalScratchBytes)
        guard remainingBytes > 0,
              let availableBytes = availableCapacity(for: directory),
              availableBytes < remainingBytes
        else {
            return
        }

        throw SafetyError.insufficientSpace(required: remainingBytes, available: availableBytes)
    }

    private static func availableCapacity(for directory: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let values = try? directory.resourceValues(forKeys: keys) else { return nil }
        if let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        if let capacity = values.volumeAvailableCapacity {
            return Int64(capacity)
        }
        return nil
    }

    private static func isUsableRoot(_ url: URL) -> Bool {
        url.isFileURL && !url.path.isEmpty && url.path != "/"
    }
}

enum FileSystemSafetyError: LocalizedError, Equatable {
    case directoryMissing(String)
    case directoryNotFolder(String)
    case directoryNotWritable(String)
    case destinationIsDirectory(String)
    case pathEscapesDirectory(String)
    case writeProbeFailed(String, String)
    case insufficientSpace(required: Int64, available: Int64)
    case unsafeDeletionTarget(String)

    var errorDescription: String? {
        switch self {
        case .directoryMissing(let path):
            L10n.string("error_download_directory_missing", path)
        case .directoryNotFolder(let path):
            L10n.string("error_download_directory_not_folder", path)
        case .directoryNotWritable(let path):
            L10n.string("error_download_directory_not_writable", path)
        case .destinationIsDirectory(let path):
            L10n.string("error_download_path_is_directory", path)
        case .pathEscapesDirectory(let path):
            L10n.string("error_download_path_escapes_directory", path)
        case .writeProbeFailed(let path, let reason):
            L10n.string("error_download_write_probe_failed", path, reason)
        case .insufficientSpace(let required, let available):
            L10n.string(
                "error_insufficient_disk_space",
                ByteCountFormatter.string(fromByteCount: required, countStyle: .file),
                ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            )
        case .unsafeDeletionTarget(let path):
            L10n.string("error_unsafe_deletion_target", path)
        }
    }
}

private typealias SafetyError = FileSystemSafetyError

extension URL {
    var resolvedForBoundaryCheck: URL {
        standardizedFileURL.resolvingSymlinksInPath()
    }

    func isDescendant(of ancestor: URL) -> Bool {
        let ancestorPath = ancestor.standardizedFileURL.path
        let path = standardizedFileURL.path
        guard path.hasPrefix(ancestorPath) else { return false }
        if path == ancestorPath { return true }
        return path.dropFirst(ancestorPath.count).first == "/"
    }
}
