import Foundation

enum ReleaseValidation {
    static let sparklePublicKeyByteCount = 32
    static let sparklePublicKeyPlaceholders: Set<String> = [
        "",
        "REPLACE_WITH_YOUR_EDDSA_PUBLIC_KEY",
        "YOUR_EDDSA_PUBLIC_KEY",
        "TODO",
        "CHANGEME"
    ]

    static func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    static func isValidSparklePublicKey(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sparklePublicKeyPlaceholders.contains(trimmed) else { return false }
        guard let data = Data(base64Encoded: trimmed) else { return false }
        return data.count == sparklePublicKeyByteCount
    }

    static func defaultReleaseNotesURL(
        repositoryURL: URL = URL(string: "https://github.com/vancehuds/SwiftGetX")!,
        version: String
    ) -> URL? {
        let normalized = normalizedVersion(version)
        guard !normalized.isEmpty else { return nil }
        return repositoryURL.appendingPathComponent("releases/tag/v\(normalized)")
    }
}
