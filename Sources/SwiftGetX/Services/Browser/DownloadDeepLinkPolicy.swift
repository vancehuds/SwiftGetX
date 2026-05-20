import Foundation
import SwiftGetXCore

struct DownloadDeepLinkValidation: Equatable, Sendable {
    var linkTrust: DownloadLinkTrust
    var sourceCount: Int
}

enum DownloadDeepLinkPolicy {
    static let maximumURLLength = 8 * 1_024
    static let maximumPublicTaskCount = 20

    static func validation(
        for url: URL,
        components: URLComponents,
        source: String,
        handoffSource: String?,
        handoffAck: NativeHandoffAck?,
        now: Date = .now
    ) -> DownloadDeepLinkValidation? {
        guard url.absoluteString.utf8.count <= maximumURLLength,
              hasSafeQueryCharacters(in: components),
              !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let sources = SourceParser.extractSources(from: source)
        guard !sources.isEmpty,
              sources.count <= maximumPublicTaskCount,
              sources.allSatisfy(isAllowedDownloadSource),
              !containsRejectedTopLevelScheme(in: source)
        else {
            return nil
        }

        return DownloadDeepLinkValidation(
            linkTrust: trust(
                handoffSource: handoffSource,
                handoffAck: handoffAck,
                now: now
            ),
            sourceCount: sources.count
        )
    }

    static func isNativeHandoffSource(_ source: String?) -> Bool {
        guard let source else { return false }
        return nativeHandoffSources.contains(source)
    }

    private static let nativeHandoffSources: Set<String> = [
        "native-host",
        "download-takeover",
        "context-menu-link",
        "context-menu-page",
        "context-menu-selection",
        "context-menu-media",
        "context-menu-scan",
        "popup-current-page",
        "popup-selection",
        "popup-scan"
    ]

    private static func trust(
        handoffSource: String?,
        handoffAck: NativeHandoffAck?,
        now: Date
    ) -> DownloadLinkTrust {
        guard isNativeHandoffSource(handoffSource),
              let handoffAck,
              handoffAck.expiresAt != nil,
              !handoffAck.isExpired(now: now)
        else {
            return .publicLink
        }

        return .trustedNativeHandoff
    }

    private static func hasSafeQueryCharacters(in components: URLComponents) -> Bool {
        components.queryItems?.allSatisfy { item in
            hasNoDangerousCharacters(item.name, allowsSourceDelimiters: false)
                && hasNoDangerousCharacters(item.value ?? "", allowsSourceDelimiters: item.name == "url")
        } ?? true
    }

    private static func hasNoDangerousCharacters(_ value: String, allowsSourceDelimiters: Bool) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            if allowsSourceDelimiters && (scalar == "\n" || scalar == "\r" || scalar == "\t") {
                return true
            }

            if CharacterSet.controlCharacters.contains(scalar) || scalar.value == 0x7F {
                return false
            }

            if (0x202A...0x202E).contains(scalar.value) {
                return false
            }

            if (0x2066...0x2069).contains(scalar.value) {
                return false
            }

            return true
        }
    }

    private static func isAllowedDownloadSource(_ source: String) -> Bool {
        if SourceParser.localFileURL(for: source) != nil {
            return SourceParser.kind(for: source) == .torrentFile
        }

        guard let components = URLComponents(string: source),
              let scheme = components.scheme?.lowercased()
        else {
            return false
        }

        if scheme == "magnet" {
            return source.lowercased().hasPrefix("magnet:?")
        }

        guard scheme == "http" || scheme == "https" else {
            return false
        }

        return components.host?.isEmpty == false
    }

    private static func containsRejectedTopLevelScheme(in source: String) -> Bool {
        let pattern = #"(?i)(?:^|[\s<>\[\]\(\)"'`])([a-z][a-z0-9+.-]{1,31}):"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }

        let allowedSchemes: Set<String> = ["http", "https", "magnet", "file"]
        let nsSource = source as NSString
        let range = NSRange(location: 0, length: nsSource.length)
        return regex.matches(in: source, range: range).contains { match in
            guard match.numberOfRanges > 1 else { return false }
            let scheme = nsSource.substring(with: match.range(at: 1)).lowercased()
            return !allowedSchemes.contains(scheme)
        }
    }
}
