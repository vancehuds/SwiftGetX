import CryptoKit
import Foundation
import Testing
@testable import SwiftGetXTorrentCore

@Suite("SwiftGetXTorrentCore")
struct SwiftGetXTorrentCoreTests {
    @Test("parses bencode dictionaries and preserves byte strings")
    func parsesBencodeDictionariesAndByteStrings() throws {
        let value = try BencodeParser(data: Data("d3:bar4:spam3:fooi42ee".utf8)).parse()

        #expect(value["bar"]?.stringValue == "spam")
        #expect(value["foo"]?.integerValue == 42)
        #expect(value.encoded() == Data("d3:bar4:spam3:fooi42ee".utf8))
    }

    @Test("rejects invalid bencode")
    func rejectsInvalidBencode() {
        #expect(throws: BencodeError.invalidInteger(offset: 0)) {
            try BencodeParser(data: Data("i03e".utf8)).parse()
        }
        #expect(throws: BencodeError.invalidDictionaryKey(offset: 9)) {
            try BencodeParser(data: Data("d3:fooi1e3:bari2ee".utf8)).parse()
        }
        #expect(throws: BencodeError.trailingData(offset: 3)) {
            try BencodeParser(data: Data("i1ei2e".utf8)).parse()
        }
    }

    @Test("parses single-file metainfo with canonical info hash")
    func parsesSingleFileMetainfoWithCanonicalInfoHash() throws {
        let info = bencodeDictionary([
            ("length", bencodeInteger(42)),
            ("name", bencodeString("demo.bin")),
            ("piece length", bencodeInteger(16_384)),
            ("pieces", bencodeData(Data("aaaaaaaaaaaaaaaaaaaa".utf8)))
        ])
        let metainfo = try TorrentMetainfo.parse(data: torrentData(
            announce: "http://t/announce",
            info: info
        ))

        #expect(metainfo.name == "demo.bin")
        #expect(metainfo.files == [
            TorrentFileInfo(index: 0, path: "demo.bin", length: 42)
        ])
        #expect(metainfo.totalLength == 42)
        #expect(metainfo.pieceLength == 16_384)
        #expect(metainfo.pieces == [Data("aaaaaaaaaaaaaaaaaaaa".utf8)])
        #expect(metainfo.announce == "http://t/announce")
        #expect(metainfo.infoDictionaryBytes == info)
        #expect(metainfo.infoHashV1Hex == "2c5e446faaaacea19b3f4e1df8d64213aaf88d1c")
        #expect(!metainfo.isPrivate)
    }

    @Test("parses multi-file announce-list and private flag")
    func parsesMultiFileAnnounceListAndPrivateFlag() throws {
        let info = bencodeDictionary([
            ("files", bencodeList([
                bencodeDictionary([
                    ("length", bencodeInteger(10)),
                    ("path", bencodeList([bencodeString("a.txt")]))
                ]),
                bencodeDictionary([
                    ("length", bencodeInteger(20)),
                    ("path", bencodeList([bencodeString("nested"), bencodeString("b.txt")]))
                ])
            ])),
            ("name", bencodeString("album")),
            ("piece length", bencodeInteger(32_768)),
            ("pieces", bencodeData(Data("bbbbbbbbbbbbbbbbbbbb".utf8))),
            ("private", bencodeInteger(1))
        ])
        let metainfo = try TorrentMetainfo.parse(data: torrentData(
            announce: "http://t/announce",
            announceList: [
                ["http://t/announce", "udp://t/announce"],
                ["http://backup/ann"]
            ],
            info: info
        ))

        #expect(metainfo.name == "album")
        #expect(metainfo.files == [
            TorrentFileInfo(index: 0, path: "album/a.txt", length: 10),
            TorrentFileInfo(index: 1, path: "album/nested/b.txt", length: 20)
        ])
        #expect(metainfo.totalLength == 30)
        #expect(metainfo.pieceLength == 32_768)
        #expect(metainfo.announceList == [
            ["http://t/announce", "udp://t/announce"],
            ["http://backup/ann"]
        ])
        #expect(metainfo.isPrivate)
        #expect(metainfo.infoDictionaryBytes == info)
        #expect(metainfo.infoHashV1Hex == sha1Hex(info))
    }

    @Test("rejects invalid torrent metainfo")
    func rejectsInvalidTorrentMetainfo() {
        #expect(throws: TorrentCoreError.invalidMetainfo("Invalid piece hashes.")) {
            try TorrentMetainfo.parse(data: torrentData(
                announce: nil,
                info: bencodeDictionary([
                    ("length", bencodeInteger(1)),
                    ("name", bencodeString("a")),
                    ("piece length", bencodeInteger(16)),
                    ("pieces", bencodeData(Data("abc".utf8)))
                ])
            ))
        }
    }

    @Test("builds safe content layout with offsets and priorities")
    func buildsSafeContentLayoutWithOffsetsAndPriorities() throws {
        let saveDirectory = URL(fileURLWithPath: "/tmp/SwiftGetXDownloads", isDirectory: true)
        let layout = try TorrentContentLayout(
            files: [
                TorrentFileInfo(index: 0, path: "album/a.txt", length: 10),
                TorrentFileInfo(index: 1, path: "album/nested/b.txt", length: 20)
            ],
            saveDirectory: saveDirectory,
            priorities: [1: .high]
        )

        #expect(layout.saveDirectory.path == "/tmp/SwiftGetXDownloads")
        #expect(layout.outputName == "album")
        #expect(layout.contentRoot.path == "/tmp/SwiftGetXDownloads/album")
        #expect(layout.isMultiFile)
        #expect(layout.finalFileURL == nil)
        #expect(layout.totalLength == 30)
        #expect(layout.files.map(\.relativePath) == ["a.txt", "nested/b.txt"])
        #expect(layout.files.map(\.offset) == [0, 10])
        #expect(layout.files.map(\.endOffset) == [10, 30])
        #expect(layout.files.map(\.priority) == [.normal, .high])
        #expect(layout.files[1].fileURL.path == "/tmp/SwiftGetXDownloads/album/nested/b.txt")
        #expect(layout.file(containingGlobalOffset: 10)?.index == 1)
        #expect(layout.file(containingGlobalOffset: 30) == nil)
    }

    @Test("single-file layout keeps save directory as content root")
    func singleFileLayoutKeepsSaveDirectoryAsContentRoot() throws {
        let saveDirectory = URL(fileURLWithPath: "/tmp/SwiftGetXDownloads", isDirectory: true)
        let layout = try TorrentContentLayout(
            files: [
                TorrentFileInfo(index: 0, path: "demo.bin", length: 42)
            ],
            saveDirectory: saveDirectory
        )

        #expect(layout.contentRoot.path == "/tmp/SwiftGetXDownloads")
        #expect(layout.outputName == "demo.bin")
        #expect(!layout.isMultiFile)
        #expect(layout.finalFileURL?.path == "/tmp/SwiftGetXDownloads/demo.bin")
        #expect(layout.files.first?.fileURL.path == "/tmp/SwiftGetXDownloads/demo.bin")
    }

    @Test("multi-file metainfo keeps content root even with one file")
    func multiFileMetainfoKeepsContentRootEvenWithOneFile() throws {
        let info = bencodeDictionary([
            ("files", bencodeList([
                bencodeDictionary([
                    ("length", bencodeInteger(10)),
                    ("path", bencodeList([bencodeString("only.bin")]))
                ])
            ])),
            ("name", bencodeString("bundle")),
            ("piece length", bencodeInteger(16_384)),
            ("pieces", bencodeData(Data("bbbbbbbbbbbbbbbbbbbb".utf8)))
        ])
        let metainfo = try TorrentMetainfo.parse(data: torrentData(announce: nil, info: info))
        let layout = try TorrentContentLayout(
            metainfo: metainfo,
            saveDirectory: URL(fileURLWithPath: "/tmp/SwiftGetXDownloads", isDirectory: true),
            outputName: "renamed-bundle"
        )

        #expect(metainfo.isMultiFile)
        #expect(layout.isMultiFile)
        #expect(layout.outputName == "renamed-bundle")
        #expect(layout.contentRoot.path == "/tmp/SwiftGetXDownloads/renamed-bundle")
        #expect(layout.files.map(\.relativePath) == ["only.bin"])
        #expect(layout.files.first?.fileURL.path == "/tmp/SwiftGetXDownloads/renamed-bundle/only.bin")
    }

    @Test("rejects unsafe torrent content paths")
    func rejectsUnsafeTorrentContentPaths() {
        let saveDirectory = URL(fileURLWithPath: "/tmp/SwiftGetXDownloads", isDirectory: true)

        #expect(throws: TorrentContentLayoutError.invalidPathComponent(fileIndex: 0, component: "..")) {
            try TorrentContentLayout(
                files: [TorrentFileInfo(index: 0, path: "album/../escape.bin", length: 1, pathComponents: ["album", "..", "escape.bin"])],
                saveDirectory: saveDirectory
            )
        }
        #expect(throws: TorrentContentLayoutError.invalidPathComponent(fileIndex: 0, component: "")) {
            try TorrentContentLayout(
                files: [TorrentFileInfo(index: 0, path: "album/", length: 1, pathComponents: ["album", ""])],
                saveDirectory: saveDirectory
            )
        }
        #expect(throws: TorrentContentLayoutError.invalidPathComponent(fileIndex: 0, component: "/etc")) {
            try TorrentContentLayout(
                files: [TorrentFileInfo(index: 0, path: "/etc/passwd", length: 1, pathComponents: ["/etc", "passwd"])],
                saveDirectory: saveDirectory
            )
        }
        #expect(throws: TorrentContentLayoutError.invalidPathComponent(fileIndex: 0, component: "bad\u{202E}name.bin")) {
            try TorrentContentLayout(
                files: [TorrentFileInfo(index: 0, path: "album/bad\u{202E}name.bin", length: 1, pathComponents: ["album", "bad\u{202E}name.bin"])],
                saveDirectory: saveDirectory
            )
        }
        #expect(throws: TorrentContentLayoutError.pathTooLong(fileIndex: 0, path: "very-long-name.bin")) {
            try TorrentContentLayout(
                files: [TorrentFileInfo(index: 0, path: "album/very-long-name.bin", length: 1)],
                saveDirectory: saveDirectory,
                maximumPathBytes: 8
            )
        }
        #expect(throws: TorrentContentLayoutError.duplicatePath(fileIndex: 1, path: "A.txt")) {
            try TorrentContentLayout(
                files: [
                    TorrentFileInfo(index: 0, path: "album/a.txt", length: 1),
                    TorrentFileInfo(index: 1, path: "album/A.txt", length: 1)
                ],
                saveDirectory: saveDirectory
            )
        }
    }

    @Test("torrent metainfo unsafe path components reach layout validation")
    func torrentMetainfoUnsafePathComponentsReachLayoutValidation() throws {
        let info = bencodeDictionary([
            ("files", bencodeList([
                bencodeDictionary([
                    ("length", bencodeInteger(1)),
                    ("path", bencodeList([bencodeString("nested"), bencodeString("")]))
                ])
            ])),
            ("name", bencodeString("album")),
            ("piece length", bencodeInteger(16_384)),
            ("pieces", bencodeData(Data("bbbbbbbbbbbbbbbbbbbb".utf8)))
        ])
        let metainfo = try TorrentMetainfo.parse(data: torrentData(announce: nil, info: info))

        #expect(metainfo.files.first?.pathComponents == ["album", "nested", ""])
        #expect(throws: TorrentContentLayoutError.invalidPathComponent(fileIndex: 0, component: "")) {
            try TorrentContentLayout(
                metainfo: metainfo,
                saveDirectory: URL(fileURLWithPath: "/tmp/SwiftGetXDownloads", isDirectory: true)
            )
        }
    }

    @Test("pure Swift resume state round trips structured progress")
    func pureSwiftResumeStateRoundTripsStructuredProgress() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_234)
        let state = try TorrentCoreResumeState(
            infoHashV1Hex: "2c5e446faaaacea19b3f4e1df8d64213aaf88d1c",
            pieceCount: 4,
            layoutTotalLength: 30,
            completedPieceIndexes: [3, 1, 3],
            partialBlocks: [
                try TorrentResumePartialBlock(pieceIndex: 2, offset: 16_384, length: 4_096),
                try TorrentResumePartialBlock(pieceIndex: 0, offset: 0, length: 16_384, checksumSHA1Hex: "abc")
            ],
            fileChecks: [
                try TorrentResumeFileCheck(fileIndex: 0, path: "a.txt", length: 10, modificationDate: updatedAt, contentFingerprint: "size:10")
            ],
            trackerStates: [
                try TorrentResumeTrackerState(url: "udp://tracker.example:80", tier: 0, failureCount: 2, lastError: "timeout")
            ],
            peerBans: [
                try TorrentResumePeerBan(peerID: "-SGX-", address: "127.0.0.1:6881", reason: "bad piece", bannedUntil: updatedAt)
            ],
            updatedAt: updatedAt
        )
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TorrentCoreResumeState.self, from: encoded)

        #expect(decoded == state)
        #expect(decoded.version == TorrentCoreResumeState.schemaVersion)
        #expect(decoded.completedPieces.completedPieceIndexes == [1, 3])
        #expect(decoded.completedPieces.contains(3))
        #expect(decoded.partialBlocks.map(\.pieceIndex) == [0, 2])
        #expect(decoded.trackerStates.first?.failureCount == 2)
        #expect(decoded.peerBans.first?.reason == "bad piece")
    }

    @Test("resume state validates info hash version and layout")
    func resumeStateValidatesInfoHashVersionAndLayout() throws {
        let saveDirectory = URL(fileURLWithPath: "/tmp/SwiftGetXDownloads", isDirectory: true)
        let info = bencodeDictionary([
            ("files", bencodeList([
                bencodeDictionary([
                    ("length", bencodeInteger(10)),
                    ("path", bencodeList([bencodeString("a.txt")]))
                ]),
                bencodeDictionary([
                    ("length", bencodeInteger(20)),
                    ("path", bencodeList([bencodeString("nested"), bencodeString("b.txt")]))
                ])
            ])),
            ("name", bencodeString("album")),
            ("piece length", bencodeInteger(16_384)),
            ("pieces", bencodeData(Data("bbbbbbbbbbbbbbbbbbbb".utf8)))
        ])
        let metainfo = try TorrentMetainfo.parse(data: torrentData(announce: nil, info: info))
        let layout = try TorrentContentLayout(metainfo: metainfo, saveDirectory: saveDirectory)
        let state = try TorrentCoreResumeState.empty(
            for: metainfo,
            layout: layout,
            updatedAt: Date(timeIntervalSince1970: 1_234)
        )
        let encoded = try state.encodedJSON()
        let decoded = try TorrentCoreResumeState.decodeJSON(
            encoded,
            expectedInfoHashV1Hex: metainfo.infoHashV1Hex,
            expectedLayout: layout
        )

        #expect(decoded.fileChecks.map(\.path) == ["a.txt", "nested/b.txt"])
        #expect(decoded.layoutTotalLength == 30)
        #expect(throws: TorrentResumeStateError.invalidInfoHash(metainfo.infoHashV1Hex)) {
            try decoded.validate(expectedInfoHashV1Hex: "0000000000000000000000000000000000000000")
        }
        #expect(throws: TorrentResumeStateError.unsupportedVersion(2)) {
            try JSONDecoder().decode(
                TorrentCoreResumeState.self,
                from: Data(
                    """
                    {
                      "version": 2,
                      "infoHashV1Hex": "2c5e446faaaacea19b3f4e1df8d64213aaf88d1c",
                      "layoutTotalLength": 30,
                      "completedPieces": {
                        "pieceCount": 4,
                        "completedPieceIndexes": []
                      },
                      "partialBlocks": [],
                      "fileChecks": [],
                      "trackerStates": [],
                      "peerBans": [],
                      "updatedAt": 1234
                    }
                    """.utf8
                )
            )
        }
    }

    @Test("resume state rejects invalid piece and block references")
    func resumeStateRejectsInvalidPieceAndBlockReferences() throws {
        #expect(throws: TorrentResumeStateError.invalidPieceIndex(4)) {
            try TorrentCoreResumeState(
                infoHashV1Hex: "2c5e446faaaacea19b3f4e1df8d64213aaf88d1c",
                pieceCount: 4,
                layoutTotalLength: 30,
                completedPieceIndexes: [4]
            )
        }
        #expect(throws: TorrentResumeStateError.invalidPieceIndex(4)) {
            try TorrentCoreResumeState(
                infoHashV1Hex: "2c5e446faaaacea19b3f4e1df8d64213aaf88d1c",
                pieceCount: 4,
                layoutTotalLength: 30,
                partialBlocks: [
                    try TorrentResumePartialBlock(pieceIndex: 4, offset: 0, length: 1)
                ]
            )
        }
        #expect(throws: TorrentResumeStateError.duplicatePartialBlock(pieceIndex: 0, offset: 0)) {
            try TorrentCoreResumeState(
                infoHashV1Hex: "2c5e446faaaacea19b3f4e1df8d64213aaf88d1c",
                pieceCount: 4,
                layoutTotalLength: 30,
                partialBlocks: [
                    try TorrentResumePartialBlock(pieceIndex: 0, offset: 0, length: 1),
                    try TorrentResumePartialBlock(pieceIndex: 0, offset: 0, length: 2)
                ]
            )
        }
        #expect(throws: TorrentResumeStateError.invalidBlockRange(pieceIndex: 0)) {
            try TorrentResumePartialBlock(pieceIndex: 0, offset: 0, length: 0)
        }
        #expect(throws: TorrentResumeStateError.duplicatePartialBlock(pieceIndex: 0, offset: 0)) {
            try JSONDecoder().decode(
                TorrentCoreResumeState.self,
                from: Data(
                    """
                    {
                      "version": 1,
                      "infoHashV1Hex": "2c5e446faaaacea19b3f4e1df8d64213aaf88d1c",
                      "layoutTotalLength": 30,
                      "completedPieces": {
                        "pieceCount": 4,
                        "completedPieceIndexes": [1, 3]
                      },
                      "partialBlocks": [
                        { "pieceIndex": 0, "offset": 0, "length": 1 },
                        { "pieceIndex": 0, "offset": 0, "length": 2 }
                      ],
                      "fileChecks": [],
                      "trackerStates": [],
                      "peerBans": [],
                      "updatedAt": 1234
                    }
                    """.utf8
                )
            )
        }
    }

    @Test("parses magnet hex btih display name trackers and length")
    func parsesMagnetHexBtihDisplayNameTrackersAndLength() throws {
        let magnet = try MagnetURI.parse(
            "magnet:?xt=urn:btih:2c5e446faaaacea19b3f4e1df8d64213aaf88d1c&dn=Demo%20File&tr=http%3A%2F%2Ft%2Fannounce&tr=udp%3A%2F%2Ft%2Fannounce&xl=42"
        )

        #expect(magnet.infoHashV1Hex == "2c5e446faaaacea19b3f4e1df8d64213aaf88d1c")
        #expect(magnet.displayName == "Demo File")
        #expect(magnet.trackers == ["http://t/announce", "udp://t/announce"])
        #expect(magnet.exactLength == 42)
    }

    @Test("parses magnet base32 btih")
    func parsesMagnetBase32Btih() throws {
        let magnet = try MagnetURI.parse("magnet:?xt=urn:btih:FRPEI35KVLHKDGZ7JYO7RVSCCOVPRDI4")

        #expect(magnet.infoHashV1Hex == "2c5e446faaaacea19b3f4e1df8d64213aaf88d1c")
    }

    @Test("rejects invalid magnet inputs")
    func rejectsInvalidMagnetInputs() {
        #expect(throws: TorrentCoreError.invalidMagnet("Magnet URI is missing a btih topic.")) {
            try MagnetURI.parse("magnet:?dn=NoHash")
        }
        #expect(throws: TorrentCoreError.invalidMagnet("Magnet btih hash must be 40-character hex or 32-character base32.")) {
            try MagnetURI.parse("magnet:?xt=urn:btih:not-a-valid-hash")
        }
        #expect(throws: TorrentCoreError.invalidMagnet("Magnet exact length must be an integer.")) {
            try MagnetURI.parse("magnet:?xt=urn:btih:2c5e446faaaacea19b3f4e1df8d64213aaf88d1c&xl=unknown")
        }
        #expect(throws: TorrentCoreError.invalidMagnet("Magnet exact length cannot be negative.")) {
            try MagnetURI.parse("magnet:?xt=urn:btih:2c5e446faaaacea19b3f4e1df8d64213aaf88d1c&xl=-1")
        }
    }

    private func torrentData(announce: String?, announceList: [[String]] = [], info: Data) -> Data {
        var fields = [(String, Data)]()
        if let announce {
            fields.append(("announce", bencodeString(announce)))
        }
        if !announceList.isEmpty {
            fields.append(("announce-list", bencodeList(
                announceList.map { tier in
                    bencodeList(tier.map { bencodeString($0) })
                }
            )))
        }
        fields.append(("info", info))
        return bencodeDictionary(fields)
    }

    private func bencodeDictionary(_ fields: [(String, Data)]) -> Data {
        var data = Data("d".utf8)
        for (key, value) in fields.sorted(by: { Array($0.0.utf8).lexicographicallyPrecedes(Array($1.0.utf8)) }) {
            data.append(bencodeString(key))
            data.append(value)
        }
        data.append(UInt8(ascii: "e"))
        return data
    }

    private func bencodeList(_ values: [Data]) -> Data {
        var data = Data("l".utf8)
        for value in values {
            data.append(value)
        }
        data.append(UInt8(ascii: "e"))
        return data
    }

    private func bencodeString(_ value: String) -> Data {
        bencodeData(Data(value.utf8))
    }

    private func bencodeData(_ value: Data) -> Data {
        var data = Data("\(value.count):".utf8)
        data.append(value)
        return data
    }

    private func bencodeInteger(_ value: Int64) -> Data {
        Data("i\(value)e".utf8)
    }

    private func sha1Hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
