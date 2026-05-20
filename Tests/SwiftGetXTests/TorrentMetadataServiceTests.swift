import Foundation
import Testing
@testable import SwiftGetX

@Suite("TorrentMetadataService")
struct TorrentMetadataServiceTests {
    @Test("copies local torrent file into cache before preview")
    func copiesLocalTorrentFileIntoCacheBeforePreview() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let sourceURL = directory.appendingPathComponent("source.torrent")
        try Self.singleFileTorrentData(name: "payload.bin", length: 99).write(to: sourceURL)
        let service = TorrentMetadataService()

        let preview = await service.preview(source: sourceURL.path)

        #expect(preview.metadataStatus == .available)
        #expect(preview.displayName == "payload.bin")
        #expect(preview.totalBytes == 99)
        #expect(preview.resolvedTorrentFilePath != nil)
        #expect(preview.resolvedTorrentFilePath != sourceURL.path)
    }

    @Test("magnet preview degrades when native engine is unavailable")
    func magnetPreviewDegradesWithoutNativeEngine() async {
        let service = TorrentMetadataService(magnetTimeout: .milliseconds(10))

        let preview = await service.preview(source: "magnet:?xt=urn:btih:abcdef&dn=Demo")

        #expect(preview.kind == .torrentMagnet)
        #expect(preview.displayName == "Demo")
        #if canImport(CSwiftGetXLibtorrent)
        #expect(preview.metadataStatus == .fetching)
        #else
        #expect(preview.metadataStatus == .unavailable)
        #endif
        #expect(preview.files.isEmpty)
    }

    @Test("magnet preview honors timeout configuration")
    func magnetPreviewHonorsTimeoutConfiguration() async {
        let service = TorrentMetadataService(magnetTimeout: .milliseconds(1))

        let preview = await service.preview(source: "magnet:?xt=urn:btih:abcdef&dn=Timeout")

        #expect(preview.displayName == "Timeout")
        #if canImport(CSwiftGetXLibtorrent)
        #expect(preview.metadataStatus == .fetching)
        #else
        #expect(preview.metadataStatus == .unavailable)
        #endif
    }

    private static func singleFileTorrentData(name: String, length: Int) -> Data {
        Data("d4:infod6:lengthi\(length)e4:name\(name.count):\(name)12:piece lengthi16384e6:pieces20:aaaaaaaaaaaaaaaaaaaaee".utf8)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
