import Foundation
import SwiftGetXCore

enum DownloadPreviewDuplicateStrategy: Equatable, Sendable {
    case none
    case autoRename(originalFilename: String, resolvedFilename: String)
}

actor HTTPMetadataPreviewService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func preview(
        source: String,
        suggestedFilename: String? = nil,
        saveDirectory: URL,
        browserContext: BrowserDownloadContext? = nil
    ) async -> TorrentMetadataPreview {
        guard let url = URL(string: source),
              url.scheme?.localizedCaseInsensitiveCompare("http") == .orderedSame
                || url.scheme?.localizedCaseInsensitiveCompare("https") == .orderedSame
        else {
            return fallbackPreview(
                source: source,
                suggestedFilename: suggestedFilename,
                saveDirectory: saveDirectory,
                browserContext: browserContext,
                error: L10n.string("error_invalid_url")
            )
        }

        let request = previewRequest(source: source, url: url, browserContext: browserContext)
        let metadata = await HTTPMetadataProbe(
            segmentCount: 1,
            probesRangeForIncompleteMetadata: true,
            timeoutInterval: 12
        ).probe(url: url, request: request)
        guard hasUsefulServerPreview(metadata, source: source) else {
            return fallbackPreview(
                source: source,
                suggestedFilename: suggestedFilename,
                saveDirectory: saveDirectory,
                browserContext: browserContext,
                error: nil
            )
        }

        let serverMetadata = metadata.responseMetadata ?? HTTPResponseMetadata.fromCreationContext(
            source: source,
            browserContext: browserContext,
            totalBytes: metadata.contentLength,
            supportsResume: metadata.supportsResume,
            eTag: metadata.eTag,
            lastModified: metadata.lastModified
        )
        let displayName = displayName(
            source: source,
            finalURL: serverMetadata.finalURL,
            metadata: serverMetadata,
            suggestedFilename: suggestedFilename
        )
        let savePlan = savePlan(displayName: displayName, saveDirectory: saveDirectory)
        let responseMetadata = serverMetadata.merged(over: HTTPResponseMetadata.fromCreationContext(
            source: source,
            browserContext: browserContext,
            suggestedFilename: displayName,
            totalBytes: metadata.contentLength,
            supportsResume: metadata.supportsResume,
            eTag: metadata.eTag,
            lastModified: metadata.lastModified
        ))

        return TorrentMetadataPreview(
            source: source,
            kind: .http,
            displayName: displayName,
            resolvedTorrentFilePath: nil,
            files: [],
            totalBytes: metadata.contentLength,
            metadataStatus: .available,
            errorMessage: nil,
            httpResponseMetadata: responseMetadata,
            supportsResume: metadata.supportsResume,
            savePath: savePlan.path,
            duplicateStrategy: savePlan.duplicateStrategy,
            browserContext: browserContext
        )
    }

    private func previewRequest(
        source: String,
        url: URL,
        browserContext: BrowserDownloadContext?
    ) -> DownloadRequest {
        DownloadRequest(
            id: UUID(),
            name: SourceParser.displayName(for: source, kind: .http),
            source: source,
            kind: .http,
            savePath: url.lastPathComponent,
            totalBytes: 0,
            downloadedBytes: 0,
            supportsResume: false,
            eTag: nil,
            lastModified: nil,
            selectedFileIndexes: [],
            browserContext: browserContext
        )
    }

    private func fallbackPreview(
        source: String,
        suggestedFilename: String?,
        saveDirectory: URL,
        browserContext: BrowserDownloadContext?,
        error: String?
    ) -> TorrentMetadataPreview {
        let displayName = sanitizedSuggestedFilename(suggestedFilename)
            ?? SourceParser.displayName(for: source, kind: .http)
        let savePlan = savePlan(displayName: displayName, saveDirectory: saveDirectory)
        return TorrentMetadataPreview(
            source: source,
            kind: .http,
            displayName: displayName,
            resolvedTorrentFilePath: nil,
            files: [],
            totalBytes: 0,
            metadataStatus: error == nil ? .unavailable : .failed,
            errorMessage: error,
            httpResponseMetadata: HTTPResponseMetadata.fromCreationContext(
                source: source,
                browserContext: browserContext,
                suggestedFilename: displayName
            ),
            supportsResume: false,
            savePath: savePlan.path,
            duplicateStrategy: savePlan.duplicateStrategy,
            browserContext: browserContext
        )
    }

    private func hasUsefulServerPreview(_ metadata: HTTPMetadata, source: String) -> Bool {
        guard let responseMetadata = metadata.responseMetadata else { return false }
        return metadata.contentLength > 0
            || metadata.supportsResume
            || responseMetadata.contentDisposition != nil
            || responseMetadata.mimeType != nil
            || responseMetadata.server != nil
            || responseMetadata.wasRedirected
            || responseMetadata.finalURL != BrowserDownloadContext.redactedURLString(source)
    }

    private func displayName(
        source: String,
        finalURL: String?,
        metadata: HTTPResponseMetadata,
        suggestedFilename: String?
    ) -> String {
        metadata.suggestedFilename
            ?? sanitizedSuggestedFilename(suggestedFilename)
            ?? finalURL.map { SourceParser.displayName(for: $0, kind: .http) }
            ?? SourceParser.displayName(for: source, kind: .http)
    }

    private func sanitizedSuggestedFilename(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        let filenameOnly = (trimmed.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        return HTTPResponseMetadata(suggestedFilename: filenameOnly).suggestedFilename
    }

    private func savePlan(
        displayName: String,
        saveDirectory: URL
    ) -> (path: String, duplicateStrategy: DownloadPreviewDuplicateStrategy) {
        let proposed = saveDirectory.appendingPathComponent(displayName)
        let resolved = fileManager.uniqueFileURL(for: proposed)
        if resolved.path == proposed.path {
            return (resolved.path, .none)
        }
        return (
            resolved.path,
            .autoRename(
                originalFilename: proposed.lastPathComponent,
                resolvedFilename: resolved.lastPathComponent
            )
        )
    }
}
