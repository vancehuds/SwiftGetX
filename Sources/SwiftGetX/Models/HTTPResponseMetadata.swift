import Foundation
import SwiftGetXCore

struct HTTPRedirectMetadata: Codable, Equatable, Sendable {
    var statusCode: Int
    var fromURL: String?
    var toURL: String?

    init(statusCode: Int, fromURL: String?, toURL: String?) {
        self.statusCode = statusCode
        self.fromURL = BrowserDownloadContext.redactedURLString(fromURL)
        self.toURL = BrowserDownloadContext.redactedURLString(toURL)
    }
}

struct HTTPResponseMetadata: Codable, Equatable, Sendable {
    var originalURL: String?
    var finalURL: String?
    var sourcePageURL: String?
    var mimeType: String?
    var contentDisposition: String?
    var suggestedFilename: String?
    var server: String?
    var supportsResume: Bool?
    var contentLength: Int64?
    var eTag: String?
    var lastModified: String?
    var redirects: [HTTPRedirectMetadata]

    init(
        originalURL: String? = nil,
        finalURL: String? = nil,
        sourcePageURL: String? = nil,
        mimeType: String? = nil,
        contentDisposition: String? = nil,
        suggestedFilename: String? = nil,
        server: String? = nil,
        supportsResume: Bool? = nil,
        contentLength: Int64? = nil,
        eTag: String? = nil,
        lastModified: String? = nil,
        redirects: [HTTPRedirectMetadata] = []
    ) {
        self.originalURL = Self.redactedURL(originalURL)
        self.finalURL = Self.redactedURL(finalURL)
        self.sourcePageURL = Self.redactedURL(sourcePageURL)
        self.mimeType = Self.nonEmpty(mimeType)
        self.contentDisposition = Self.nonEmpty(contentDisposition)
        self.suggestedFilename = Self.sanitizedFilename(suggestedFilename)
        self.server = Self.nonEmpty(server)
        self.supportsResume = supportsResume
        self.contentLength = contentLength
        self.eTag = Self.nonEmpty(eTag)
        self.lastModified = Self.nonEmpty(lastModified)
        self.redirects = redirects
    }

    var wasRedirected: Bool {
        if !redirects.isEmpty {
            return true
        }
        guard let originalURL, let finalURL else { return false }
        return originalURL != finalURL
    }

    func merged(over fallback: HTTPResponseMetadata?) -> HTTPResponseMetadata {
        guard let fallback else { return self }
        return HTTPResponseMetadata(
            originalURL: originalURL ?? fallback.originalURL,
            finalURL: finalURL ?? fallback.finalURL,
            sourcePageURL: sourcePageURL ?? fallback.sourcePageURL,
            mimeType: mimeType ?? fallback.mimeType,
            contentDisposition: contentDisposition ?? fallback.contentDisposition,
            suggestedFilename: suggestedFilename ?? fallback.suggestedFilename,
            server: server ?? fallback.server,
            supportsResume: supportsResume ?? fallback.supportsResume,
            contentLength: contentLength ?? fallback.contentLength,
            eTag: eTag ?? fallback.eTag,
            lastModified: lastModified ?? fallback.lastModified,
            redirects: redirects.isEmpty ? fallback.redirects : redirects
        )
    }

    static func fromCreationContext(
        source: String,
        browserContext: BrowserDownloadContext?,
        suggestedFilename: String? = nil,
        totalBytes: Int64 = 0,
        supportsResume: Bool? = nil,
        eTag: String? = nil,
        lastModified: String? = nil
    ) -> HTTPResponseMetadata {
        HTTPResponseMetadata(
            originalURL: browserContext?.originalURL ?? source,
            finalURL: browserContext?.finalURL ?? source,
            sourcePageURL: browserContext?.sourcePageURL ?? browserContext?.referrer,
            suggestedFilename: suggestedFilename ?? browserContext?.suggestedFilename,
            supportsResume: supportsResume,
            contentLength: totalBytes > 0 ? totalBytes : nil,
            eTag: eTag,
            lastModified: lastModified
        )
    }

    private static func redactedURL(_ value: String?) -> String? {
        BrowserDownloadContext.redactedURLString(nonEmpty(value))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private static func sanitizedFilename(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }
        let basename = value
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? value
        let withoutUnsafeScalars = String(basename.unicodeScalars.map { scalar in
            if isBidirectionalOverride(scalar) {
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
