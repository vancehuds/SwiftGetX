import Foundation

enum HTTPContentDisposition {
    static func suggestedFilename(from headerValue: String?) -> String? {
        let parameters = parameters(from: headerValue)
        if let filename = parameters["filename*"].flatMap(decodeExtendedFilename) {
            return sanitizedFilename(filename)
        }
        if let filename = parameters["filename"].flatMap(decodeFilename) {
            return sanitizedFilename(filename)
        }
        return nil
    }

    private static func parameters(from headerValue: String?) -> [String: String] {
        guard let headerValue else { return [:] }
        let parts = splitParameters(headerValue)
        guard parts.count > 1 else { return [:] }

        return parts.dropFirst().reduce(into: [String: String]()) { result, part in
            let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pieces.count == 2 else { return }
            let name = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, result[name] == nil else { return }
            result[name] = unquoted(value)
        }
    }

    private static func splitParameters(_ value: String) -> [String] {
        var parts = [String]()
        var current = ""
        var isQuoted = false
        var isEscaped = false

        for character in value {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if isQuoted, character == "\\" {
                current.append(character)
                isEscaped = true
                continue
            }
            if character == "\"" {
                isQuoted.toggle()
                current.append(character)
                continue
            }
            if character == ";", !isQuoted {
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current.removeAll(keepingCapacity: true)
                continue
            }
            current.append(character)
        }

        parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return parts
    }

    private static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else {
            return trimmed
        }

        let inner = trimmed.dropFirst().dropLast()
        var result = ""
        var isEscaped = false
        for character in inner {
            if isEscaped {
                result.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                result.append(character)
            }
        }
        if isEscaped {
            result.append("\\")
        }
        return result
    }

    private static func decodeExtendedFilename(_ value: String) -> String? {
        let pieces = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        guard pieces.count == 3 else {
            return decodePercentEncoded(value, charset: "utf-8")
        }

        let charset = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return decodePercentEncoded(String(pieces[2]), charset: charset)
    }

    private static func decodeFilename(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }

    private static func decodePercentEncoded(_ value: String, charset: String) -> String? {
        guard let data = percentDecodedData(value) else { return nil }
        switch charset {
        case "", "utf-8", "utf8", "us-ascii", "ascii":
            return String(data: data, encoding: .utf8)
        case "iso-8859-1", "latin1", "latin-1":
            return String(data: data, encoding: .isoLatin1)
        default:
            return String(data: data, encoding: .utf8)
        }
    }

    private static func percentDecodedData(_ value: String) -> Data? {
        let scalars = Array(value.unicodeScalars)
        var bytes = [UInt8]()
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "%",
               index + 2 < scalars.count,
               let high = hexValue(scalars[index + 1]),
               let low = hexValue(scalars[index + 2])
            {
                bytes.append(UInt8(high * 16 + low))
                index += 3
                continue
            }

            guard let data = String(scalar).data(using: .utf8) else { return nil }
            bytes.append(contentsOf: data)
            index += 1
        }

        return Data(bytes)
    }

    private static func hexValue(_ scalar: UnicodeScalar) -> Int? {
        switch scalar.value {
        case 48...57:
            Int(scalar.value - 48)
        case 65...70:
            Int(scalar.value - 55)
        case 97...102:
            Int(scalar.value - 87)
        default:
            nil
        }
    }

    private static func sanitizedFilename(_ value: String) -> String? {
        let basename = value
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .last
            .map(String.init) ?? value
        let withoutUnsafeScalars = String(basename.unicodeScalars.map { scalar in
            if CharacterSet.controlCharacters.contains(scalar) || isBidirectionalOverride(scalar) {
                return "-"
            }
            return String(scalar)
        }.joined())
        let sanitized = SourceParser
            .sanitizeFilename(withoutUnsafeScalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty, sanitized != ".", sanitized != ".." else {
            return nil
        }
        return sanitized
    }

    private static func isBidirectionalOverride(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x202A...0x202E, 0x2066...0x2069:
            true
        default:
            false
        }
    }
}
