import Foundation
import SwiftGetXCore

enum PrivacyRedactor {
    static func redactedText(_ text: String) -> String {
        var redacted = replaceURLLikeSubstrings(in: text)
        redacted = replaceSensitiveHeaders(in: redacted)
        redacted = replaceSensitiveAssignments(in: redacted)
        redacted = replaceBearerTokens(in: redacted)
        return redacted
    }

    static func redactedURLString(_ value: String?) -> String? {
        BrowserDownloadContext.redactedURLString(value)
    }

    private static func replaceURLLikeSubstrings(in text: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)\b(?:https?|ftp)://[^\s<>"')\]]+"#,
            options: []
        ) else {
            return text
        }

        let nsText = text as NSString
        let matches = expression.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            let value = nsText.substring(with: match.range)
            let replacement = BrowserDownloadContext.redactedURLString(value) ?? value
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }

    private static func replaceSensitiveHeaders(in text: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?im)\b(authorization|cookie|proxy-authorization|x-api-key|x-auth-token|x-csrf-token|x-xsrf-token)\s*[:=]\s*[^\r\n]+"#,
            options: []
        ) else {
            return text
        }

        let nsText = text as NSString
        let matches = expression.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            let key = nsText.substring(with: match.range(at: 1))
            let replacement = "\(key)=\(BrowserDownloadContext.redactedValue)"
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }

    private static func replaceSensitiveAssignments(in text: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)\b(token|auth|signature|sig|key)\s*[:=]\s*([^\s,;&]+)"#,
            options: []
        ) else {
            return text
        }

        let nsText = text as NSString
        let matches = expression.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            let key = nsText.substring(with: match.range(at: 1))
            let replacement = "\(key)=\(BrowserDownloadContext.redactedValue)"
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }

    private static func replaceBearerTokens(in text: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+"#,
            options: []
        ) else {
            return text
        }

        let nsText = text as NSString
        let matches = expression.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: "Bearer \(BrowserDownloadContext.redactedValue)")
            }
        }
        return result
    }
}
