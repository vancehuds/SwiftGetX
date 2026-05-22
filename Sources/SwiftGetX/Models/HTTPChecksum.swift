import CryptoKit
import Foundation

enum HTTPChecksumAlgorithm: String, Codable, CaseIterable, Sendable {
    case sha256
    case sha1
    case md5

    var title: String {
        switch self {
        case .sha256:
            "SHA-256"
        case .sha1:
            "SHA-1"
        case .md5:
            "MD5"
        }
    }

    var hexDigitCount: Int {
        switch self {
        case .sha256:
            64
        case .sha1:
            40
        case .md5:
            32
        }
    }
}

enum HTTPChecksumStatus: String, Codable, CaseIterable, Sendable {
    case notRequested
    case pending
    case verified
    case failed
    case unavailable

    var title: String {
        switch self {
        case .notRequested:
            L10n.string("http_checksum_status_not_requested")
        case .pending:
            L10n.string("http_checksum_status_pending")
        case .verified:
            L10n.string("http_checksum_status_verified")
        case .failed:
            L10n.string("http_checksum_status_failed")
        case .unavailable:
            L10n.string("http_checksum_status_unavailable")
        }
    }
}

struct HTTPChecksum: Codable, Equatable, Sendable {
    var algorithm: HTTPChecksumAlgorithm
    var expectedHexDigest: String

    init?(algorithm: HTTPChecksumAlgorithm, expectedHexDigest: String) {
        guard let normalized = Self.normalizedHexDigest(expectedHexDigest),
              normalized.count == algorithm.hexDigitCount
        else {
            return nil
        }
        self.algorithm = algorithm
        self.expectedHexDigest = normalized
    }

    init?(input: String, preferredFilename: String? = nil) {
        guard let discovered = Self.discover(from: input, preferredFilename: preferredFilename) else {
            return nil
        }
        self = discovered
    }

    var expectedHexDigestUppercased: String {
        expectedHexDigest.uppercased()
    }

    func verification(for data: Data) -> HTTPChecksumVerification {
        let actualHexDigest = Self.actualHexDigest(algorithm: algorithm, data: data)
        return HTTPChecksumVerification(
            expected: self,
            actualHexDigest: actualHexDigest,
            matches: actualHexDigest.caseInsensitiveCompare(expectedHexDigest) == .orderedSame
        )
    }

    func verification(forFileAt url: URL) throws -> HTTPChecksumVerification {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        switch algorithm {
        case .sha256:
            var hasher = SHA256()
            try Self.update(&hasher, using: handle)
            let actualHexDigest = Data(hasher.finalize()).hexString
            return HTTPChecksumVerification(
                expected: self,
                actualHexDigest: actualHexDigest,
                matches: actualHexDigest.caseInsensitiveCompare(expectedHexDigest) == .orderedSame
            )
        case .sha1:
            var hasher = Insecure.SHA1()
            try Self.update(&hasher, using: handle)
            let actualHexDigest = Data(hasher.finalize()).hexString
            return HTTPChecksumVerification(
                expected: self,
                actualHexDigest: actualHexDigest,
                matches: actualHexDigest.caseInsensitiveCompare(expectedHexDigest) == .orderedSame
            )
        case .md5:
            var hasher = Insecure.MD5()
            try Self.update(&hasher, using: handle)
            let actualHexDigest = Data(hasher.finalize()).hexString
            return HTTPChecksumVerification(
                expected: self,
                actualHexDigest: actualHexDigest,
                matches: actualHexDigest.caseInsensitiveCompare(expectedHexDigest) == .orderedSame
            )
        }
    }

    static func discover(from text: String, preferredFilename: String? = nil) -> HTTPChecksum? {
        if let candidate = discoverDirectHex(from: text) {
            return candidate
        }

        if let candidate = discoverChecksumManifest(from: text, preferredFilename: preferredFilename) {
            return candidate
        }

        if let candidate = discoverReleaseMetadata(from: text, preferredFilename: preferredFilename) {
            return candidate
        }

        return discoverMetalink(from: text, preferredFilename: preferredFilename)
    }

    static func normalizedHexDigest(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty,
              normalized.unicodeScalars.allSatisfy({ hexDigits.contains($0) })
        else {
            return nil
        }
        return normalized
    }

    static func isValidHexDigest(_ value: String?) -> Bool {
        guard let normalized = normalizedHexDigest(value) else { return false }
        return [HTTPChecksumAlgorithm.sha256, .sha1, .md5].contains(where: {
            normalized.count == $0.hexDigitCount
        })
    }

    private static func discoverDirectHex(from text: String) -> HTTPChecksum? {
        guard let normalized = normalizedHexDigest(text) else { return nil }
        switch normalized.count {
        case HTTPChecksumAlgorithm.sha256.hexDigitCount:
            return HTTPChecksum(algorithm: .sha256, expectedHexDigest: normalized)
        case HTTPChecksumAlgorithm.sha1.hexDigitCount:
            return HTTPChecksum(algorithm: .sha1, expectedHexDigest: normalized)
        case HTTPChecksumAlgorithm.md5.hexDigitCount:
            return HTTPChecksum(algorithm: .md5, expectedHexDigest: normalized)
        default:
            return nil
        }
    }

    private static func discoverChecksumManifest(from text: String, preferredFilename: String?) -> HTTPChecksum? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        for line in lines {
            if let checksum = parseManifestLine(line, preferredFilename: preferredFilename) {
                return checksum
            }
        }

        return nil
    }

    private static func parseManifestLine(_ line: String, preferredFilename: String?) -> HTTPChecksum? {
        if let checksum = parseLabeledManifestLine(line, preferredFilename: preferredFilename) {
            return checksum
        }

        if let checksum = parsePlainManifestLine(line, preferredFilename: preferredFilename) {
            return checksum
        }

        return nil
    }

    private static func parseLabeledManifestLine(_ line: String, preferredFilename: String?) -> HTTPChecksum? {
        let bsdPatterns: [(HTTPChecksumAlgorithm, String)] = [
            (.sha256, #"(?i)\bsha256\b\s*\(([^)]*)\)\s*=\s*([a-f0-9]{64})\b"#),
            (.sha1, #"(?i)\bsha1\b\s*\(([^)]*)\)\s*=\s*([a-f0-9]{40})\b"#),
            (.md5, #"(?i)\bmd5\b\s*\(([^)]*)\)\s*=\s*([a-f0-9]{32})\b"#)
        ]
        for (algorithm, pattern) in bsdPatterns {
            guard let match = firstRegexMatch(in: line, pattern: pattern),
                  let filename = match.value(1),
                  let digest = match.value(2)
            else { continue }
            guard preferredFilename == nil
                || filenameMatches(preferredFilename ?? "", lineFilename: filename)
            else {
                return nil
            }
            return HTTPChecksum(algorithm: algorithm, expectedHexDigest: digest)
        }

        let patterns: [(HTTPChecksumAlgorithm, String)] = [
            (.sha256, #"(?i)\bsha256\b[^a-f0-9]*([a-f0-9]{64})\b"#),
            (.sha1, #"(?i)\bsha1\b[^a-f0-9]*([a-f0-9]{40})\b"#),
            (.md5, #"(?i)\bmd5\b[^a-f0-9]*([a-f0-9]{32})\b"#)
        ]

        for (algorithm, pattern) in patterns {
            guard let match = firstRegexMatch(in: line, pattern: pattern),
                  let digest = match.value(1)
            else { continue }
            if let filename = match.value(2),
               let preferredFilename,
               filenameMatches(preferredFilename, lineFilename: filename)
            {
                return HTTPChecksum(algorithm: algorithm, expectedHexDigest: digest)
            }
            if match.value(2) == nil || preferredFilename == nil {
                return HTTPChecksum(algorithm: algorithm, expectedHexDigest: digest)
            }
        }

        return nil
    }

    private static func parsePlainManifestLine(_ line: String, preferredFilename: String?) -> HTTPChecksum? {
        let pattern = #"(?i)^\s*([a-f0-9]{32}|[a-f0-9]{40}|[a-f0-9]{64})(?:\s+|\s+\*\s*|\s*:\s*)(.*?)\s*$"#
        guard let match = firstRegexMatch(in: line, pattern: pattern),
              let digest = match.value(1)
        else { return nil }
        let filename = match.value(2)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let checksum = checksumForHexDigest(from: digest) else { return nil }
        if let preferredFilename, let filename, !filename.isEmpty,
           !filenameMatches(preferredFilename, lineFilename: filename)
        {
            return nil
        }
        return checksum
    }

    private static func discoverReleaseMetadata(from text: String, preferredFilename: String?) -> HTTPChecksum? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }

        return discoverReleaseMetadata(in: json, preferredFilename: preferredFilename)
    }

    private static func discoverReleaseMetadata(in value: Any, preferredFilename: String?) -> HTTPChecksum? {
        if let dictionary = value as? [String: Any] {
            if let checksum = checksum(from: dictionary, preferredFilename: preferredFilename) {
                return checksum
            }
            for item in dictionary.values {
                if let checksum = discoverReleaseMetadata(in: item, preferredFilename: preferredFilename) {
                    return checksum
                }
            }
        } else if let array = value as? [Any] {
            for item in array {
                if let checksum = discoverReleaseMetadata(in: item, preferredFilename: preferredFilename) {
                    return checksum
                }
            }
        } else if let string = value as? String {
            if let checksum = discoverDirectHex(from: string) {
                return checksum
            }
        }
        return nil
    }

    private static func checksum(from dictionary: [String: Any], preferredFilename: String?) -> HTTPChecksum? {
        if let preferredFilename,
           let matchingDictionary = dictionaryIfMatchingFilename(dictionary, preferredFilename: preferredFilename)
        {
            return checksum(from: matchingDictionary, preferredFilename: nil)
        }

        for key in checksumKeyPriority {
            if let value = dictionary[key] as? String,
               let checksum = checksum(from: value)
            {
                return checksum
            }
            if let nested = dictionary[key] as? [String: Any],
               let checksum = checksum(from: nested, preferredFilename: preferredFilename)
            {
                return checksum
            }
        }

        for value in dictionary.values {
            if let checksum = discoverReleaseMetadata(in: value, preferredFilename: preferredFilename) {
                return checksum
            }
        }
        return nil
    }

    private static func dictionaryIfMatchingFilename(
        _ dictionary: [String: Any],
        preferredFilename: String
    ) -> [String: Any]? {
        guard let filename = dictionary["filename"] as? String ?? dictionary["name"] as? String else {
            return nil
        }
        guard filenameMatches(preferredFilename, lineFilename: filename) else {
            return nil
        }
        return dictionary
    }

    private static func checksum(from value: String) -> HTTPChecksum? {
        if let checksum = discoverDirectHex(from: value) {
            return checksum
        }

        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for algorithm in HTTPChecksumAlgorithm.allCases {
            let prefixes = [
                "\(algorithm.rawValue):",
                "\(algorithm.rawValue) =",
                "\(algorithm.title.lowercased()):",
                "\(algorithm.title.lowercased()) ="
            ]
            for prefix in prefixes where lowered.hasPrefix(prefix) {
                let digest = String(value.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let checksum = HTTPChecksum(algorithm: algorithm, expectedHexDigest: digest) {
                    return checksum
                }
            }
        }

        return nil
    }

    private static func discoverMetalink(from text: String, preferredFilename: String?) -> HTTPChecksum? {
        let patterns: [(HTTPChecksumAlgorithm, String)] = [
            (.sha256, #"(?is)<hash[^>]*type\s*=\s*["']?sha256["']?[^>]*>([a-f0-9]{64})</hash>"#),
            (.sha1, #"(?is)<hash[^>]*type\s*=\s*["']?sha1["']?[^>]*>([a-f0-9]{40})</hash>"#),
            (.md5, #"(?is)<hash[^>]*type\s*=\s*["']?md5["']?[^>]*>([a-f0-9]{32})</hash>"#)
        ]

        for (algorithm, pattern) in patterns {
            if let match = firstRegexMatch(in: text, pattern: pattern),
               let digest = match.value(1),
               let checksum = HTTPChecksum(algorithm: algorithm, expectedHexDigest: digest)
            {
                return checksum
            }
        }

        return discoverDirectHex(from: text)
    }

    private static func checksumForHexDigest(from digest: String) -> HTTPChecksum? {
        guard let normalized = normalizedHexDigest(digest) else { return nil }
        switch normalized.count {
        case HTTPChecksumAlgorithm.sha256.hexDigitCount:
            return HTTPChecksum(algorithm: .sha256, expectedHexDigest: normalized)
        case HTTPChecksumAlgorithm.sha1.hexDigitCount:
            return HTTPChecksum(algorithm: .sha1, expectedHexDigest: normalized)
        case HTTPChecksumAlgorithm.md5.hexDigitCount:
            return HTTPChecksum(algorithm: .md5, expectedHexDigest: normalized)
        default:
            return nil
        }
    }

    private static func actualHexDigest(algorithm: HTTPChecksumAlgorithm, data: Data) -> String {
        switch algorithm {
        case .sha256:
            Data(SHA256.hash(data: data)).hexString
        case .sha1:
            Data(Insecure.SHA1.hash(data: data)).hexString
        case .md5:
            Data(Insecure.MD5.hash(data: data)).hexString
        }
    }

    private static func update<HashType: HashFunction>(
        _ hasher: inout HashType,
        using handle: FileHandle
    ) throws {
        while true {
            let data = try handle.read(upToCount: 64 * 1024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
    }

    private static func firstRegexMatch(in text: String, pattern: String) -> RegexMatch? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = expression.firstMatch(in: text, range: range) else { return nil }
        return RegexMatch(nsText: nsText, match: match)
    }

    private static func filenameMatches(_ lhs: String, lineFilename rhs: String) -> Bool {
        let normalizedLHS = normalizedManifestFilename(lhs)
        let normalizedRHS = normalizedManifestFilename(rhs)
        return normalizedLHS == normalizedRHS
            || normalizedLHS.hasSuffix("/\(normalizedRHS)")
            || normalizedRHS.hasSuffix("/\(normalizedLHS)")
    }

    private static func normalizedManifestFilename(_ value: String) -> String {
        var normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
        if normalized.hasPrefix("*") {
            normalized.removeFirst()
        }
        return normalized
    }

    private static let checksumKeyPriority = [
        "sha256",
        "sha1",
        "md5",
        "checksum",
        "digest",
        "hash"
    ]

    private static let hexDigits = CharacterSet(charactersIn: "0123456789abcdef")
}

struct HTTPChecksumVerification: Equatable, Sendable {
    let expected: HTTPChecksum
    let actualHexDigest: String
    let matches: Bool
}

private struct RegexMatch {
    let nsText: NSString
    let match: NSTextCheckingResult

    func value(_ index: Int) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return nsText.substring(with: range)
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
