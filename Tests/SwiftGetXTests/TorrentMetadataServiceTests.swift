import Foundation
import Testing
@testable import SwiftGetX

@Suite("TorrentMetadataService")
struct TorrentMetadataServiceTests {
    @Test("parses single-file torrent metadata")
    func parsesSingleFileTorrentMetadata() throws {
        let data = Self.singleFileTorrentData(name: "demo.bin", length: 42)

        let metadata = try TorrentFileParser.parse(data: data)

        #expect(metadata.name == "demo.bin")
        #expect(metadata.totalBytes == 42)
        #expect(metadata.files == [
            TorrentFile(index: 0, path: "demo.bin", size: 42)
        ])
    }

    @Test("parses multi-file torrent metadata")
    func parsesMultiFileTorrentMetadata() throws {
        let data = Self.multiFileTorrentData()

        let metadata = try TorrentFileParser.parse(data: data)

        #expect(metadata.name == "album")
        #expect(metadata.totalBytes == 30)
        #expect(metadata.files == [
            TorrentFile(index: 0, path: "album/a.txt", size: 10),
            TorrentFile(index: 1, path: "album/nested/b.txt", size: 20)
        ])
    }

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
        #expect(preview.metadataStatus == .unavailable)
        #expect(preview.files.isEmpty)
    }

    @Test("magnet preview honors timeout configuration")
    func magnetPreviewHonorsTimeoutConfiguration() async {
        let service = TorrentMetadataService(magnetTimeout: .milliseconds(1))

        let preview = await service.preview(source: "magnet:?xt=urn:btih:abcdef&dn=Timeout")

        #expect(preview.displayName == "Timeout")
        #expect(preview.metadataStatus == .unavailable)
    }

    private static func singleFileTorrentData(name: String, length: Int) -> Data {
        Data("d4:infod6:lengthi\(length)e4:name\(name.count):\(name)ee".utf8)
    }

    private static func multiFileTorrentData() -> Data {
        Data("d4:infod5:filesld6:lengthi10e4:pathl5:a.txteed6:lengthi20e4:pathl6:nested5:b.txteee4:name5:albumee".utf8)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
