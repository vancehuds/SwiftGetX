import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftGetXCore

struct TorrentMetadataPreview: Equatable, Sendable {
    var source: String
    var kind: DownloadKind
    var displayName: String
    var resolvedTorrentFilePath: String?
    var files: [TorrentFile]
    var totalBytes: Int64
    var metadataStatus: TorrentMetadataStatus
    var errorMessage: String?
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
            let metadata = try TorrentFileParser.parse(url: cachedURL)
            let displayName = suggestedFilename?.nonEmpty
                ?? metadata.name.nonEmpty
                ?? SourceParser.displayName(for: source, kind: .torrentFile)

            return TorrentMetadataPreview(
                source: source,
                kind: .torrentFile,
                displayName: displayName,
                resolvedTorrentFilePath: cachedURL.path,
                files: metadata.files,
                totalBytes: metadata.totalBytes,
                metadataStatus: .available,
                errorMessage: nil
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
                errorMessage: error.localizedDescription
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
            errorMessage: nil
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

struct ParsedTorrentMetadata: Equatable, Sendable {
    var name: String
    var files: [TorrentFile]

    var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.size }
    }
}

enum TorrentFileParser {
    static func parse(url: URL) throws -> ParsedTorrentMetadata {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> ParsedTorrentMetadata {
        let value = try BencodeParser(data: data).parse()
        guard case .dictionary(let root) = value,
              let info = root["info"],
              case .dictionary(let infoDictionary) = info
        else {
            throw TorrentMetadataError.invalidTorrentFile
        }

        let name = stringValue(infoDictionary["name"]) ?? stringValue(infoDictionary["name.utf-8"]) ?? "torrent"

        if case .list(let fileValues)? = infoDictionary["files"] {
            let files = fileValues.enumerated().compactMap { offset, value -> TorrentFile? in
                guard case .dictionary(let fileDictionary) = value,
                      let length = integerValue(fileDictionary["length"])
                else {
                    return nil
                }

                let pathComponents = pathComponents(from: fileDictionary["path.utf-8"])
                    ?? pathComponents(from: fileDictionary["path"])
                    ?? ["file-\(offset)"]
                let path = ([name] + pathComponents).joined(separator: "/")
                return TorrentFile(index: offset, path: path, size: length, progress: 0)
            }

            guard !files.isEmpty else { throw TorrentMetadataError.invalidTorrentFile }
            return ParsedTorrentMetadata(name: name, files: files)
        }

        guard let length = integerValue(infoDictionary["length"]) else {
            throw TorrentMetadataError.invalidTorrentFile
        }

        return ParsedTorrentMetadata(
            name: name,
            files: [TorrentFile(index: 0, path: name, size: length, progress: 0)]
        )
    }

    private static func integerValue(_ value: BencodeValue?) -> Int64? {
        guard case .integer(let integer)? = value else { return nil }
        return integer
    }

    private static func stringValue(_ value: BencodeValue?) -> String? {
        guard case .data(let data)? = value else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func pathComponents(from value: BencodeValue?) -> [String]? {
        guard case .list(let components)? = value else { return nil }
        let strings = components.compactMap(stringValue)
        return strings.isEmpty ? nil : strings
    }
}

enum BencodeValue: Equatable, Sendable {
    case integer(Int64)
    case data(Data)
    case list([BencodeValue])
    case dictionary([String: BencodeValue])
}

struct BencodeParser {
    private let bytes: [UInt8]
    private var index = 0

    init(data: Data) {
        bytes = Array(data)
    }

    func parse() throws -> BencodeValue {
        var parser = self
        let value = try parser.parseValue()
        guard parser.index == parser.bytes.count else {
            throw TorrentMetadataError.invalidBencode
        }
        return value
    }

    private mutating func parseValue() throws -> BencodeValue {
        guard index < bytes.count else { throw TorrentMetadataError.invalidBencode }
        let byte = bytes[index]
        if byte == UInt8(ascii: "i") {
            return try parseInteger()
        }
        if byte == UInt8(ascii: "l") {
            return try parseList()
        }
        if byte == UInt8(ascii: "d") {
            return try parseDictionary()
        }
        if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") {
            return try parseData()
        }
        throw TorrentMetadataError.invalidBencode
    }

    private mutating func parseInteger() throws -> BencodeValue {
        index += 1
        let start = index
        while index < bytes.count, bytes[index] != UInt8(ascii: "e") {
            index += 1
        }
        guard index < bytes.count,
              let integer = Int64(String(decoding: bytes[start..<index], as: UTF8.self))
        else {
            throw TorrentMetadataError.invalidBencode
        }
        index += 1
        return .integer(integer)
    }

    private mutating func parseData() throws -> BencodeValue {
        let lengthStart = index
        while index < bytes.count, bytes[index] != UInt8(ascii: ":") {
            guard bytes[index] >= UInt8(ascii: "0") && bytes[index] <= UInt8(ascii: "9") else {
                throw TorrentMetadataError.invalidBencode
            }
            index += 1
        }
        guard index < bytes.count,
              let length = Int(String(decoding: bytes[lengthStart..<index], as: UTF8.self))
        else {
            throw TorrentMetadataError.invalidBencode
        }
        index += 1
        guard length >= 0, index + length <= bytes.count else {
            throw TorrentMetadataError.invalidBencode
        }
        let data = Data(bytes[index..<index + length])
        index += length
        return .data(data)
    }

    private mutating func parseList() throws -> BencodeValue {
        index += 1
        var values = [BencodeValue]()
        while index < bytes.count, bytes[index] != UInt8(ascii: "e") {
            values.append(try parseValue())
        }
        guard index < bytes.count else { throw TorrentMetadataError.invalidBencode }
        index += 1
        return .list(values)
    }

    private mutating func parseDictionary() throws -> BencodeValue {
        index += 1
        var values = [String: BencodeValue]()
        while index < bytes.count, bytes[index] != UInt8(ascii: "e") {
            guard case .data(let keyData) = try parseData(),
                  let key = String(data: keyData, encoding: .utf8)
            else {
                throw TorrentMetadataError.invalidBencode
            }
            values[key] = try parseValue()
        }
        guard index < bytes.count else { throw TorrentMetadataError.invalidBencode }
        index += 1
        return .dictionary(values)
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
