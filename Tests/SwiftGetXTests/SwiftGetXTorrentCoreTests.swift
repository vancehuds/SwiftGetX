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

    @Test("enforces bencode parser resource limits")
    func enforcesBencodeParserResourceLimits() {
        #expect(throws: BencodeError.inputLimitExceeded(offset: 2)) {
            try BencodeParser(
                data: Data("i1e".utf8),
                limits: BencodeLimits(maximumInputBytes: 2)
            ).parse()
        }
        #expect(throws: BencodeError.nestingLimitExceeded(offset: 2)) {
            try BencodeParser(
                data: Data("lli1eee".utf8),
                limits: BencodeLimits(maximumDepth: 1)
            ).parse()
        }
        #expect(throws: BencodeError.collectionLimitExceeded(offset: 4)) {
            try BencodeParser(
                data: Data("li1ei2ee".utf8),
                limits: BencodeLimits(maximumCollectionElements: 1)
            ).parse()
        }
        #expect(throws: BencodeError.byteStringLimitExceeded(offset: 0)) {
            try BencodeParser(
                data: Data("4:spam".utf8),
                limits: BencodeLimits(maximumByteStringLength: 3)
            ).parse()
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

    @Test("rejects torrent metainfo with mismatched piece count")
    func rejectsTorrentMetainfoWithMismatchedPieceCount() {
        #expect(throws: TorrentCoreError.invalidMetainfo("Piece hash count does not match torrent length.")) {
            try TorrentMetainfo.parse(data: torrentData(
                announce: nil,
                info: bencodeDictionary([
                    ("length", bencodeInteger(16_385)),
                    ("name", bencodeString("two-pieces.bin")),
                    ("piece length", bencodeInteger(16_384)),
                    ("pieces", bencodeData(Data("aaaaaaaaaaaaaaaaaaaa".utf8)))
                ])
            ))
        }
    }

    @Test("torrent metainfo parse enforces bencode limits")
    func torrentMetainfoParseEnforcesBencodeLimits() {
        #expect(throws: TorrentCoreError.invalidBencode(.inputLimitExceeded(offset: 8))) {
            try TorrentMetainfo.parse(
                data: torrentData(
                    announce: nil,
                    info: bencodeDictionary([
                        ("length", bencodeInteger(42)),
                        ("name", bencodeString("demo.bin")),
                        ("piece length", bencodeInteger(16_384)),
                        ("pieces", bencodeData(Data("aaaaaaaaaaaaaaaaaaaa".utf8)))
                    ])
                ),
                limits: BencodeLimits(maximumInputBytes: 8)
            )
        }
        #expect(throws: TorrentCoreError.invalidBencode(.byteStringLimitExceeded(offset: 1))) {
            try TorrentMetainfo.parse(
                data: torrentData(
                    announce: nil,
                    info: bencodeDictionary([
                        ("length", bencodeInteger(42)),
                        ("name", bencodeString("demo.bin")),
                        ("piece length", bencodeInteger(16_384)),
                        ("pieces", bencodeData(Data("aaaaaaaaaaaaaaaaaaaa".utf8)))
                    ])
                ),
                limits: BencodeLimits(maximumByteStringLength: 3)
            )
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

    @Test("torrent layout keeps generated paths inside save directory")
    func torrentLayoutKeepsGeneratedPathsInsideSaveDirectory() throws {
        let saveDirectory = URL(fileURLWithPath: "/tmp/SwiftGetXDownloads", isDirectory: true)
        let layout = try TorrentContentLayout(
            files: [
                TorrentFileInfo(index: 0, path: "album/a.txt", length: 1),
                TorrentFileInfo(index: 1, path: "album/nested/b.txt", length: 1)
            ],
            saveDirectory: saveDirectory,
            outputName: "renamed-album"
        )

        #expect(layout.contentRoot.path == "/tmp/SwiftGetXDownloads/renamed-album")
        #expect(layout.files.allSatisfy { $0.fileURL.path.hasPrefix("/tmp/SwiftGetXDownloads/renamed-album/") })
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
        #expect(throws: TorrentContentLayoutError.pathTooLong(
            fileIndex: 0,
            path: "/tmp/SwiftGetXDownloads/very-long-parent/album/a.txt"
        )) {
            try TorrentContentLayout(
                files: [TorrentFileInfo(index: 0, path: "album/a.txt", length: 1)],
                saveDirectory: saveDirectory.appendingPathComponent("very-long-parent", isDirectory: true),
                maximumPathBytes: 32
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

    @Test("parses HTTP tracker compact and non-compact peers")
    func parsesHTTPTrackerPeers() throws {
        let compact = Data([127, 0, 0, 1, 0x1a, 0xe1])
        let compactResponse = try TorrentHTTPTrackerResponse.parse(data: bencodeDictionary([
            ("complete", bencodeInteger(3)),
            ("downloaded", bencodeInteger(9)),
            ("incomplete", bencodeInteger(4)),
            ("interval", bencodeInteger(120)),
            ("min interval", bencodeInteger(60)),
            ("peers", bencodeData(compact)),
            ("warning message", bencodeString("slow"))
        ]))

        #expect(compactResponse.announceResult.peers == [
            TorrentPeerEndpoint(host: "127.0.0.1", port: 6881)
        ])
        #expect(compactResponse.announceResult.seedCount == 3)
        #expect(compactResponse.announceResult.leecherCount == 4)
        #expect(compactResponse.announceResult.downloadedCount == 9)
        #expect(compactResponse.announceResult.warningMessage == "slow")

        let peerID = Data("-SGX0001-ABCDEFGHIJK".utf8)
        let listResponse = try TorrentHTTPTrackerResponse.parse(data: bencodeDictionary([
            ("interval", bencodeInteger(90)),
            ("peers", bencodeList([
                bencodeDictionary([
                    ("ip", bencodeString("192.0.2.10")),
                    ("peer id", bencodeData(peerID)),
                    ("port", bencodeInteger(51413))
                ])
            ]))
        ]))

        #expect(listResponse.announceResult.peers == [
            TorrentPeerEndpoint(
                host: "192.0.2.10",
                port: 51413,
                peerID: peerID.map { String(format: "%02x", $0) }.joined()
            )
        ])
    }

    @Test("builds HTTP tracker announce requests")
    func buildsHTTPTrackerAnnounceRequests() throws {
        let peerID = Data("-SGX0001-12345678901".utf8)
        let request = try TorrentTrackerAnnounceRequest(
            trackerURL: URL(string: "http://tracker.example/announce?existing=1")!,
            infoHash: Data((0..<20).map(UInt8.init)),
            peerID: peerID,
            port: 6881,
            uploaded: 2,
            downloaded: 3,
            left: 4,
            event: .started,
            compact: true,
            numWant: 25,
            key: 7
        )
        let url = try #require(request.httpURLRequest().url?.absoluteString)

        #expect(url.contains("existing=1"))
        #expect(url.contains("info_hash=%00%01%02%03%04%05%06%07%08%09%0A%0B%0C%0D%0E%0F%10%11%12%13"))
        #expect(url.contains("peer_id=-SGX0001-12345678901"))
        #expect(url.contains("port=6881"))
        #expect(url.contains("event=started"))
        #expect(url.contains("key=7"))

        for event in [TorrentTrackerEvent.none, .started, .completed, .stopped] {
            let eventRequest = try TorrentTrackerAnnounceRequest(
                trackerURL: URL(string: "http://tracker.example/announce")!,
                infoHash: Data((0..<20).map(UInt8.init)),
                peerID: peerID,
                left: 4,
                event: event
            )
            let eventURL = try #require(eventRequest.httpURLRequest().url?.absoluteString)
            if event == .none {
                #expect(!eventURL.contains("event="))
            } else {
                #expect(eventURL.contains("event=\(event.rawValue)"))
            }
        }
    }

    @Test("announces through mocked HTTP and UDP tracker transports")
    func announcesThroughMockedTrackerTransports() async throws {
        let httpTransport = MockHTTPTrackerTransport(response: bencodeDictionary([
            ("complete", bencodeInteger(1)),
            ("incomplete", bencodeInteger(2)),
            ("interval", bencodeInteger(30)),
            ("peers", bencodeData(Data([10, 0, 0, 2, 0x1a, 0xe1])))
        ]))
        let udpTransport = MockUDPTrackerTransport()
        let client = TorrentTrackerClient(
            httpTransport: httpTransport,
            udpTransport: udpTransport,
            retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .seconds(1)),
            randomSource: TorrentTrackerRandomSource(
                nextTransactionID: SequentialInt32Source([10, 11]).next,
                nextKey: { 0 }
            )
        )
        let httpRequest = try TorrentTrackerAnnounceRequest(
            trackerURL: URL(string: "http://tracker.example/announce")!,
            infoHash: Data((0..<20).map(UInt8.init)),
            peerID: Data("-SGX0001-12345678901".utf8),
            left: 42
        )
        let httpResult = try await client.announce(httpRequest)

        #expect(httpResult.peers == [TorrentPeerEndpoint(host: "10.0.0.2", port: 6881)])
        #expect(await httpTransport.requests.count == 1)

        let udpRequest = try TorrentTrackerAnnounceRequest(
            trackerURL: URL(string: "udp://tracker.example:80/announce")!,
            infoHash: Data((0..<20).map(UInt8.init)),
            peerID: Data("-SGX0001-12345678901".utf8),
            left: 42
        )
        let udpResult = try await client.announce(udpRequest)

        #expect(udpResult.peers == [TorrentPeerEndpoint(host: "203.0.113.9", port: 51413)])
        #expect(await udpTransport.requests.count == 2)
    }

    @Test("retries HTTP tracker failures")
    func retriesHTTPTrackerFailures() async throws {
        let httpTransport = RetryingHTTPTrackerTransport(response: bencodeDictionary([
            ("interval", bencodeInteger(45)),
            ("peers", bencodeData(Data([192, 0, 2, 20, 0x1a, 0xe1])))
        ]))
        let client = TorrentTrackerClient(
            httpTransport: httpTransport,
            retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 1, timeout: .milliseconds(10))
        )
        let request = try TorrentTrackerAnnounceRequest(
            trackerURL: URL(string: "http://tracker.example/announce")!,
            infoHash: Data((0..<20).map(UInt8.init)),
            peerID: Data("-SGX0001-12345678901".utf8),
            left: 42
        )

        let result = try await client.announce(request)

        #expect(result.interval == 45)
        #expect(result.peers == [TorrentPeerEndpoint(host: "192.0.2.20", port: 6881)])
        #expect(await httpTransport.requests.count == 2)
    }

    @Test("validates UDP tracker transaction ids and retries timeouts")
    func validatesUDPTrackerTransactionIDsAndRetriesTimeouts() async throws {
        var connectMismatch = Data()
        connectMismatch.appendUInt32(0)
        connectMismatch.appendInt32(99)
        connectMismatch.appendInt64(0x0102030405060708)
        #expect(throws: TorrentTrackerError.transactionIDMismatch(expected: 10, actual: 99)) {
            try TorrentUDPTrackerPacket.parseConnectResponse(connectMismatch, expectedTransactionID: 10)
        }

        var announceMismatch = Data()
        announceMismatch.appendUInt32(1)
        announceMismatch.appendInt32(100)
        announceMismatch.appendInt32(60)
        announceMismatch.appendInt32(2)
        announceMismatch.appendInt32(1)
        #expect(throws: TorrentTrackerError.transactionIDMismatch(expected: 11, actual: 100)) {
            try TorrentUDPTrackerPacket.parseAnnounceResponse(announceMismatch, expectedTransactionID: 11)
        }

        let udpTransport = RetryingUDPTrackerTransport()
        let client = TorrentTrackerClient(
            udpTransport: udpTransport,
            retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 1, timeout: .milliseconds(10)),
            randomSource: TorrentTrackerRandomSource(
                nextTransactionID: SequentialInt32Source([20, 21, 22]).next,
                nextKey: { 0 }
            )
        )
        let request = try TorrentTrackerAnnounceRequest(
            trackerURL: URL(string: "udp://tracker.example:80/announce")!,
            infoHash: Data((0..<20).map(UInt8.init)),
            peerID: Data("-SGX0001-12345678901".utf8),
            left: 42
        )
        let result = try await client.announce(request)

        #expect(result.peers == [TorrentPeerEndpoint(host: "198.51.100.10", port: 6000)])
        #expect(await udpTransport.requests.count == 3)
    }

    @Test("schedules tracker tiers and retry backoff")
    func schedulesTrackerTiersAndRetryBackoff() {
        let start = Date(timeIntervalSince1970: 1_000)
        var scheduler = TorrentTrackerScheduler(trackers: [
            TorrentTrackerDescriptor(url: "http://primary/announce", tier: 0),
            TorrentTrackerDescriptor(url: "http://backup/announce", tier: 1)
        ], baseBackoffSeconds: 5)

        #expect(scheduler.nextCandidate(now: start)?.url == "http://primary/announce")
        scheduler.recordFailure(
            url: "http://primary/announce",
            error: TorrentTrackerError.timeout,
            now: start
        )
        #expect(scheduler.nextCandidate(now: start)?.url == "http://backup/announce")
        #expect(scheduler.states.first?.failureCount == 1)
        #expect(scheduler.states.first?.nextAnnounceDate == start.addingTimeInterval(5))
        scheduler.recordSuccess(
            url: "http://backup/announce",
            result: TorrentTrackerAnnounceResult(
                interval: 30,
                minInterval: 10,
                peers: [TorrentPeerEndpoint(host: "192.0.2.1", port: 6881)],
                seedCount: 11,
                leecherCount: 12,
                downloadedCount: 13
            ),
            now: start
        )
        let backupState = scheduler.states[1]
        #expect(backupState.status == .working)
        #expect(backupState.failureCount == 0)
        #expect(backupState.seedCount == 11)
        #expect(backupState.leecherCount == 12)
        #expect(backupState.downloadedCount == 13)
        #expect(backupState.nextAnnounceDate == start.addingTimeInterval(30))
        #expect(scheduler.nextCandidate(now: start.addingTimeInterval(5))?.url == "http://primary/announce")
    }

    @Test("parses tracker scrape responses")
    func parsesTrackerScrapeResponses() throws {
        #expect(TorrentTrackerScrape.scrapeURL(from: URL(string: "http://tracker.example/announce")!)?.absoluteString == "http://tracker.example/scrape")

        let infoHash = Data((0..<20).map(UInt8.init))
        let result = try TorrentTrackerScrape.parse(
            data: bencodeDictionary([
                ("files", bencodeRawDictionary([
                    (infoHash, bencodeDictionary([
                        ("complete", bencodeInteger(7)),
                        ("downloaded", bencodeInteger(8)),
                        ("incomplete", bencodeInteger(9))
                    ]))
                ]))
            ]),
            infoHash: infoHash
        )

        #expect(result == TorrentTrackerScrapeResult(complete: 7, downloaded: 8, incomplete: 9))
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
        bencodeRawDictionary(fields.map { (Data($0.0.utf8), $0.1) })
    }

    private func bencodeRawDictionary(_ fields: [(Data, Data)]) -> Data {
        var data = Data("d".utf8)
        for (key, value) in fields.sorted(by: { [UInt8]($0.0).lexicographicallyPrecedes([UInt8]($1.0)) }) {
            data.append(bencodeData(key))
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

    @Test("DHT routing table handles node additions and XOR distance lookups")
    func dhtRoutingTableHandlesNodesAndClosestLookups() throws {
        let nodeID1 = Data(repeating: 1, count: 20)
        let nodeID2 = Data(repeating: 2, count: 20)
        
        let node1 = try TorrentDHTNode(id: nodeID1, host: "127.0.0.1", port: 6881)
        let node2 = try TorrentDHTNode(id: nodeID2, host: "127.0.0.2", port: 6882)
        
        var routingTable = TorrentDHTRoutingTable()
        routingTable.add(node1)
        routingTable.add(node2)
        
        #expect(routingTable.nodes.count == 2)
        #expect(routingTable.nodes.contains(where: { $0.address == node1.address }))
        
        let target = Data(repeating: 1, count: 20)
        let closest = routingTable.closestNodes(to: target, limit: 1)
        #expect(closest.first?.id == nodeID1)
        
        routingTable.recordFailure(for: node1)
        #expect(routingTable.nodes.first(where: { $0.address == node1.address })?.failureCount == 1)
    }

    @Test("DHT KRPC message query and response serialization")
    func dhtKRPCMessageEncodeAndDecode() throws {
        let transactionID = Data([0xaa, 0xbb])
        let nodeID = Data(repeating: 1, count: 20)
        let target = Data(repeating: 2, count: 20)
        
        let pingReq = try TorrentDHTKRPC.pingRequest(transactionID: transactionID, nodeID: nodeID)
        #expect(!pingReq.isEmpty)
        
        let findNodeReq = try TorrentDHTKRPC.findNodeRequest(transactionID: transactionID, nodeID: nodeID, target: target)
        #expect(!findNodeReq.isEmpty)
        
        let getPeersReq = try TorrentDHTKRPC.getPeersRequest(transactionID: transactionID, nodeID: nodeID, infoHash: target)
        #expect(!getPeersReq.isEmpty)
        
        let announcePeerReq = try TorrentDHTKRPC.announcePeerRequest(
            transactionID: transactionID,
            nodeID: nodeID,
            infoHash: target,
            port: 6881,
            token: Data([1, 2, 3])
        )
        #expect(!announcePeerReq.isEmpty)
        
        // Test parsing response
        let peer = TorrentPeerEndpoint(host: "127.0.0.1", port: 6881)
        let node = try TorrentDHTNode(id: nodeID, host: "127.0.0.2", port: 6882)
        let responseData = try TorrentDHTKRPC.response(
            transactionID: transactionID,
            nodeID: nodeID,
            nodes: [node],
            peers: [peer],
            token: Data([4, 5])
        )
        
        let parsed = try TorrentDHTKRPC.parseResponse(responseData, expectedTransactionID: transactionID)
        #expect(parsed.transactionID == transactionID)
        #expect(parsed.token == Data([4, 5]))
        #expect(parsed.peers.count == 1)
        #expect(parsed.peers.first?.host == "127.0.0.1")
        #expect(parsed.nodes.count == 1)
        #expect(parsed.nodes.first?.host == "127.0.0.2")
    }

    @Test("DHT node store load and save persistence")
    func dhtNodeStorePersistsNodes() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("dht-nodes-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        
        let node = try TorrentDHTNode(id: Data(repeating: 3, count: 20), host: "10.0.0.1", port: 6883)
        let store = TorrentDHTNodeStore(url: fileURL)
        
        try store.save([node])
        let loaded = try store.load()
        
        #expect(loaded.count == 1)
        #expect(loaded.first?.host == "10.0.0.1")
        #expect(loaded.first?.port == 6883)
    }

    @Test("DHT client bootstrap and peer discovery lookup")
    func dhtClientPerformsBootstrapAndDiscovery() async throws {
        let transport = MockDHTTransport2()
        let client = try TorrentDHTClient(
            localNodeID: Data(repeating: 4, count: 20),
            timeout: .milliseconds(50),
            transport: transport,
            transactionIDSource: { Data([1, 2]) }
        )
        
        let infoHash = Data(repeating: 5, count: 20)
        let bootstrapNode = try TorrentDHTNode(id: Data(repeating: 9, count: 20), host: "127.0.0.1", port: 6881)
        
        let nodeID = Data(repeating: 9, count: 20)
        let findNodeResp = try TorrentDHTKRPC.response(
            transactionID: Data([1, 2]),
            nodeID: nodeID,
            nodes: [try TorrentDHTNode(id: Data(repeating: 8, count: 20), host: "127.0.0.2", port: 6882)]
        )
        let getPeersResp = try TorrentDHTKRPC.response(
            transactionID: Data([1, 2]),
            nodeID: nodeID,
            peers: [TorrentPeerEndpoint(host: "192.168.1.5", port: 6889)],
            token: Data([0xaa, 0xbb])
        )
        
        await transport.setResponse(forQueryType: "find_node", data: findNodeResp)
        await transport.setResponse(forQueryType: "get_peers", data: getPeersResp)
        
        let result = try await client.discoverPeers(
            infoHash: infoHash,
            bootstrapNodes: [bootstrapNode],
            announcePort: 6881,
            maxPeers: 1
        )
        
        #expect(result.peers.count >= 1)
        #expect(result.peers.first?.endpoint.host == "192.168.1.5")
        #expect(result.peers.first?.source == .dht)
    }

    @Test("PEX message parsing matches added peers")
    func pexMessageParsesAddedPeers() throws {
        let addedCompact = Data([127, 0, 0, 1, 0x1a, 0xe1])
        let pexPayload = BencodeValue.dictionary([
            Data("added".utf8): .data(addedCompact)
        ]).encoded()
        
        let peers = try TorrentPeerExchangeMessage.parse(pexPayload)
        #expect(peers.count == 1)
        #expect(peers.first?.endpoint.host == "127.0.0.1")
        #expect(peers.first?.endpoint.port == 6881)
        #expect(peers.first?.source == .pex)
    }

    @Test("LSD search message formatting and parsing")
    func lsdAnnounceAndParsing() throws {
        let infoHash = Data(repeating: 7, count: 20)
        let messageData = try TorrentLocalServiceDiscovery.searchMessage(infoHash: infoHash, port: 6881)
        
        let parsed = try TorrentLocalServiceDiscovery.parseSearchMessage(
            messageData,
            sourceHost: "192.168.1.10",
            expectedInfoHash: infoHash
        )
        
        #expect(parsed != nil)
        #expect(parsed?.endpoint.host == "192.168.1.10")
        #expect(parsed?.endpoint.port == 6881)
        #expect(parsed?.source == .lsd)
        
        let mismatched = try TorrentLocalServiceDiscovery.parseSearchMessage(
            messageData,
            sourceHost: "192.168.1.10",
            expectedInfoHash: Data(repeating: 8, count: 20)
        )
        #expect(mismatched == nil)
    }

    private func sha1Hex(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private actor MockHTTPTrackerTransport: TorrentHTTPTrackerTransport {
    private(set) var requests = [URLRequest]()
    private let response: Data

    init(response: Data) {
        self.response = response
    }

    func load(_ request: URLRequest) async throws -> Data {
        requests.append(request)
        return response
    }
}

private actor RetryingHTTPTrackerTransport: TorrentHTTPTrackerTransport {
    private(set) var requests = [URLRequest]()
    private let response: Data

    init(response: Data) {
        self.response = response
    }

    func load(_ request: URLRequest) async throws -> Data {
        requests.append(request)
        if requests.count == 1 {
            throw TorrentTrackerError.timeout
        }
        return response
    }
}

private actor MockUDPTrackerTransport: TorrentUDPTrackerTransport {
    private(set) var requests = [Data]()

    func send(_ data: Data, to url: URL, timeout: Duration) async throws -> Data {
        requests.append(data)
        if requests.count == 1 {
            var response = Data()
            response.appendUInt32(0)
            response.appendInt32(10)
            response.appendInt64(0x0102030405060708)
            return response
        }
        var response = Data()
        response.appendUInt32(1)
        response.appendInt32(11)
        response.appendInt32(60)
        response.appendInt32(2)
        response.appendInt32(1)
        response.append(contentsOf: [203, 0, 113, 9, 0xc8, 0xd5])
        return response
    }
}

private actor RetryingUDPTrackerTransport: TorrentUDPTrackerTransport {
    private(set) var requests = [Data]()

    func send(_ data: Data, to url: URL, timeout: Duration) async throws -> Data {
        requests.append(data)
        switch requests.count {
        case 1:
            throw TorrentTrackerError.timeout
        case 2:
            var response = Data()
            response.appendUInt32(0)
            response.appendInt32(21)
            response.appendInt64(0x0102030405060708)
            return response
        default:
            var response = Data()
            response.appendUInt32(1)
            response.appendInt32(22)
            response.appendInt32(60)
            response.appendInt32(2)
            response.appendInt32(1)
            response.append(contentsOf: [198, 51, 100, 10, 0x17, 0x70])
            return response
        }
    }
}

private final class SequentialInt32Source: @unchecked Sendable {
    private let values: [Int32]
    private var index = 0
    private let lock = NSLock()

    init(_ values: [Int32]) {
        self.values = values
    }

    func next() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }
}

private extension Data {
    mutating func appendUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendInt32(_ value: Int32) {
        appendUInt32(UInt32(bitPattern: value))
    }

    mutating func appendInt64(_ value: Int64) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }
}

private actor MockDHTTransport2: TorrentDHTTransport {
    private var responsesByQuery = [String: Data]()
    
    func setResponse(forQueryType type: String, data: Data) {
        responsesByQuery[type] = data
    }
    
    func send(_ data: Data, to node: TorrentDHTNode, timeout: Duration) async throws -> Data {
        if let value = try? BencodeParser(data: data).parse(),
           case .dictionary(let dict) = value,
           let q = dict[Data("q".utf8)]?.stringValue,
           let response = responsesByQuery[q] {
            return response
        }
        throw TorrentDHTError.timeout
    }
}
