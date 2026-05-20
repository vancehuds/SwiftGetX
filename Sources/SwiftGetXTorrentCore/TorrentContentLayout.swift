import Foundation

public enum TorrentContentPriority: Int, Codable, CaseIterable, Sendable {
    case skip = 0
    case normal = 1
    case high = 2
    case maximum = 7
}

public enum TorrentContentLayoutError: Error, Equatable, Sendable, LocalizedError {
    case invalidSaveDirectory
    case missingFiles
    case invalidPathComponent(fileIndex: Int, component: String)
    case pathTooLong(fileIndex: Int, path: String)
    case duplicatePath(fileIndex: Int, path: String)
    case nonContiguousFileIndex(expected: Int, actual: Int)
    case totalLengthOverflow

    public var errorDescription: String? {
        switch self {
        case .invalidSaveDirectory:
            "Torrent save directory must be a non-empty file URL."
        case .missingFiles:
            "Torrent content layout requires at least one file."
        case .invalidPathComponent(let fileIndex, let component):
            "Torrent file \(fileIndex) contains an unsafe path component: \(component)."
        case .pathTooLong(let fileIndex, let path):
            "Torrent file \(fileIndex) path is too long: \(path)."
        case .duplicatePath(let fileIndex, let path):
            "Torrent file \(fileIndex) duplicates another path: \(path)."
        case .nonContiguousFileIndex(let expected, let actual):
            "Torrent file index \(actual) is not contiguous; expected \(expected)."
        case .totalLengthOverflow:
            "Torrent content length exceeds supported bounds."
        }
    }
}

public struct TorrentContentFile: Codable, Equatable, Identifiable, Sendable {
    public var index: Int
    public var relativePath: String
    public var pathComponents: [String]
    public var fileURL: URL
    public var offset: Int64
    public var length: Int64
    public var priority: TorrentContentPriority

    public var id: Int { index }

    public var endOffset: Int64 {
        offset + length
    }
}

public struct TorrentContentLayout: Codable, Equatable, Sendable {
    public static let defaultMaximumPathBytes = 4_096
    public static let defaultMaximumPathComponentBytes = 255

    public var saveDirectory: URL
    public var outputName: String
    public var contentRoot: URL
    public var files: [TorrentContentFile]
    public var totalLength: Int64
    public var isMultiFile: Bool

    public var finalFileURL: URL? {
        isMultiFile ? nil : files.first?.fileURL
    }

    public init(
        metainfo: TorrentMetainfo,
        saveDirectory: URL,
        outputName: String? = nil,
        priorities: [Int: TorrentContentPriority] = [:],
        maximumPathBytes: Int = Self.defaultMaximumPathBytes
    ) throws {
        try self.init(
            files: metainfo.files,
            saveDirectory: saveDirectory,
            outputName: outputName,
            isMultiFile: metainfo.isMultiFile,
            priorities: priorities,
            maximumPathBytes: maximumPathBytes
        )
    }

    public init(
        files torrentFiles: [TorrentFileInfo],
        saveDirectory: URL,
        outputName: String? = nil,
        isMultiFile: Bool? = nil,
        priorities: [Int: TorrentContentPriority] = [:],
        maximumPathBytes: Int = Self.defaultMaximumPathBytes
    ) throws {
        let normalizedSaveDirectory = try Self.normalizedSaveDirectory(saveDirectory)
        let sortedFiles = torrentFiles.sorted(by: { $0.index < $1.index })
        guard !sortedFiles.isEmpty else {
            throw TorrentContentLayoutError.missingFiles
        }

        for (expectedIndex, file) in sortedFiles.enumerated() where file.index != expectedIndex {
            throw TorrentContentLayoutError.nonContiguousFileIndex(
                expected: expectedIndex,
                actual: file.index
            )
        }

        let usesMultiFileRoot = isMultiFile ?? Self.inferMultiFileLayout(from: sortedFiles)
        let torrentRootName = usesMultiFileRoot ? sortedFiles[0].pathComponents[0] : nil
        let resolvedOutputName = try Self.outputName(
            explicitOutputName: outputName,
            torrentRootName: torrentRootName,
            firstFile: sortedFiles[0]
        )
        let contentRoot = usesMultiFileRoot
            ? normalizedSaveDirectory.appendingPathComponent(resolvedOutputName, isDirectory: true)
            : normalizedSaveDirectory

        var offset: Int64 = 0
        var seenPaths = Set<String>()
        var layoutFiles = [TorrentContentFile]()
        layoutFiles.reserveCapacity(sortedFiles.count)

        for file in sortedFiles {
            let rawComponents = try Self.validatedComponents(
                file.pathComponents,
                fileIndex: file.index
            )
            let components: [String]
            if usesMultiFileRoot {
                guard rawComponents.first == torrentRootName else {
                    throw TorrentContentLayoutError.invalidPathComponent(
                        fileIndex: file.index,
                        component: rawComponents.first ?? ""
                    )
                }
                components = Array(rawComponents.dropFirst())
                guard !components.isEmpty else {
                    throw TorrentContentLayoutError.invalidPathComponent(fileIndex: file.index, component: "")
                }
            } else {
                guard rawComponents.count == 1 else {
                    throw TorrentContentLayoutError.invalidPathComponent(
                        fileIndex: file.index,
                        component: rawComponents.dropFirst().first ?? rawComponents.first ?? ""
                    )
                }
                components = [resolvedOutputName]
            }

            let relativePath = components.joined(separator: "/")
            guard relativePath.utf8.count <= maximumPathBytes else {
                throw TorrentContentLayoutError.pathTooLong(fileIndex: file.index, path: relativePath)
            }
            let normalizedKey = relativePath.precomposedStringWithCanonicalMapping.lowercased()
            guard seenPaths.insert(normalizedKey).inserted else {
                throw TorrentContentLayoutError.duplicatePath(fileIndex: file.index, path: relativePath)
            }
            guard file.length >= 0, Int64.max - offset >= file.length else {
                throw TorrentContentLayoutError.totalLengthOverflow
            }

            let fileURL = Self.fileURL(contentRoot: contentRoot, components: components)
            layoutFiles.append(
                TorrentContentFile(
                    index: file.index,
                    relativePath: relativePath,
                    pathComponents: components,
                    fileURL: fileURL,
                    offset: offset,
                    length: file.length,
                    priority: priorities[file.index] ?? .normal
                )
            )
            offset += file.length
        }

        self.saveDirectory = normalizedSaveDirectory
        self.outputName = resolvedOutputName
        self.contentRoot = contentRoot
        self.files = layoutFiles
        self.totalLength = offset
        self.isMultiFile = usesMultiFileRoot
    }

    public func file(containingGlobalOffset globalOffset: Int64) -> TorrentContentFile? {
        guard globalOffset >= 0, globalOffset < totalLength else { return nil }
        return files.first { globalOffset >= $0.offset && globalOffset < $0.endOffset }
    }

    private static func normalizedSaveDirectory(_ url: URL) throws -> URL {
        guard url.isFileURL, !url.path.isEmpty else {
            throw TorrentContentLayoutError.invalidSaveDirectory
        }
        return url.standardizedFileURL
    }

    private static func validatedComponents(_ components: [String], fileIndex: Int) throws -> [String] {
        guard !components.isEmpty else {
            throw TorrentContentLayoutError.invalidPathComponent(fileIndex: fileIndex, component: "")
        }

        return try components.map { component in
            guard isSafeComponent(component) else {
                throw TorrentContentLayoutError.invalidPathComponent(fileIndex: fileIndex, component: component)
            }
            guard component.utf8.count <= defaultMaximumPathComponentBytes else {
                throw TorrentContentLayoutError.pathTooLong(fileIndex: fileIndex, path: component)
            }
            return component
        }
    }

    private static func isSafeComponent(_ component: String) -> Bool {
        guard !component.isEmpty,
              component != ".",
              component != "..",
              !component.hasPrefix("/"),
              !component.hasPrefix("~"),
              component.rangeOfCharacter(from: .torrentPathControlCharacters) == nil,
              component.range(of: #"[\\/]"#, options: .regularExpression) == nil
        else {
            return false
        }
        return true
    }

    private static func inferMultiFileLayout(from files: [TorrentFileInfo]) -> Bool {
        guard let root = files.first?.pathComponents.first,
              !root.isEmpty
        else { return false }
        return files.contains { $0.pathComponents.count > 1 }
            && files.allSatisfy { $0.pathComponents.first == root }
    }

    private static func outputName(
        explicitOutputName: String?,
        torrentRootName: String?,
        firstFile: TorrentFileInfo
    ) throws -> String {
        let candidate = explicitOutputName ?? torrentRootName ?? firstFile.pathComponents.first ?? firstFile.path
        guard isSafeComponent(candidate) else {
            throw TorrentContentLayoutError.invalidPathComponent(fileIndex: firstFile.index, component: candidate)
        }
        guard candidate.utf8.count <= defaultMaximumPathComponentBytes else {
            throw TorrentContentLayoutError.pathTooLong(fileIndex: firstFile.index, path: candidate)
        }
        return candidate
    }

    private static func fileURL(contentRoot: URL, components: [String]) -> URL {
        components.enumerated().reduce(contentRoot) { partialURL, pair in
            partialURL.appendingPathComponent(
                pair.element,
                isDirectory: pair.offset < components.count - 1
            )
        }
    }
}

private extension CharacterSet {
    static let torrentPathControlCharacters = CharacterSet.controlCharacters
        .union(CharacterSet(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}"))
}
