import Foundation
import SwiftGetXCore

struct HTTPDownloadOptions: Codable, Equatable, Sendable {
    static let maximumSegmentCount = 128
    static let maximumRetryLimit = 50
    static let maximumHeaderCount = 32

    var segmentCountOverride: Int?
    var retryLimitOverride: Int?
    var perTaskDownloadLimitBytes: Int64?
    var filenameOverride: String?
    var checksum: HTTPChecksum?
    var additionalHeaders: [BrowserDownloadHeader]

    init(
        segmentCountOverride: Int? = nil,
        retryLimitOverride: Int? = nil,
        perTaskDownloadLimitBytes: Int64? = nil,
        filenameOverride: String? = nil,
        checksum: HTTPChecksum? = nil,
        additionalHeaders: [BrowserDownloadHeader] = []
    ) {
        self.segmentCountOverride = Self.clampedSegmentCount(segmentCountOverride)
        self.retryLimitOverride = Self.clampedRetryLimit(retryLimitOverride)
        self.perTaskDownloadLimitBytes = Self.positiveLimit(perTaskDownloadLimitBytes)
        self.filenameOverride = Self.sanitizedFilename(filenameOverride)
        self.checksum = checksum
        self.additionalHeaders = Self.sanitizedHeaders(additionalHeaders)
    }

    var persistable: HTTPDownloadOptions {
        HTTPDownloadOptions(
            segmentCountOverride: segmentCountOverride,
            retryLimitOverride: retryLimitOverride,
            perTaskDownloadLimitBytes: perTaskDownloadLimitBytes,
            filenameOverride: filenameOverride,
            checksum: checksum,
            additionalHeaders: additionalHeaders.compactMap(\.persistable)
        )
    }

    var isEmpty: Bool {
        segmentCountOverride == nil
            && retryLimitOverride == nil
            && perTaskDownloadLimitBytes == nil
            && filenameOverride == nil
            && checksum == nil
            && additionalHeaders.isEmpty
    }

    func effectiveSegmentCount(defaultSegmentCount: Int, multithreadingEnabled: Bool) -> Int {
        if let segmentCountOverride {
            return segmentCountOverride
        }
        let defaultCount = multithreadingEnabled ? defaultSegmentCount : 1
        return Self.clampedSegmentCount(defaultCount) ?? 1
    }

    func effectiveRetryLimit(defaultRetryLimit: Int) -> Int {
        retryLimitOverride ?? Self.clampedRetryLimit(defaultRetryLimit) ?? 0
    }

    func httpHeaders() -> [String: String] {
        var values = [String: String]()
        for header in additionalHeaders {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = header.trimmedValue
            guard !name.isEmpty, !value.isEmpty else { continue }
            guard !Self.controlledHeaderNames.contains(name.lowercased()) else { continue }
            values[name] = value
        }
        return values
    }

    static func headers(from text: String) -> [BrowserDownloadHeader] {
        text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> BrowserDownloadHeader? in
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return nil }
                let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !value.isEmpty else { return nil }
                return BrowserDownloadHeader(name: name, value: value)
            }
    }

    private enum CodingKeys: String, CodingKey {
        case segmentCountOverride
        case retryLimitOverride
        case perTaskDownloadLimitBytes
        case filenameOverride
        case checksum
        case additionalHeaders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedHeaders = try container.decodeIfPresent(
            [BrowserDownloadHeader].self,
            forKey: .additionalHeaders
        ) ?? []
        self.init(
            segmentCountOverride: try container.decodeIfPresent(Int.self, forKey: .segmentCountOverride),
            retryLimitOverride: try container.decodeIfPresent(Int.self, forKey: .retryLimitOverride),
            perTaskDownloadLimitBytes: try container.decodeIfPresent(Int64.self, forKey: .perTaskDownloadLimitBytes),
            filenameOverride: try container.decodeIfPresent(String.self, forKey: .filenameOverride),
            checksum: try container.decodeIfPresent(HTTPChecksum.self, forKey: .checksum),
            additionalHeaders: decodedHeaders.compactMap(\.persistable)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(segmentCountOverride, forKey: .segmentCountOverride)
        try container.encodeIfPresent(retryLimitOverride, forKey: .retryLimitOverride)
        try container.encodeIfPresent(perTaskDownloadLimitBytes, forKey: .perTaskDownloadLimitBytes)
        try container.encodeIfPresent(filenameOverride, forKey: .filenameOverride)
        try container.encodeIfPresent(checksum, forKey: .checksum)
        let persistableHeaders = additionalHeaders.compactMap(\.persistable)
        if !persistableHeaders.isEmpty {
            try container.encode(persistableHeaders, forKey: .additionalHeaders)
        }
    }

    private static func clampedSegmentCount(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return min(max(1, value), maximumSegmentCount)
    }

    private static func clampedRetryLimit(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return min(max(0, value), maximumRetryLimit)
    }

    private static func positiveLimit(_ value: Int64?) -> Int64? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func sanitizedFilename(_ value: String?) -> String? {
        HTTPResponseMetadata(suggestedFilename: value).suggestedFilename
    }

    private static func sanitizedHeaders(_ headers: [BrowserDownloadHeader]) -> [BrowserDownloadHeader] {
        var seen = Set<String>()
        var sanitized = [BrowserDownloadHeader]()
        for header in headers {
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = header.trimmedValue
            let normalizedName = name.lowercased()
            guard !name.isEmpty,
                  !value.isEmpty,
                  !controlledHeaderNames.contains(normalizedName),
                  seen.insert(normalizedName).inserted
            else {
                continue
            }
            sanitized.append(BrowserDownloadHeader(name: name, value: value, sensitive: header.sensitive))
            if sanitized.count >= maximumHeaderCount {
                break
            }
        }
        return sanitized
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
