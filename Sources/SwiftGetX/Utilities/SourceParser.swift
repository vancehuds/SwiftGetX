import Foundation

enum SourceParser {
    static func extractSources(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: .whitespacesAndNewlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { source in
                source.hasPrefix("http://")
                    || source.hasPrefix("https://")
                    || source.hasPrefix("magnet:")
                    || source.hasSuffix(".torrent")
            }
    }

    static func kind(for source: String) -> DownloadKind {
        if source.hasPrefix("magnet:") {
            return .torrentMagnet
        }
        if source.lowercased().hasSuffix(".torrent") {
            return .torrentFile
        }
        return .http
    }

    static func displayName(for source: String, kind: DownloadKind) -> String {
        switch kind {
        case .torrentMagnet:
            if let dn = magnetDisplayName(from: source) {
                return sanitizeFilename(dn)
            }
            return "磁力任务-\(shortHash(source)).torrent"
        case .torrentFile:
            return urlFilename(source) ?? "种子任务.torrent"
        case .http:
            return urlFilename(source) ?? "未命名下载"
        }
    }

    private static func urlFilename(_ source: String) -> String? {
        guard let url = URL(string: source) else { return nil }
        let lastPathComponent = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        guard !lastPathComponent.isEmpty && lastPathComponent != "/" else { return nil }
        return sanitizeFilename(lastPathComponent)
    }

    private static func magnetDisplayName(from source: String) -> String? {
        guard let components = URLComponents(string: source),
              let dn = components.queryItems?.first(where: { $0.name == "dn" })?.value,
              !dn.isEmpty
        else {
            return nil
        }
        return dn
    }

    private static func sanitizeFilename(_ filename: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return filename
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shortHash(_ source: String) -> String {
        String(abs(source.hashValue), radix: 16).prefix(8).description
    }
}
