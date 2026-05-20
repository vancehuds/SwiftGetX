import Foundation

public struct MagnetURI: Equatable, Sendable {
    public var rawValue: String
    public var infoHashV1: Data
    public var displayName: String?
    public var trackers: [String]
    public var exactLength: Int64?

    public var infoHashV1Hex: String {
        infoHashV1.map { String(format: "%02x", $0) }.joined()
    }

    public static func parse(_ rawValue: String) throws -> MagnetURI {
        guard let components = URLComponents(string: rawValue),
              components.scheme?.localizedCaseInsensitiveCompare("magnet") == .orderedSame
        else {
            throw TorrentCoreError.invalidMagnet("Invalid magnet URI.")
        }

        let items = components.queryItems ?? []
        guard let xt = items
            .filter({ $0.name == "xt" })
            .compactMap(\.value)
            .first(where: { $0.lowercased().hasPrefix("urn:btih:") })
        else {
            throw TorrentCoreError.invalidMagnet("Magnet URI is missing a btih topic.")
        }

        let rawHash = String(xt.dropFirst("urn:btih:".count))
        let infoHash = try parseInfoHash(rawHash)
        let displayName = items.first(where: { $0.name == "dn" })?.value?.trimmedNonEmpty
        let trackers = items
            .filter { $0.name == "tr" }
            .compactMap { $0.value?.trimmedNonEmpty }
        let exactLength = try exactLength(from: items.first(where: { $0.name == "xl" })?.value)
        if let exactLength, exactLength < 0 {
            throw TorrentCoreError.invalidMagnet("Magnet exact length cannot be negative.")
        }

        return MagnetURI(
            rawValue: rawValue,
            infoHashV1: infoHash,
            displayName: displayName,
            trackers: trackers,
            exactLength: exactLength
        )
    }

    private static func exactLength(from rawValue: String?) throws -> Int64? {
        guard let rawValue else { return nil }
        guard let exactLength = Int64(rawValue) else {
            throw TorrentCoreError.invalidMagnet("Magnet exact length must be an integer.")
        }
        return exactLength
    }

    private static func parseInfoHash(_ rawHash: String) throws -> Data {
        if rawHash.count == 40, let data = Data(hexEncoded: rawHash), data.count == 20 {
            return data
        }
        if rawHash.count == 32, let data = Data(base32Encoded: rawHash), data.count == 20 {
            return data
        }
        throw TorrentCoreError.invalidMagnet("Magnet btih hash must be 40-character hex or 32-character base32.")
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Data {
    init?(hexEncoded string: String) {
        guard string.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(string.count / 2)

        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    init?(base32Encoded string: String) {
        let alphabet = Dictionary(uniqueKeysWithValues: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".enumerated().map {
            (Character(String($0.element)), UInt8($0.offset))
        })
        var buffer = UInt32(0)
        var bitCount = 0
        var bytes = [UInt8]()
        bytes.reserveCapacity(20)

        for character in string.uppercased() {
            guard let value = alphabet[character] else { return nil }
            buffer = (buffer << 5) | UInt32(value)
            bitCount += 5

            while bitCount >= 8 {
                let shift = bitCount - 8
                bytes.append(UInt8((buffer >> UInt32(shift)) & 0xff))
                bitCount -= 8
                buffer &= (UInt32(1) << UInt32(bitCount)) - 1
            }
        }

        guard bytes.count == 20 else { return nil }
        self.init(bytes)
    }
}
