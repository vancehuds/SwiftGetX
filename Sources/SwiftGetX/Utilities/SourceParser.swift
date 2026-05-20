import Foundation

enum SourceParser {
    static func extractSources(from text: String) -> [String] {
        sourceCandidates(in: text)
            .compactMap(normalizedSource)
    }

    static func kind(for source: String) -> DownloadKind {
        let lowercasedSource = source.lowercased()
        if lowercasedSource.hasPrefix("magnet:") {
            return .torrentMagnet
        }
        if URL(string: source)?.path.lowercased().hasSuffix(".torrent") == true
            || lowercasedSource.hasSuffix(".torrent")
        {
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
            return L10n.string("default_magnet_task_filename", String(shortHash(source))) + ".torrent"
        case .torrentFile:
            return urlFilename(source) ?? L10n.string("default_torrent_task_filename")
        case .http:
            return urlFilename(source) ?? L10n.string("default_unnamed_download_filename")
        }
    }

    private static func urlFilename(_ source: String) -> String? {
        guard let url = URL(string: source) else { return nil }
        if let githubArtifactFilename = githubActionsArtifactFilename(from: url) {
            return githubArtifactFilename
        }
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

    private static func sourceCandidates(in text: String) -> [String] {
        let pattern = #"(?i)(magnet:\?[^\s<>\]]+|https?://[^\s<>\]]+|[^\s<>\]]+\.torrent(?:\?[^\s<>\]]*)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).map { match in
            cleanCandidate(nsText.substring(with: match.range))
        }
    }

    private static func cleanCandidate(_ candidate: String) -> String {
        var source = candidate.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "<>[]{}\"'`")
        ))
        while let last = source.last, ".,;!?)".contains(last) {
            source.removeLast()
        }
        return source
    }

    private static func normalizedSource(_ source: String) -> String? {
        let lowercasedSource = source.lowercased()
        guard lowercasedSource.hasPrefix("http://")
            || lowercasedSource.hasPrefix("https://")
            || lowercasedSource.hasPrefix("magnet:")
            || lowercasedSource.hasSuffix(".torrent")
        else {
            return nil
        }

        if let url = URL(string: source),
           let githubArtifactURL = githubActionsArtifactDownloadURL(from: url)
        {
            return githubArtifactURL.absoluteString
        }
        return source
    }

    private static func githubActionsArtifactDownloadURL(from url: URL) -> URL? {
        guard let artifact = githubActionsArtifact(from: url),
              url.host?.localizedCaseInsensitiveCompare("api.github.com") != .orderedSame
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(artifact.owner)/\(artifact.repository)/actions/artifacts/\(artifact.id)/zip"
        return components.url
    }

    private static func githubActionsArtifactFilename(from url: URL) -> String? {
        guard let artifact = githubActionsArtifact(from: url) else { return nil }
        return sanitizeFilename("\(artifact.repository)-artifact-\(artifact.id).zip")
    }

    private static func githubActionsArtifact(from url: URL) -> GitHubActionsArtifact? {
        guard let host = url.host?.lowercased() else { return nil }
        let pathComponents = url.path
            .split(separator: "/")
            .map { String($0.removingPercentEncoding ?? String($0)) }

        if host == "github.com" || host == "www.github.com" {
            guard pathComponents.count >= 7,
                  pathComponents[2].caseInsensitiveCompare("actions") == .orderedSame,
                  pathComponents[3].caseInsensitiveCompare("runs") == .orderedSame,
                  pathComponents[5].caseInsensitiveCompare("artifacts") == .orderedSame,
                  isNumeric(pathComponents[6])
            else {
                return nil
            }
            return GitHubActionsArtifact(
                owner: pathComponents[0],
                repository: pathComponents[1],
                id: pathComponents[6]
            )
        }

        if host == "api.github.com" {
            guard pathComponents.count >= 7,
                  pathComponents[0].caseInsensitiveCompare("repos") == .orderedSame,
                  pathComponents[3].caseInsensitiveCompare("actions") == .orderedSame,
                  pathComponents[4].caseInsensitiveCompare("artifacts") == .orderedSame,
                  pathComponents[6].caseInsensitiveCompare("zip") == .orderedSame,
                  isNumeric(pathComponents[5])
            else {
                return nil
            }
            return GitHubActionsArtifact(
                owner: pathComponents[1],
                repository: pathComponents[2],
                id: pathComponents[5]
            )
        }

        return nil
    }

    private static func isNumeric(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }
}

private struct GitHubActionsArtifact {
    let owner: String
    let repository: String
    let id: String
}
