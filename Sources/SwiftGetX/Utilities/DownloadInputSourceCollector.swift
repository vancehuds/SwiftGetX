import AppKit
import Foundation

enum DownloadInputSourceCollector {
    static func sources(textFragments: [String] = [], urls: [URL] = []) -> [String] {
        var seen = Set<String>()
        var collected = [String]()
        let fragments = textFragments + urls.compactMap(sourceString(from:))

        for fragment in fragments {
            for source in SourceParser.extractSources(from: fragment) where seen.insert(source).inserted {
                collected.append(source)
            }
        }

        return collected
    }

    static func sources(from pasteboard: NSPasteboard) -> [String] {
        var textFragments = [String]()
        var urls = [URL]()

        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) ?? []
        for object in objects {
            if let url = object as? URL {
                urls.append(url)
            } else if let url = object as? NSURL {
                urls.append(url as URL)
            }
        }

        for type in NSPasteboard.PasteboardType.downloadInputTextTypes {
            if let value = pasteboard.string(forType: type), !value.isEmpty {
                textFragments.append(value)
            }
        }

        if let filenames = pasteboard.propertyList(forType: .legacyFileNames) as? [String] {
            textFragments.append(contentsOf: filenames)
        }

        return sources(textFragments: textFragments, urls: urls)
    }

    static func draft(textFragments: [String] = [], urls: [URL] = []) -> DownloadDraft? {
        let sources = sources(textFragments: textFragments, urls: urls)
        guard !sources.isEmpty else { return nil }

        return DownloadDraft(
            source: sources.joined(separator: "\n"),
            linkTrust: .publicLink,
            sourceCount: sources.count
        )
    }

    static func sourceString(from url: URL) -> String? {
        if url.isFileURL {
            let path = url.path
            return path.lowercased().hasSuffix(".torrent") ? path : nil
        }

        guard let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "http", "https", "magnet":
            return url.absoluteString
        default:
            return nil
        }
    }

    static func draft(from pasteboard: NSPasteboard) -> DownloadDraft? {
        let sources = sources(from: pasteboard)
        guard !sources.isEmpty else { return nil }

        return DownloadDraft(
            source: sources.joined(separator: "\n"),
            linkTrust: .publicLink,
            sourceCount: sources.count
        )
    }
}

private extension NSPasteboard.PasteboardType {
    static let legacyFileNames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    static let downloadInputTextTypes: [NSPasteboard.PasteboardType] = [
        .string,
        NSPasteboard.PasteboardType("NSStringPboardType"),
        NSPasteboard.PasteboardType("NSURLPboardType"),
        NSPasteboard.PasteboardType("public.url"),
        NSPasteboard.PasteboardType("public.file-url"),
        NSPasteboard.PasteboardType("public.utf8-plain-text"),
        NSPasteboard.PasteboardType("public.text")
    ]
}
