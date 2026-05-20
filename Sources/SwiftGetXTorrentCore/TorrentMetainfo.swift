import CryptoKit
import Foundation

public enum TorrentCoreError: Error, Equatable, Sendable, LocalizedError {
    case invalidBencode(BencodeError)
    case invalidMetainfo(String)
    case invalidMagnet(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBencode(let error):
            error.localizedDescription
        case .invalidMetainfo(let message):
            message
        case .invalidMagnet(let message):
            message
        }
    }
}

public struct TorrentFileInfo: Codable, Equatable, Sendable {
    public var index: Int
    public var path: String
    public var pathComponents: [String]
    public var length: Int64

    public init(index: Int, path: String, length: Int64, pathComponents: [String]? = nil) {
        self.index = index
        self.path = path
        self.pathComponents = pathComponents ?? path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        self.length = length
    }
}

public struct TorrentMetainfo: Equatable, Sendable {
    public var name: String
    public var files: [TorrentFileInfo]
    public var pieceLength: Int64
    public var pieces: [Data]
    public var announce: String?
    public var announceList: [[String]]
    public var isPrivate: Bool
    public var isMultiFile: Bool
    public var infoDictionaryBytes: Data
    public var infoHashV1: Data

    public var totalLength: Int64 {
        files.reduce(0) { $0 + $1.length }
    }

    public var isSingleFile: Bool {
        !isMultiFile
    }

    public var infoHashV1Hex: String {
        infoHashV1.map { String(format: "%02x", $0) }.joined()
    }

    public static func parse(data: Data) throws -> TorrentMetainfo {
        let rootValue: BencodeValue
        do {
            rootValue = try BencodeParser(data: data).parse()
        } catch let error as BencodeError {
            throw TorrentCoreError.invalidBencode(error)
        }

        guard case .dictionary(let root) = rootValue,
              let infoValue = root[stringKey("info")],
              case .dictionary(let info) = infoValue
        else {
            throw TorrentCoreError.invalidMetainfo("Missing torrent info dictionary.")
        }

        let infoDictionaryBytes = try canonicalInfoBytes(from: data)
        let hash = Insecure.SHA1.hash(data: infoDictionaryBytes)
        let name = string(in: info, preferredKey: "name.utf-8", fallbackKey: "name") ?? "torrent"
        let pieceLength = integer(in: info, key: "piece length")
        guard let pieceLength, pieceLength > 0 else {
            throw TorrentCoreError.invalidMetainfo("Missing or invalid piece length.")
        }
        let pieces = try pieces(from: info[stringKey("pieces")])

        let parsedFiles = try files(from: info, rootName: name)

        return TorrentMetainfo(
            name: name,
            files: parsedFiles.files,
            pieceLength: pieceLength,
            pieces: pieces,
            announce: root[stringKey("announce")]?.stringValue,
            announceList: announceList(from: root[stringKey("announce-list")]),
            isPrivate: integer(in: info, key: "private") == 1,
            isMultiFile: parsedFiles.isMultiFile,
            infoDictionaryBytes: infoDictionaryBytes,
            infoHashV1: Data(hash)
        )
    }

    public static func parse(url: URL) throws -> TorrentMetainfo {
        try parse(data: Data(contentsOf: url))
    }

    private static func files(from info: [Data: BencodeValue], rootName: String) throws -> (
        files: [TorrentFileInfo],
        isMultiFile: Bool
    ) {
        if case .list(let fileValues)? = info[stringKey("files")] {
            let files = try fileValues.enumerated().map { offset, value -> TorrentFileInfo in
                guard case .dictionary(let fileDictionary) = value,
                      let length = integer(in: fileDictionary, key: "length"),
                      length >= 0
                else {
                    throw TorrentCoreError.invalidMetainfo("Invalid multi-file entry.")
                }

                let components = pathComponents(in: fileDictionary, preferredKey: "path.utf-8", fallbackKey: "path")
                guard let components, !components.isEmpty else {
                    throw TorrentCoreError.invalidMetainfo("Missing multi-file path.")
                }

                return TorrentFileInfo(
                    index: offset,
                    path: ([rootName] + components).joined(separator: "/"),
                    length: length,
                    pathComponents: [rootName] + components
                )
            }
            guard !files.isEmpty else {
                throw TorrentCoreError.invalidMetainfo("Torrent contains no files.")
            }
            return (files, true)
        }

        guard let length = integer(in: info, key: "length"), length >= 0 else {
            throw TorrentCoreError.invalidMetainfo("Missing single-file length.")
        }
        return ([TorrentFileInfo(index: 0, path: rootName, length: length, pathComponents: [rootName])], false)
    }

    private static func pieces(from value: BencodeValue?) throws -> [Data] {
        guard case .data(let data)? = value,
              !data.isEmpty,
              data.count.isMultiple(of: 20)
        else {
            throw TorrentCoreError.invalidMetainfo("Invalid piece hashes.")
        }

        return stride(from: 0, to: data.count, by: 20).map { offset in
            data.subdata(in: offset..<(offset + 20))
        }
    }

    private static func announceList(from value: BencodeValue?) -> [[String]] {
        guard case .list(let tiers)? = value else { return [] }
        return tiers.compactMap { tierValue in
            guard case .list(let trackerValues) = tierValue else { return nil }
            let trackers = trackerValues.compactMap(\.stringValue).filter { !$0.isEmpty }
            return trackers.isEmpty ? nil : trackers
        }
    }

    private static func canonicalInfoBytes(from data: Data) throws -> Data {
        var extractor = InfoDictionaryByteExtractor(data: data)
        do {
            return try extractor.extract()
        } catch let error as BencodeError {
            throw TorrentCoreError.invalidBencode(error)
        }
    }

    private static func string(in dictionary: [Data: BencodeValue], preferredKey: String, fallbackKey: String) -> String? {
        dictionary[stringKey(preferredKey)]?.stringValue ?? dictionary[stringKey(fallbackKey)]?.stringValue
    }

    private static func pathComponents(
        in dictionary: [Data: BencodeValue],
        preferredKey: String,
        fallbackKey: String
    ) -> [String]? {
        let value = dictionary[stringKey(preferredKey)] ?? dictionary[stringKey(fallbackKey)]
        guard case .list(let components)? = value else { return nil }
        let strings = components.compactMap(\.stringValue)
        return strings.isEmpty ? nil : strings
    }

    private static func integer(in dictionary: [Data: BencodeValue], key: String) -> Int64? {
        dictionary[stringKey(key)]?.integerValue
    }
}

private struct InfoDictionaryByteExtractor {
    private let bytes: [UInt8]
    private var offset = 0

    init(data: Data) {
        bytes = Array(data)
    }

    mutating func extract() throws -> Data {
        guard offset < bytes.count, bytes[offset] == UInt8(ascii: "d") else {
            throw BencodeError.invalidToken(offset: offset)
        }
        offset += 1
        var previousKey: Data?
        var foundInfoBytes: Data?

        while offset < bytes.count, bytes[offset] != UInt8(ascii: "e") {
            let keyOffset = offset
            let key = try parseData()
            if let previousKey, !previousKey.lexicographicallyPrecedes(key) {
                throw BencodeError.invalidDictionaryKey(offset: keyOffset)
            }
            previousKey = key

            let valueStart = offset
            try skipValue()
            if key == stringKey("info") {
                foundInfoBytes = Data(bytes[valueStart..<offset])
            }
        }

        guard offset < bytes.count else {
            throw BencodeError.unexpectedEnd(offset: offset)
        }
        offset += 1
        guard offset == bytes.count else {
            throw BencodeError.trailingData(offset: offset)
        }
        guard let foundInfoBytes else {
            throw TorrentCoreError.invalidMetainfo("Missing torrent info dictionary.")
        }
        return foundInfoBytes
    }

    private mutating func parseData() throws -> Data {
        let start = offset
        let lengthStart = offset
        while offset < bytes.count, bytes[offset] != UInt8(ascii: ":") {
            guard bytes[offset] >= UInt8(ascii: "0"), bytes[offset] <= UInt8(ascii: "9") else {
                throw BencodeError.invalidByteStringLength(offset: start)
            }
            offset += 1
        }
        guard offset < bytes.count else {
            throw BencodeError.unexpectedEnd(offset: offset)
        }
        let rawLength = bytes[lengthStart..<offset]
        guard !rawLength.isEmpty,
              let length = Int(String(decoding: rawLength, as: UTF8.self)),
              isCanonicalLength(rawLength)
        else {
            throw BencodeError.invalidByteStringLength(offset: start)
        }

        offset += 1
        guard length >= 0, offset + length <= bytes.count else {
            throw BencodeError.unexpectedEnd(offset: offset)
        }
        let data = Data(bytes[offset..<offset + length])
        offset += length
        return data
    }

    private mutating func skipValue() throws {
        guard offset < bytes.count else {
            throw BencodeError.unexpectedEnd(offset: offset)
        }
        switch bytes[offset] {
        case UInt8(ascii: "i"):
            try skipInteger()
        case UInt8(ascii: "l"):
            offset += 1
            while offset < bytes.count, bytes[offset] != UInt8(ascii: "e") {
                try skipValue()
            }
            guard offset < bytes.count else { throw BencodeError.unexpectedEnd(offset: offset) }
            offset += 1
        case UInt8(ascii: "d"):
            offset += 1
            var previousKey: Data?
            while offset < bytes.count, bytes[offset] != UInt8(ascii: "e") {
                let keyOffset = offset
                let key = try parseData()
                if let previousKey, !previousKey.lexicographicallyPrecedes(key) {
                    throw BencodeError.invalidDictionaryKey(offset: keyOffset)
                }
                previousKey = key
                try skipValue()
            }
            guard offset < bytes.count else { throw BencodeError.unexpectedEnd(offset: offset) }
            offset += 1
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            _ = try parseData()
        default:
            throw BencodeError.invalidToken(offset: offset)
        }
    }

    private mutating func skipInteger() throws {
        let start = offset
        offset += 1
        let numberStart = offset
        while offset < bytes.count, bytes[offset] != UInt8(ascii: "e") {
            offset += 1
        }
        guard offset < bytes.count else {
            throw BencodeError.unexpectedEnd(offset: offset)
        }
        let raw = bytes[numberStart..<offset]
        offset += 1
        guard !raw.isEmpty,
              Int64(String(decoding: raw, as: UTF8.self)) != nil,
              isCanonicalInteger(raw)
        else {
            throw BencodeError.invalidInteger(offset: start)
        }
    }

    private func isCanonicalInteger(_ raw: ArraySlice<UInt8>) -> Bool {
        if raw.count == 1, raw.first == UInt8(ascii: "0") {
            return true
        }
        if raw.first == UInt8(ascii: "-") {
            let remaining = raw.dropFirst()
            guard !remaining.isEmpty, remaining.first != UInt8(ascii: "0") else { return false }
            return remaining.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }
        }
        guard raw.first != UInt8(ascii: "0") else { return false }
        return raw.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }
    }

    private func isCanonicalLength(_ raw: ArraySlice<UInt8>) -> Bool {
        if raw.count == 1, raw.first == UInt8(ascii: "0") {
            return true
        }
        guard raw.first != UInt8(ascii: "0") else { return false }
        return raw.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }
    }
}

private func stringKey(_ key: String) -> Data {
    Data(key.utf8)
}

private extension Data {
    func lexicographicallyPrecedes(_ other: Data) -> Bool {
        lexicographicallyPrecedes(other, by: <)
    }
}
