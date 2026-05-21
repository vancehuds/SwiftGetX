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

    @Test("local torrent preview exposes tracker list")
    func localTorrentPreviewExposesTrackerList() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let sourceURL = directory.appendingPathComponent("tracked.torrent")
        try Self.singleFileTorrentData(
            name: "payload.bin",
            length: 99,
            announce: "http://tracker.example/announce",
            announceList: [
                ["http://tracker.example/announce", "udp://tracker.example:80/announce"],
                ["http://backup.example/announce"]
            ]
        ).write(to: sourceURL)
        let service = TorrentMetadataService()

        let preview = await service.preview(source: sourceURL.path)

        #expect(preview.metadataStatus == .available)
        #expect(preview.trackers == [
            "http://tracker.example/announce",
            "udp://tracker.example:80/announce",
            "http://backup.example/announce"
        ])
    }

    @Test("magnet preview degrades when native engine is unavailable")
    func magnetPreviewDegradesWithoutNativeEngine() async {
        let service = TorrentMetadataService(magnetTimeout: .milliseconds(10))

        let preview = await service.preview(
            source: "magnet:?xt=urn:btih:0123456789012345678901234567890123456789&dn=Demo&tr=http%3A%2F%2Ftracker.example%2Fannounce"
        )

        #expect(preview.kind == .torrentMagnet)
        #expect(preview.displayName == "Demo")
        #expect(preview.trackers == ["http://tracker.example/announce"])
        #expect(preview.metadataStatus == Self.expectedMagnetPreviewPendingStatus)
        #expect(preview.files.isEmpty)
    }

    @Test("magnet preview honors timeout configuration")
    func magnetPreviewHonorsTimeoutConfiguration() async {
        let service = TorrentMetadataService(magnetTimeout: .milliseconds(1))

        let preview = await service.preview(
            source: "magnet:?xt=urn:btih:0123456789012345678901234567890123456789&dn=Timeout"
        )

        #expect(preview.displayName == "Timeout")
        #expect(preview.metadataStatus == Self.expectedMagnetPreviewPendingStatus)
    }

    private static var expectedMagnetPreviewPendingStatus: TorrentMetadataStatus {
        #if canImport(CSwiftGetXLibtorrent)
        return LibtorrentMetadataPreviewer() == nil ? .unavailable : .fetching
        #else
        return .unavailable
        #endif
    }

    private static func singleFileTorrentData(
        name: String,
        length: Int,
        announce: String? = nil,
        announceList: [[String]] = []
    ) -> Data {
        var data = Data("d".utf8)
        if let announce {
            data.append(bencodeString("announce"))
            data.append(bencodeString(announce))
        }
        if !announceList.isEmpty {
            data.append(bencodeString("announce-list"))
            data.append(bencodeList(announceList.map { tier in
                bencodeList(tier.map { bencodeString($0) })
            }))
        }
        data.append(bencodeString("info"))
        data.append(Data("d6:lengthi\(length)e4:name\(name.count):\(name)12:piece lengthi16384e6:pieces20:aaaaaaaaaaaaaaaaaaaae".utf8))
        data.append(UInt8(ascii: "e"))
        return data
    }

    private static func bencodeString(_ value: String) -> Data {
        var data = Data("\(value.utf8.count):".utf8)
        data.append(contentsOf: value.utf8)
        return data
    }

    private static func bencodeList(_ values: [Data]) -> Data {
        var data = Data("l".utf8)
        for value in values {
            data.append(value)
        }
        data.append(UInt8(ascii: "e"))
        return data
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
