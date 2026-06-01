import Foundation
import UniformTypeIdentifiers

enum DownloadDropSourceLoader {
    static let supportedTypeIdentifiers = [
        UTType.fileURL.identifier,
        UTType.url.identifier,
        UTType.plainText.identifier,
        "public.utf8-plain-text",
        "public.text"
    ]

    @discardableResult
    static func loadDraft(
        from providers: [NSItemProvider],
        completion: @escaping @MainActor (DownloadDraft?) -> Void
    ) -> Bool {
        let group = DispatchGroup()
        let accumulator = DropSourceAccumulator()
        var didAcceptProvider = false

        for provider in providers {
            guard let typeIdentifier = supportedTypeIdentifiers.first(where: {
                provider.hasItemConformingToTypeIdentifier($0)
            }) else {
                continue
            }

            didAcceptProvider = true
            group.enter()
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                let loaded = loadedValues(from: item, typeIdentifier: typeIdentifier)
                accumulator.append(textFragments: loaded.textFragments, urls: loaded.urls)
                group.leave()
            }
        }

        guard didAcceptProvider else { return false }

        group.notify(queue: .main) {
            let draft = accumulator.draft()
            Task { @MainActor in
                completion(draft)
            }
        }
        return true
    }

    private static func loadedValues(
        from item: NSSecureCoding?,
        typeIdentifier: String
    ) -> (textFragments: [String], urls: [URL]) {
        switch item {
        case let url as URL:
            return ([], [url])
        case let url as NSURL:
            return ([], [url as URL])
        case let data as Data:
            guard let text = String(data: data, encoding: .utf8) else { return ([], []) }
            return values(fromText: text, typeIdentifier: typeIdentifier)
        case let string as String:
            return values(fromText: string, typeIdentifier: typeIdentifier)
        case let string as NSString:
            return values(fromText: String(string), typeIdentifier: typeIdentifier)
        default:
            return ([], [])
        }
    }

    private static func values(
        fromText text: String,
        typeIdentifier: String
    ) -> (textFragments: [String], urls: [URL]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if typeIdentifier == UTType.fileURL.identifier || typeIdentifier == UTType.url.identifier,
           let url = URL(string: trimmed)
        {
            return ([], [url])
        }
        return ([text], [])
    }
}

private final class DropSourceAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var textFragments = [String]()
    private var urls = [URL]()

    func append(textFragments: [String], urls: [URL]) {
        lock.lock()
        self.textFragments.append(contentsOf: textFragments)
        self.urls.append(contentsOf: urls)
        lock.unlock()
    }

    func draft() -> DownloadDraft? {
        lock.lock()
        let textFragments = self.textFragments
        let urls = self.urls
        lock.unlock()
        return DownloadInputSourceCollector.draft(textFragments: textFragments, urls: urls)
    }
}
