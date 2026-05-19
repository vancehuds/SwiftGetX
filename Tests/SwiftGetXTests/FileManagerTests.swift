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
}
