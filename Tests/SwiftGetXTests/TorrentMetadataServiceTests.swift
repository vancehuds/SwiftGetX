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

    @Test("local torrent preview exposes web seed list")
    func localTorrentPreviewExposesWebSeedList() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let sourceURL = directory.appendingPathComponent("web-seeded.torrent")
        try Self.singleFileTorrentData(
            name: "payload.bin",
            length: 99,
            urlList: [
                "https://seed.example/payload.bin",
                "  https://mirror.example/payload.bin  "
            ],
            httpSeeds: ["https://seed.example/payload.bin"]
        ).write(to: sourceURL)
        let service = TorrentMetadataService()

        let preview = await service.preview(source: sourceURL.path)

        #expect(preview.metadataStatus == .available)
        #expect(preview.webSeeds == [
            "https://seed.example/payload.bin",
            "https://mirror.example/payload.bin"
        ])
    }

    @Test("magnet preview exposes files before download")
    func magnetPreviewExposesFilesBeforeDownload() async {
        let service = TorrentMetadataService(magnetPreview: { _ in
            TorrentMagnetPreviewResult(
                displayName: "Demo",
                files: [
                    TorrentFile(index: 0, path: "Demo/movie.mkv", size: 100),
                    TorrentFile(index: 1, path: "Demo/readme.txt", size: 20)
                ],
                trackers: ["udp://tracker.example:80/announce"],
                webSeeds: ["https://preview-seed.example/demo"]
            )
        })

        let preview = await service.preview(
            source: "magnet:?xt=urn:btih:0123456789012345678901234567890123456789&dn=Fallback&tr=http%3A%2F%2Ftracker.example%2Fannounce&ws=https%3A%2F%2Fsource-seed.example%2Fdemo"
        )

        #expect(preview.kind == .torrentMagnet)
        #expect(preview.displayName == "Demo")
        #expect(preview.metadataStatus == .available)
        #expect(preview.totalBytes == 120)
        #expect(preview.trackers == [
            "udp://tracker.example:80/announce",
            "http://tracker.example/announce"
        ])
        #expect(preview.webSeeds == [
            "https://preview-seed.example/demo",
            "https://source-seed.example/demo"
        ])
        #expect(preview.selectedFileIndexes == [0, 1])
        #expect(preview.files.map(\.path) == ["Demo/movie.mkv", "Demo/readme.txt"])
    }

    @Test("magnet preview honors timeout configuration")
    func magnetPreviewHonorsTimeoutConfiguration() async {
        let service = TorrentMetadataService(
            magnetTimeout: .milliseconds(1),
            magnetPreview: { _ in
                try await Task.sleep(for: .seconds(60))
                return TorrentMagnetPreviewResult(files: [])
            }
        )

        let preview = await service.preview(
            source: "magnet:?xt=urn:btih:0123456789012345678901234567890123456789&dn=Timeout&xl=42&tr=udp%3A%2F%2Ftimeout.example%3A80%2Fannounce&ws=https%3A%2F%2Ftimeout-seed.example%2Fpayload.bin"
        )

        #expect(preview.displayName == "Timeout")
        #expect(preview.metadataStatus == .fetching)
        #expect(preview.totalBytes == 42)
        #expect(preview.trackers == ["udp://timeout.example:80/announce"])
        #expect(preview.webSeeds == ["https://timeout-seed.example/payload.bin"])
        #expect(preview.files.isEmpty)
    }

    private static func singleFileTorrentData(
        name: String,
        length: Int,
        announce: String? = nil,
        announceList: [[String]] = [],
        urlList: [String] = [],
        httpSeeds: [String] = []
    ) -> Data {
        var fields = [(String, Data)]()
        if let announce {
            fields.append(("announce", bencodeString(announce)))
        }
        if !announceList.isEmpty {
            fields.append(("announce-list", bencodeList(announceList.map { tier in
                bencodeList(tier.map { bencodeString($0) })
            })))
        }
        if !httpSeeds.isEmpty {
            fields.append(("httpseeds", bencodeList(httpSeeds.map { bencodeString($0) })))
        }
        fields.append((
            "info",
            Data("d6:lengthi\(length)e4:name\(name.count):\(name)12:piece lengthi16384e6:pieces20:aaaaaaaaaaaaaaaaaaaae".utf8)
        ))
        if !urlList.isEmpty {
            fields.append(("url-list", bencodeList(urlList.map { bencodeString($0) })))
        }
        return bencodeDictionary(fields)
    }

    private static func bencodeDictionary(_ fields: [(String, Data)]) -> Data {
        var data = Data("d".utf8)
        for (key, value) in fields.sorted(by: { $0.0 < $1.0 }) {
            data.append(bencodeString(key))
            data.append(value)
        }
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
