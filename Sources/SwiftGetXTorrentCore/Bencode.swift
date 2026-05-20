import Foundation

public enum BencodeError: Error, Equatable, Sendable, LocalizedError {
    case unexpectedEnd(offset: Int)
    case invalidToken(offset: Int)
    case invalidInteger(offset: Int)
    case invalidByteStringLength(offset: Int)
    case invalidDictionaryKey(offset: Int)
    case trailingData(offset: Int)
    case inputLimitExceeded(offset: Int)
    case nestingLimitExceeded(offset: Int)
    case collectionLimitExceeded(offset: Int)
    case byteStringLimitExceeded(offset: Int)

    public var errorDescription: String? {
        switch self {
        case .unexpectedEnd(let offset):
            "Unexpected end of bencode at byte \(offset)."
        case .invalidToken(let offset):
            "Invalid bencode token at byte \(offset)."
        case .invalidInteger(let offset):
            "Invalid bencode integer at byte \(offset)."
        case .invalidByteStringLength(let offset):
            "Invalid bencode byte string length at byte \(offset)."
        case .invalidDictionaryKey(let offset):
            "Invalid bencode dictionary key at byte \(offset)."
        case .trailingData(let offset):
            "Trailing data after bencode value at byte \(offset)."
        case .inputLimitExceeded(let offset):
            "Bencode input size limit exceeded at byte \(offset)."
        case .nestingLimitExceeded(let offset):
            "Bencode nesting limit exceeded at byte \(offset)."
        case .collectionLimitExceeded(let offset):
            "Bencode collection item limit exceeded at byte \(offset)."
        case .byteStringLimitExceeded(let offset):
            "Bencode byte string length limit exceeded at byte \(offset)."
        }
    }
}

public struct BencodeLimits: Equatable, Sendable {
    public static let `default` = BencodeLimits()

    public var maximumInputBytes: Int
    public var maximumDepth: Int
    public var maximumCollectionElements: Int
    public var maximumByteStringLength: Int

    public init(
        maximumInputBytes: Int = 64 * 1024 * 1024,
        maximumDepth: Int = 128,
        maximumCollectionElements: Int = 100_000,
        maximumByteStringLength: Int = 64 * 1024 * 1024
    ) {
        self.maximumInputBytes = max(0, maximumInputBytes)
        self.maximumDepth = max(0, maximumDepth)
        self.maximumCollectionElements = max(0, maximumCollectionElements)
        self.maximumByteStringLength = max(0, maximumByteStringLength)
    }
}

public enum BencodeValue: Equatable, Sendable {
    case integer(Int64)
    case data(Data)
    case list([BencodeValue])
    case dictionary([Data: BencodeValue])

    public subscript(_ key: String) -> BencodeValue? {
        guard let data = key.data(using: .utf8) else { return nil }
        guard case .dictionary(let dictionary) = self else { return nil }
        return dictionary[data]
    }

    public var stringValue: String? {
        guard case .data(let data) = self else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public var integerValue: Int64? {
        guard case .integer(let integer) = self else { return nil }
        return integer
    }

    public var listValue: [BencodeValue]? {
        guard case .list(let list) = self else { return nil }
        return list
    }

    public var dictionaryValue: [Data: BencodeValue]? {
        guard case .dictionary(let dictionary) = self else { return nil }
        return dictionary
    }

    public func encoded() -> Data {
        switch self {
        case .integer(let integer):
            return Data("i\(integer)e".utf8)
        case .data(let data):
            var encoded = Data("\(data.count):".utf8)
            encoded.append(data)
            return encoded
        case .list(let list):
            var encoded = Data("l".utf8)
            for value in list {
                encoded.append(value.encoded())
            }
            encoded.append(UInt8(ascii: "e"))
            return encoded
        case .dictionary(let dictionary):
            var encoded = Data("d".utf8)
            for key in dictionary.keys.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
                encoded.append(BencodeValue.data(key).encoded())
                if let value = dictionary[key] {
                    encoded.append(value.encoded())
                }
            }
            encoded.append(UInt8(ascii: "e"))
            return encoded
        }
    }
}

public struct BencodeParser: Sendable {
    private let data: Data
    private let limits: BencodeLimits

    public init(data: Data, limits: BencodeLimits = .default) {
        self.data = data
        self.limits = limits
    }

    public func parse() throws -> BencodeValue {
        guard data.count <= limits.maximumInputBytes else {
            throw BencodeError.inputLimitExceeded(offset: limits.maximumInputBytes)
        }
        let bytes = Array(data)
        var parser = BencodeCursor(bytes: bytes, limits: limits)
        let value = try parser.parseValue(depth: 0)
        guard parser.offset == bytes.count else {
            throw BencodeError.trailingData(offset: parser.offset)
        }
        return value
    }
}

struct BencodeCursor {
    let bytes: [UInt8]
    let limits: BencodeLimits
    private(set) var offset = 0

    mutating func parseValue(depth: Int) throws -> BencodeValue {
        guard offset < bytes.count else {
            throw BencodeError.unexpectedEnd(offset: offset)
        }
        guard depth <= limits.maximumDepth else {
            throw BencodeError.nestingLimitExceeded(offset: offset)
        }

        switch bytes[offset] {
        case UInt8(ascii: "i"):
            return try parseInteger()
        case UInt8(ascii: "l"):
            return try parseList(depth: depth)
        case UInt8(ascii: "d"):
            return try parseDictionary(depth: depth)
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return try parseData()
        default:
            throw BencodeError.invalidToken(offset: offset)
        }
    }

    mutating func parseInfoDictionaryBytes() throws -> Data? {
        guard offset < bytes.count else {
            throw BencodeError.unexpectedEnd(offset: offset)
        }
        let start = offset
        _ = try parseValue(depth: 0)
        return Data(bytes[start..<offset])
    }

    private mutating func parseInteger() throws -> BencodeValue {
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
              let integer = Int64(String(decoding: raw, as: UTF8.self)),
              isCanonicalInteger(raw)
        else {
            throw BencodeError.invalidInteger(offset: start)
        }
        return .integer(integer)
    }

    private mutating func parseData() throws -> BencodeValue {
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
        guard length <= limits.maximumByteStringLength else {
            throw BencodeError.byteStringLimitExceeded(offset: start)
        }

        offset += 1
        guard length >= 0, length <= bytes.count - offset else {
            throw BencodeError.unexpectedEnd(offset: offset)
        }
        let data = Data(bytes[offset..<offset + length])
        offset += length
        return .data(data)
    }

    private mutating func parseList(depth: Int) throws -> BencodeValue {
        offset += 1
        var values = [BencodeValue]()
        while offset < bytes.count, bytes[offset] != UInt8(ascii: "e") {
            guard values.count < limits.maximumCollectionElements else {
                throw BencodeError.collectionLimitExceeded(offset: offset)
            }
            values.append(try parseValue(depth: depth + 1))
        }
        guard offset < bytes.count else {
            throw BencodeError.unexpectedEnd(offset: offset)
        }
        offset += 1
        return .list(values)
    }

    private mutating func parseDictionary(depth: Int) throws -> BencodeValue {
        offset += 1
        var values = [Data: BencodeValue]()
        var previousKey: Data?

        while offset < bytes.count, bytes[offset] != UInt8(ascii: "e") {
            guard values.count < limits.maximumCollectionElements else {
                throw BencodeError.collectionLimitExceeded(offset: offset)
            }
            let keyOffset = offset
            guard case .data(let key) = try parseData() else {
                throw BencodeError.invalidDictionaryKey(offset: keyOffset)
            }
            if let previousKey, !previousKey.lexicographicallyPrecedes(key) {
                throw BencodeError.invalidDictionaryKey(offset: keyOffset)
            }
            previousKey = key
            values[key] = try parseValue(depth: depth + 1)
        }
        guard offset < bytes.count else {
            throw BencodeError.unexpectedEnd(offset: offset)
        }
        offset += 1
        return .dictionary(values)
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

private extension Data {
    func lexicographicallyPrecedes(_ other: Data) -> Bool {
        lexicographicallyPrecedes(other, by: <)
    }
}
