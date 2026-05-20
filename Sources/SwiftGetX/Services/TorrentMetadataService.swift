import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftGetXCore
import SwiftGetXTorrentCore

struct TorrentMetadataPreview: Equatable, Sendable {
    var source: String
    var kind: DownloadKind
    var displayName: String
    var resolvedTorrentFilePath: String?
    var files: [TorrentFile]
    var totalBytes: Int64
    var metadataStatus: TorrentMetadataStatus
    var errorMessage: String?
    var trackers: [String]
    var httpResponseMetadata: HTTPResponseMetadata?
    var supportsResume: Bool
    var savePath: String?
    var duplicateStrategy: DownloadPreviewDuplicateStrategy
    var browserContext: BrowserDownloadContext?

    var selectedFileIndexes: [Int] {
        files.map(\.index)
    }

    init(
        source: String,
        kind: DownloadKind,
        displayName: String,
        resolvedTorrentFilePath: String?,
        files: [TorrentFile],
        totalBytes: Int64,
        metadataStatus: TorrentMetadataStatus,
        errorMessage: String?,
        trackers: [String] = [],
        httpResponseMetadata: HTTPResponseMetadata? = nil,
        supportsResume: Bool = false,
        savePath: String? = nil,
        duplicateStrategy: DownloadPreviewDuplicateStrategy = .none,
        browserContext: BrowserDownloadContext? = nil
    ) {
        self.source = source
        self.kind = kind
        self.displayName = displayName
        self.resolvedTorrentFilePath = resolvedTorrentFilePath
        self.files = files
        self.totalBytes = totalBytes
        self.metadataStatus = metadataStatus
        self.errorMessage = errorMessage
        self.trackers = trackers
        self.httpResponseMetadata = httpResponseMetadata
        self.supportsResume = supportsResume
        self.savePath = savePath
        self.duplicateStrategy = duplicateStrategy
        self.browserContext = browserContext
    }
}

actor TorrentMetadataService {
    static let shared = TorrentMetadataService()

    private let fileManager: FileManager
    private let urlSession: URLSession
    private let magnetTimeout: Duration

    init(
        fileManager: FileManager = .default,
        urlSession: URLSession = .shared,
        magnetTimeout: Duration = .seconds(12)
    ) {
        self.fileManager = fileManager
        self.urlSession = urlSession
        self.magnetTimeout = magnetTimeout
    }

    func preview(source: String, suggestedFilename: String? = nil) async -> TorrentMetadataPreview {
        let kind = SourceParser.kind(for: source)
        switch kind {
        case .http:
            return TorrentMetadataPreview(
                source: source,
                kind: kind,
                displayName: suggestedFilename ?? SourceParser.displayName(for: source, kind: kind),
                resolvedTorrentFilePath: nil,
                files: [],
                totalBytes: 0,
                metadataStatus: .unavailable,
                errorMessage: nil
            )
        case .torrentFile:
            return await previewTorrentFile(source: source, suggestedFilename: suggestedFilename)
        case .torrentMagnet:
            return await previewMagnet(source: source, suggestedFilename: suggestedFilename)
        }
    }

    func cachedTorrentFile(for source: String) async throws -> URL {
        if let localURL = SourceParser.localFileURL(for: source) {
            return try copyTorrentFileToCache(localURL)
        }

        guard let url = URL(string: source), url.scheme?.hasPrefix("http") == true else {
            throw TorrentMetadataError.invalidTorrentSource
        }

        let (temporaryURL, response) = try await urlSession.download(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw TorrentMetadataError.httpStatus(httpResponse.statusCode)
        }
        let cachedURL = try cacheURL(
            filename: SourceParser.displayName(for: source, kind: .torrentFile),
            preferredExtension: "torrent"
        )
        try? fileManager.removeItem(at: cachedURL)
        try fileManager.moveItem(at: temporaryURL, to: cachedURL)
        return cachedURL
    }

    private func previewTorrentFile(source: String, suggestedFilename: String?) async -> TorrentMetadataPreview {
        do {
            let cachedURL = try await cachedTorrentFile(for: source)
            let metadata = try TorrentMetainfo.parse(url: cachedURL)
            let displayName = suggestedFilename?.nonEmpty
                ?? metadata.name.nonEmpty
                ?? SourceParser.displayName(for: source, kind: .torrentFile)

            return TorrentMetadataPreview(
                source: source,
                kind: .torrentFile,
                displayName: displayName,
                resolvedTorrentFilePath: cachedURL.path,
                files: metadata.files.map {
                    TorrentFile(index: $0.index, path: $0.path, size: $0.length, progress: 0)
                },
                totalBytes: metadata.totalLength,
                metadataStatus: .available,
                errorMessage: nil,
                trackers: metadata.trackerURLs
            )
        } catch {
            return TorrentMetadataPreview(
                source: source,
                kind: .torrentFile,
                displayName: suggestedFilename?.nonEmpty ?? SourceParser.displayName(for: source, kind: .torrentFile),
                resolvedTorrentFilePath: nil,
                files: [],
                totalBytes: 0,
                metadataStatus: .failed,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func previewMagnet(source: String, suggestedFilename: String?) async -> TorrentMetadataPreview {
        do {
            return try await withThrowingTaskGroup(of: TorrentMetadataPreview.self) { group in
                group.addTask {
                    try await self.nativeMagnetPreview(source: source, suggestedFilename: suggestedFilename)
                }
                group.addTask {
                    try await Task.sleep(for: self.magnetTimeout)
                    throw TorrentMetadataError.metadataTimeout
                }

                guard let preview = try await group.next() else {
                    throw TorrentMetadataError.metadataTimeout
                }
                group.cancelAll()
                return preview
            }
        } catch {
            let metadataStatus: TorrentMetadataStatus = (error as? TorrentMetadataError) == .metadataTimeout
                ? .fetching
                : .unavailable
            return TorrentMetadataPreview(
                source: source,
                kind: .torrentMagnet,
                displayName: suggestedFilename?.nonEmpty ?? SourceParser.displayName(for: source, kind: .torrentMagnet),
                resolvedTorrentFilePath: nil,
                files: [],
                totalBytes: 0,
                metadataStatus: metadataStatus,
                errorMessage: error.localizedDescription,
                trackers: MagnetURI.parseTrackers(from: source)
            )
        }
    }

    private func nativeMagnetPreview(source: String, suggestedFilename: String?) async throws -> TorrentMetadataPreview {
        #if canImport(CSwiftGetXLibtorrent)
        guard let previewer = LibtorrentMetadataPreviewer() else {
            throw TorrentMetadataError.nativeEngineUnavailable
        }
        let preview = try await previewer.preview(magnet: source)
        return TorrentMetadataPreview(
            source: source,
            kind: .torrentMagnet,
            displayName: suggestedFilename?.nonEmpty ?? preview.displayName?.nonEmpty ?? SourceParser.displayName(for: source, kind: .torrentMagnet),
            resolvedTorrentFilePath: nil,
            files: preview.files,
            totalBytes: preview.files.reduce(0) { $0 + $1.size },
            metadataStatus: .available,
            errorMessage: nil,
            trackers: MagnetURI.parseTrackers(from: source)
        )
        #else
        throw TorrentMetadataError.nativeEngineUnavailable
        #endif
    }

    private func copyTorrentFileToCache(_ sourceURL: URL) throws -> URL {
        let filename = sourceURL.lastPathComponent.isEmpty
            ? L10n.string("default_torrent_task_filename")
            : sourceURL.lastPathComponent
        let cachedURL = try cacheURL(filename: filename, preferredExtension: "torrent")
        try? fileManager.removeItem(at: cachedURL)
        try fileManager.copyItem(at: sourceURL, to: cachedURL)
        return cachedURL
    }

    private func cacheURL(filename: String, preferredExtension: String) throws -> URL {
        let directory = try torrentCacheDirectory()
        let sanitized = SourceParser.sanitizeFilename(filename).nonEmpty ?? L10n.string("default_torrent_task_filename")
        let baseURL = directory.appendingPathComponent(sanitized)
        let url = baseURL.pathExtension.isEmpty
            ? baseURL.appendingPathExtension(preferredExtension)
            : baseURL
        return fileManager.uniqueFileURL(for: url)
    }

    private func torrentCacheDirectory() throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("SwiftGetX/Torrents", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

enum TorrentMetadataError: LocalizedError, Equatable {
    case invalidTorrentSource
    case httpStatus(Int)
    case metadataTimeout
    case nativeEngineUnavailable
    case invalidTorrentFile
    case invalidBencode

    var errorDescription: String? {
        switch self {
        case .invalidTorrentSource:
            L10n.string("error_invalid_torrent_source")
        case .httpStatus(let status):
            L10n.string("error_server_status", status)
        case .metadataTimeout:
            L10n.string("error_torrent_metadata_timeout")
        case .nativeEngineUnavailable:
            L10n.string("torrent_native_engine_unavailable")
        case .invalidTorrentFile:
            L10n.string("error_invalid_torrent_file")
        case .invalidBencode:
            L10n.string("error_invalid_bencode")
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
