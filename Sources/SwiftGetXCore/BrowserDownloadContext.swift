import Foundation

public struct BrowserDownloadHeader: Codable, Equatable, Sendable {
    public var name: String
    public var value: String
    public var sensitive: Bool

    public init(name: String, value: String, sensitive: Bool = false) {
        self.name = name
        self.value = value
        self.sensitive = sensitive
    }

    public var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isSensitive: Bool {
        sensitive || Self.sensitiveHeaderNames.contains(normalizedName)
    }

    public var redacted: BrowserDownloadHeader {
        BrowserDownloadHeader(
            name: name,
            value: isSensitive ? BrowserDownloadContext.redactedValue : value,
            sensitive: sensitive
        )
    }

    public var persistable: BrowserDownloadHeader? {
        guard !isSensitive else { return nil }
        if Self.urlHeaderNames.contains(normalizedName) {
            return BrowserDownloadHeader(
                name: name,
                value: BrowserDownloadContext.redactedURLString(value) ?? value,
                sensitive: false
            )
        }
        return self
    }

    private static let sensitiveHeaderNames: Set<String> = [
        "authorization",
        "cookie",
        "proxy-authorization",
        "set-cookie",
        "x-api-key",
        "x-auth-token",
        "x-csrf-token",
        "x-xsrf-token"
    ]

    private static let urlHeaderNames: Set<String> = [
        "origin",
        "referer"
    ]
}

public struct BrowserDownloadBodyMetadata: Codable, Equatable, Sendable {
    public var byteCount: Int64?
    public var contentType: String?
    public var description: String?

    public init(byteCount: Int64? = nil, contentType: String? = nil, description: String? = nil) {
        self.byteCount = byteCount
        self.contentType = contentType
        self.description = description
    }
}

public struct BrowserDownloadContext: Codable, Equatable, Sendable {
    public static let redactedValue = "<redacted>"

    public var referrer: String?
    public var userAgent: String?
    public var method: String?
    public var headers: [BrowserDownloadHeader]
    public var bodyMetadata: BrowserDownloadBodyMetadata?
    public var finalURL: String?
    public var originalURL: String?
    public var suggestedFilename: String?
    public var sourcePageTitle: String?
    public var sourcePageURL: String?
    public var handoffSource: String?
    public var handoffSourceText: String?

    public init(
        referrer: String? = nil,
        userAgent: String? = nil,
        method: String? = nil,
        headers: [BrowserDownloadHeader] = [],
        bodyMetadata: BrowserDownloadBodyMetadata? = nil,
        finalURL: String? = nil,
        originalURL: String? = nil,
        suggestedFilename: String? = nil,
        sourcePageTitle: String? = nil,
        sourcePageURL: String? = nil,
        handoffSource: String? = nil,
        handoffSourceText: String? = nil
    ) {
        self.referrer = Self.nonEmpty(referrer)
        self.userAgent = Self.nonEmpty(userAgent)
        self.method = Self.nonEmpty(method)
        self.headers = headers
        self.bodyMetadata = bodyMetadata
        self.finalURL = Self.nonEmpty(finalURL)
        self.originalURL = Self.nonEmpty(originalURL)
        self.suggestedFilename = Self.nonEmpty(suggestedFilename)
        self.sourcePageTitle = Self.nonEmpty(sourcePageTitle)
        self.sourcePageURL = Self.nonEmpty(sourcePageURL)
        self.handoffSource = Self.nonEmpty(handoffSource)
        self.handoffSourceText = Self.nonEmpty(handoffSourceText)
    }

    public var redacted: BrowserDownloadContext {
        BrowserDownloadContext(
            referrer: Self.redactedURLString(referrer),
            userAgent: userAgent,
            method: method,
            headers: headers.map(\.redacted),
            bodyMetadata: bodyMetadata,
            finalURL: Self.redactedURLString(finalURL),
            originalURL: Self.redactedURLString(originalURL),
            suggestedFilename: suggestedFilename,
            sourcePageTitle: sourcePageTitle,
            sourcePageURL: Self.redactedURLString(sourcePageURL),
            handoffSource: handoffSource,
            handoffSourceText: Self.redactedSourceText(handoffSourceText)
        )
    }

    public var normalizedMethod: String {
        (method ?? "GET").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public var redactedPrimaryURL: String? {
        Self.redactedURLString(finalURL ?? originalURL ?? sourcePageURL ?? referrer)
    }

    public var containsSensitiveHeaders: Bool {
        headers.contains(where: \.isSensitive)
    }

    public var persistable: BrowserDownloadContext {
        BrowserDownloadContext(
            referrer: Self.redactedURLString(referrer),
            userAgent: userAgent,
            method: method,
            headers: headers.compactMap(\.persistable),
            bodyMetadata: bodyMetadata,
            finalURL: Self.redactedURLString(finalURL),
            originalURL: Self.redactedURLString(originalURL),
            suggestedFilename: suggestedFilename,
            sourcePageTitle: sourcePageTitle,
            sourcePageURL: Self.redactedURLString(sourcePageURL),
            handoffSource: handoffSource,
            handoffSourceText: nil
        )
    }

    public func httpHeaders() -> [String: String] {
        var values = [String: String]()

        for header in headers {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = header.trimmedValue
            guard !name.isEmpty, !value.isEmpty else { continue }
            guard !Self.controlledHeaderNames.contains(name.lowercased()) else { continue }
            values[name] = value
        }

        if let referrer = referrer, values.caseInsensitiveValue(for: "Referer") == nil {
            values["Referer"] = referrer
        }
        if let userAgent = userAgent, values.caseInsensitiveValue(for: "User-Agent") == nil {
            values["User-Agent"] = userAgent
        }

        return values
    }

    public static func context(from message: BrowserDownloadMessage) -> BrowserDownloadContext? {
        guard message.context != nil
            || nonEmpty(message.sourcePageUrl) != nil
            || nonEmpty(message.sourcePageTitle) != nil
            || nonEmpty(message.suggestedFilename) != nil
            || nonEmpty(message.source) != nil
        else {
            return nil
        }

        let base = message.context ?? BrowserDownloadContext()
        let messageSourceText = nonEmpty(message.url)
        return BrowserDownloadContext(
            referrer: base.referrer ?? message.sourcePageUrl,
            userAgent: base.userAgent,
            method: base.method,
            headers: base.headers,
            bodyMetadata: base.bodyMetadata,
            finalURL: base.finalURL,
            originalURL: base.originalURL ?? singleLineSource(messageSourceText),
            suggestedFilename: base.suggestedFilename ?? message.suggestedFilename,
            sourcePageTitle: base.sourcePageTitle ?? message.sourcePageTitle,
            sourcePageURL: base.sourcePageURL ?? message.sourcePageUrl,
            handoffSource: base.handoffSource ?? message.source,
            handoffSourceText: base.handoffSourceText ?? messageSourceText
        )
    }

    public static func redactedURLString(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }
        guard var components = URLComponents(string: value), components.queryItems?.isEmpty == false else {
            return value
        }

        components.queryItems = components.queryItems?.map { item in
            guard isSensitiveQueryName(item.name) else { return item }
            return URLQueryItem(name: item.name, value: redactedValue)
        }
        return components.string ?? value
    }

    private static func redactedSourceText(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else { return nil }
        let redactedSources = value
            .split(whereSeparator: \.isNewline)
            .map { source in
                redactedURLString(String(source)) ?? String(source)
            }
        return redactedSources.isEmpty ? nil : redactedSources.joined(separator: "\n")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private static func singleLineSource(_ value: String?) -> String? {
        guard let value,
              !value.contains(where: \.isNewline)
        else {
            return nil
        }
        return value
    }

    private static func isSensitiveQueryName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.contains("token")
            || lowercased.contains("auth")
            || lowercased.contains("key")
            || lowercased.contains("signature")
            || lowercased == "sig"
            || lowercased == "expires"
            || lowercased.hasPrefix("x-amz-")
    }

    private static let controlledHeaderNames: Set<String> = [
        "accept-encoding",
        "connection",
        "content-length",
        "host",
        "if-range",
        "range",
        "transfer-encoding"
    ]
}

private extension Dictionary where Key == String, Value == String {
    func caseInsensitiveValue(for name: String) -> String? {
        first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
