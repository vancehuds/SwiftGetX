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
