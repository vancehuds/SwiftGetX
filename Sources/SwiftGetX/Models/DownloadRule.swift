import Foundation
import SwiftGetXCore

struct DownloadRule: Codable, Equatable, Sendable {
    static let maximumRuleCount = 64

    var name: String
    var domains: [String]
    var fileExtensions: [String]
    var minSizeBytes: Int64?
    var maxSizeBytes: Int64?
    var saveDirectoryPath: String?
    var segmentCount: Int?
    var retryLimit: Int?
    var autoStart: Bool?
    var filenameTemplate: String?
    var headers: [BrowserDownloadHeader]

    private enum CodingKeys: String, CodingKey {
        case name
        case domains
        case fileExtensions
        case minSizeBytes
        case maxSizeBytes
        case saveDirectoryPath
        case segmentCount
        case retryLimit
        case autoStart
        case filenameTemplate
        case headers
    }

    init(
        name: String = "",
        domains: [String] = [],
        fileExtensions: [String] = [],
        minSizeBytes: Int64? = nil,
        maxSizeBytes: Int64? = nil,
        saveDirectoryPath: String? = nil,
        segmentCount: Int? = nil,
        retryLimit: Int? = nil,
        autoStart: Bool? = nil,
        filenameTemplate: String? = nil,
        headers: [BrowserDownloadHeader] = []
    ) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.domains = HostPattern.normalized(domains)
        self.fileExtensions = Self.normalizedExtensions(fileExtensions)
        self.minSizeBytes = minSizeBytes.flatMap { $0 > 0 ? $0 : nil }
        self.maxSizeBytes = maxSizeBytes.flatMap { $0 > 0 ? $0 : nil }
        self.saveDirectoryPath = Self.nonEmpty(saveDirectoryPath)
        self.segmentCount = HTTPDownloadOptions(segmentCountOverride: segmentCount).segmentCountOverride
        self.retryLimit = HTTPDownloadOptions(retryLimitOverride: retryLimit).retryLimitOverride
        self.autoStart = autoStart
        self.filenameTemplate = Self.nonEmpty(filenameTemplate)
        self.headers = HTTPDownloadOptions(additionalHeaders: headers).persistable.additionalHeaders
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
            domains: try container.decodeIfPresent([String].self, forKey: .domains) ?? [],
            fileExtensions: try container.decodeIfPresent([String].self, forKey: .fileExtensions) ?? [],
            minSizeBytes: try container.decodeIfPresent(Int64.self, forKey: .minSizeBytes),
            maxSizeBytes: try container.decodeIfPresent(Int64.self, forKey: .maxSizeBytes),
            saveDirectoryPath: try container.decodeIfPresent(String.self, forKey: .saveDirectoryPath),
            segmentCount: try container.decodeIfPresent(Int.self, forKey: .segmentCount),
            retryLimit: try container.decodeIfPresent(Int.self, forKey: .retryLimit),
            autoStart: try container.decodeIfPresent(Bool.self, forKey: .autoStart),
            filenameTemplate: try container.decodeIfPresent(String.self, forKey: .filenameTemplate),
            headers: try container.decodeIfPresent([BrowserDownloadHeader].self, forKey: .headers) ?? []
        )
    }

    var hasSavePathOverride: Bool {
        saveDirectoryPath != nil || filenameTemplate != nil
    }

    func matches(
        source: String,
        kind: DownloadKind,
        filename: String,
        totalBytes: Int64?
    ) -> Bool {
        if !domains.isEmpty {
            guard let host = Self.host(from: source),
                  domains.contains(where: { HostPattern.matches(host: host, pattern: $0) })
            else {
                return false
            }
        }

        if !fileExtensions.isEmpty {
            let extensionValue = Self.fileExtension(source: source, filename: filename, kind: kind)
            guard let extensionValue, fileExtensions.contains(extensionValue) else {
                return false
            }
        }

        if let minSizeBytes {
            guard let totalBytes, totalBytes >= minSizeBytes else { return false }
        }

        if let maxSizeBytes {
            guard let totalBytes, totalBytes <= maxSizeBytes else { return false }
        }

        return true
    }

    func plannedSaveURL(
        fallbackURL: URL,
        source: String,
        filename: String,
        date: Date = Date()
    ) -> URL {
        guard hasSavePathOverride else { return fallbackURL }
        let baseDirectory = saveDirectoryPath
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
            ?? fallbackURL.deletingLastPathComponent()
        let safeFilename = SourceParser.sanitizeFilename(filename)

        guard let filenameTemplate else {
            let resolvedFilename = Self.safeOutputFilename(safeFilename.isEmpty ? filename : safeFilename)
            return baseDirectory.appendingPathComponent(resolvedFilename)
        }

        let relativeComponents = Self.renderTemplateComponents(
            template: filenameTemplate,
            source: source,
            filename: filename,
            date: date
        )
        guard !relativeComponents.isEmpty else {
            let resolvedFilename = Self.safeOutputFilename(safeFilename.isEmpty ? filename : safeFilename)
            return baseDirectory.appendingPathComponent(resolvedFilename)
        }

        return relativeComponents.reduce(baseDirectory) { partial, component in
            partial.appendingPathComponent(component)
        }
    }

    private static func renderTemplateComponents(
        template: String,
        source: String,
        filename: String,
        date: Date
    ) -> [String] {
        let filename = SourceParser.sanitizeFilename(filename)
        let pathExtension = URL(fileURLWithPath: filename).pathExtension
        let baseName = pathExtension.isEmpty
            ? filename
            : String(filename.dropLast(pathExtension.count + 1))
        let host = host(from: source) ?? "local"

        let rendered = template
            .replacingOccurrences(of: "{date}", with: DateFormatter.downloadRuleDate.string(from: date))
            .replacingOccurrences(of: "{domain}", with: SourceParser.sanitizeFilename(host))
            .replacingOccurrences(of: "{host}", with: SourceParser.sanitizeFilename(host))
            .replacingOccurrences(of: "{filename}", with: filename)
            .replacingOccurrences(of: "{basename}", with: SourceParser.sanitizeFilename(baseName))
            .replacingOccurrences(of: "{ext}", with: SourceParser.sanitizeFilename(pathExtension))

        return rendered
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { SourceParser.sanitizeFilename(String($0)) }
            .filter { component in
                !component.isEmpty && component != "." && component != ".."
            }
    }

    private static func host(from source: String) -> String? {
        guard let host = URL(string: source)?.host(percentEncoded: false) else { return nil }
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func fileExtension(source: String, filename: String, kind: DownloadKind) -> String? {
        if kind == .torrentMagnet {
            return "torrent"
        }
        let filenameExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if !filenameExtension.isEmpty {
            return filenameExtension
        }
        if let url = URL(string: source) {
            let sourceExtension = url.pathExtension.lowercased()
            if !sourceExtension.isEmpty {
                return sourceExtension
            }
        }
        return nil
    }

    private static func normalizedList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",;")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private static func normalizedExtensions(_ values: [String]) -> [String] {
        normalizedList(values).map { value in
            value.hasPrefix(".") ? String(value.dropFirst()) : value
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private static func safeOutputFilename(_ value: String) -> String {
        let sanitized = SourceParser.sanitizeFilename(value)
        guard !sanitized.isEmpty, sanitized != ".", sanitized != ".." else {
            return SourceParser.displayName(for: "about:blank", kind: .http)
        }
        return sanitized
    }
}

enum DownloadRuleTextFormat {
    static func parse(_ text: String) -> [DownloadRule] {
        var rules = [DownloadRule]()
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let rule = parseLine(trimmed) else { continue }
            rules.append(rule)
            if rules.count >= DownloadRule.maximumRuleCount {
                break
            }
        }
        return rules
    }

    static func format(_ rules: [DownloadRule]) -> String {
        rules.map(formatRule).joined(separator: "\n")
    }

    private static func parseLine(_ line: String) -> DownloadRule? {
        let parts = line
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }

        var name = ""
        var domains = [String]()
        var extensions = [String]()
        var minSizeBytes: Int64?
        var maxSizeBytes: Int64?
        var saveDirectoryPath: String?
        var segmentCount: Int?
        var retryLimit: Int?
        var autoStart: Bool?
        var filenameTemplate: String?
        var headers = [BrowserDownloadHeader]()

        for (index, part) in parts.enumerated() {
            let keyValue = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard keyValue.count == 2 else {
                if index == 0 {
                    name = part
                }
                continue
            }

            let key = keyValue[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = keyValue[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            switch key {
            case "name":
                name = value
            case "domain", "domains", "host", "hosts":
                domains.append(contentsOf: splitList(value))
            case "ext", "extension", "extensions":
                extensions.append(contentsOf: splitList(value))
            case "min", "minsize", "minsizebytes":
                minSizeBytes = parseByteCount(value)
            case "max", "maxsize", "maxsizebytes":
                maxSizeBytes = parseByteCount(value)
            case "dir", "directory", "save", "savedirectory":
                saveDirectoryPath = value
            case "segments", "segment", "threads", "thread":
                segmentCount = Int(value)
            case "retries", "retry":
                retryLimit = Int(value)
            case "autostart", "auto-start", "start":
                autoStart = parseBool(value)
            case "template", "filenametemplate":
                filenameTemplate = value
            case "header", "headers":
                headers.append(contentsOf: HTTPDownloadOptions.headers(from: value))
            default:
                continue
            }
        }

        let rule = DownloadRule(
            name: name,
            domains: domains,
            fileExtensions: extensions,
            minSizeBytes: minSizeBytes,
            maxSizeBytes: maxSizeBytes,
            saveDirectoryPath: saveDirectoryPath,
            segmentCount: segmentCount,
            retryLimit: retryLimit,
            autoStart: autoStart,
            filenameTemplate: filenameTemplate,
            headers: headers
        )
        return rule.domains.isEmpty
            && rule.fileExtensions.isEmpty
            && rule.minSizeBytes == nil
            && rule.maxSizeBytes == nil
            && rule.saveDirectoryPath == nil
            && rule.segmentCount == nil
            && rule.retryLimit == nil
            && rule.autoStart == nil
            && rule.filenameTemplate == nil
            && rule.headers.isEmpty
            ? nil
            : rule
    }

    private static func formatRule(_ rule: DownloadRule) -> String {
        var parts = [String]()
        if !rule.name.isEmpty {
            parts.append("name=\(rule.name)")
        }
        if !rule.domains.isEmpty {
            parts.append("domain=\(rule.domains.joined(separator: ","))")
        }
        if !rule.fileExtensions.isEmpty {
            parts.append("ext=\(rule.fileExtensions.joined(separator: ","))")
        }
        if let minSizeBytes = rule.minSizeBytes {
            parts.append("min=\(minSizeBytes)")
        }
        if let maxSizeBytes = rule.maxSizeBytes {
            parts.append("max=\(maxSizeBytes)")
        }
        if let saveDirectoryPath = rule.saveDirectoryPath {
            parts.append("dir=\(saveDirectoryPath)")
        }
        if let segmentCount = rule.segmentCount {
            parts.append("segments=\(segmentCount)")
        }
        if let retryLimit = rule.retryLimit {
            parts.append("retries=\(retryLimit)")
        }
        if let autoStart = rule.autoStart {
            parts.append("autoStart=\(autoStart)")
        }
        if let filenameTemplate = rule.filenameTemplate {
            parts.append("template=\(filenameTemplate)")
        }
        for header in rule.headers {
            parts.append("header=\(header.name): \(header.value)")
        }
        return parts.joined(separator: " | ")
    }

    private static func splitList(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseBool(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return nil
        }
    }

    private static func parseByteCount(_ value: String) -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let numberPart = trimmed.prefix { character in
            character.isNumber || character == "."
        }
        guard let number = Double(numberPart), number > 0 else { return nil }
        let suffix = trimmed.dropFirst(numberPart.count).trimmingCharacters(in: .whitespacesAndNewlines)
        let multiplier: Double
        switch suffix {
        case "", "b", "byte", "bytes":
            multiplier = 1
        case "k", "kb", "kib":
            multiplier = 1_024
        case "m", "mb", "mib":
            multiplier = 1_024 * 1_024
        case "g", "gb", "gib":
            multiplier = 1_024 * 1_024 * 1_024
        default:
            return nil
        }
        return Int64(number * multiplier)
    }
}

enum BrowserTakeoverPolicyDecision: Equatable {
    case allowed
    case rejected(reason: String)
}

enum BrowserTakeoverPolicy {
    static func decision(
        for source: String,
        allowedHosts: [String],
        blockedHosts: [String]
    ) -> BrowserTakeoverPolicyDecision {
        guard let host = URL(string: source)?.host(percentEncoded: false)?.lowercased() else {
            return .allowed
        }

        let blockedHosts = HostPattern.normalized(blockedHosts)
        if blockedHosts.contains(where: { HostPattern.matches(host: host, pattern: $0) }) {
            return .rejected(reason: "blockedByHostPolicy")
        }

        let allowedHosts = HostPattern.normalized(allowedHosts)
        guard !allowedHosts.isEmpty else { return .allowed }
        if allowedHosts.contains(where: { HostPattern.matches(host: host, pattern: $0) }) {
            return .allowed
        }
        return .rejected(reason: "notAllowedByHostPolicy")
    }
}

enum HostPattern {
    static func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",;")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { $0.hasPrefix("*.") ? String($0.dropFirst(2)) : $0 }
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    static func matches(host: String, pattern: String) -> Bool {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty, !pattern.isEmpty else { return false }
        return host == pattern || host.hasSuffix(".\(pattern)")
    }
}

private extension DateFormatter {
    static let downloadRuleDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
