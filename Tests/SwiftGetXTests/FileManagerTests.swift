import Foundation
import Testing
@testable import SwiftGetX

@Suite("FileManager helpers")
struct FileManagerTests {
    @Test("uniqueFileURL appends numeric suffix")
    func uniqueFileURL() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let original = directory.appendingPathComponent("archive.zip")
        FileManager.default.createFile(atPath: original.path, contents: Data())

        let candidate = FileManager.default.uniqueFileURL(for: original)

        #expect(candidate.lastPathComponent == "archive 2.zip")
    }

    @Test("filesystem safety rejects symlink escapes from allowed roots")
    func filesystemSafetyRejectsSymlinkEscapes() throws {
        let root = try makeTemporaryDirectory()
        let outside = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let outsideFile = outside.appendingPathComponent("outside.txt")
        let link = root.appendingPathComponent("link.txt")
        try Data("outside".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideFile)

        let planned = FileSystemSafety.safeDeletionURLs(
            candidates: [link],
            allowedRoot: root,
            allowsDirectories: false
        )

        #expect(planned.isEmpty)
        #expect(throws: FileSystemSafetyError.unsafeDeletionTarget(link.path)) {
            try FileSystemSafety.removeSafely(
                link,
                allowedRoot: root,
                allowsDirectories: false
            )
        }
        #expect(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
