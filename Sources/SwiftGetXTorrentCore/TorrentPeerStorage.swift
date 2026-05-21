import Foundation
import Darwin

public struct TorrentPeerWorkspace: @unchecked Sendable {
    public var metainfo: TorrentMetainfo
    public var layout: TorrentContentLayout
    public var resumeStateURL: URL
    public var fileManager: FileManager

    public init(
        metainfo: TorrentMetainfo,
        layout: TorrentContentLayout,
        resumeStateURL: URL,
        fileManager: FileManager = .default
    ) {
        self.metainfo = metainfo
        self.layout = layout
        self.resumeStateURL = resumeStateURL
        self.fileManager = fileManager
    }

    public var contentStorage: TorrentContentStorage {
        TorrentContentStorage(layout: layout, fileManager: fileManager)
    }

    public func makeEmptyResumeState(updatedAt: Date = .now) throws -> TorrentCoreResumeState {
        try TorrentCoreResumeState.empty(for: metainfo, layout: layout, updatedAt: updatedAt)
    }

    public func loadResumeState() throws -> TorrentCoreResumeState? {
        guard fileManager.fileExists(atPath: resumeStateURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: resumeStateURL)
        return try TorrentCoreResumeState.decodeJSON(
            data,
            expectedInfoHashV1Hex: metainfo.infoHashV1Hex,
            expectedLayout: layout
        )
    }

    public func saveResumeState(_ state: TorrentCoreResumeState) throws {
        try state.validate(
            expectedInfoHashV1Hex: metainfo.infoHashV1Hex,
            expectedLayout: layout
        )
        try fileManager.createDirectory(
            at: resumeStateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try state.encodedJSON(prettyPrinted: true).write(to: resumeStateURL, options: .atomic)
    }

    public func deletePartialData() throws {
        let storage = contentStorage
        try storage.deletePartialData()
        if fileManager.fileExists(atPath: resumeStateURL.path) {
            try fileManager.removeItem(at: resumeStateURL)
        }
    }
}

public final class TorrentContentStorage: @unchecked Sendable {
    public var layout: TorrentContentLayout
    public var fileManager: FileManager

    public init(layout: TorrentContentLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    public func write(_ data: Data, atGlobalOffset globalOffset: Int64) throws {
        guard globalOffset >= 0 else {
            throw TorrentContentLayoutError.totalLengthOverflow
        }
        guard !data.isEmpty else { return }
        guard Int64(data.count) <= layout.totalLength - globalOffset else {
            throw TorrentContentLayoutError.totalLengthOverflow
        }

        var remaining = data
        var currentOffset = globalOffset
        while !remaining.isEmpty {
            guard let file = layout.file(containingGlobalOffset: currentOffset) else {
                throw TorrentContentLayoutError.totalLengthOverflow
            }
            let fileOffset = currentOffset - file.offset
            let remainingInFile = Int(file.length - fileOffset)
            let chunkCount = min(remaining.count, remainingInFile)
            let chunk = remaining.prefix(chunkCount)
            try write(chunk, to: file.fileURL, fileOffset: fileOffset)
            remaining.removeFirst(chunkCount)
            currentOffset += Int64(chunkCount)
        }
    }

    public func write(piece data: Data, pieceIndex: Int, pieceLength: Int64) throws {
        let offset = Int64(pieceIndex) * pieceLength
        try write(data, atGlobalOffset: offset)
    }

    public func deletePartialData() throws {
        if layout.isMultiFile {
            if fileManager.fileExists(atPath: layout.contentRoot.path) {
                try fileManager.removeItem(at: layout.contentRoot)
            }
            return
        }

        guard let finalFileURL = layout.finalFileURL else { return }
        if fileManager.fileExists(atPath: finalFileURL.path) {
            try fileManager.removeItem(at: finalFileURL)
        }
    }

    private func write(_ bytes: Data.SubSequence, to fileURL: URL, fileOffset: Int64) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }

        let fd = open(fileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard fd >= 0 else {
            throw makePOSIXError()
        }
        defer { close(fd) }

        let payload = Data(bytes)
        try payload.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var remaining = buffer.count
            var written: Int = 0
            while remaining > 0 {
                let result = pwrite(
                    fd,
                    baseAddress.advanced(by: written),
                    remaining,
                    off_t(fileOffset + Int64(written))
                )
                if result < 0 {
                    throw makePOSIXError()
                }
                guard result > 0 else {
                    throw TorrentContentLayoutError.totalLengthOverflow
                }
                written += result
                remaining -= result
            }
        }
    }

    private func makePOSIXError() -> Error {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
