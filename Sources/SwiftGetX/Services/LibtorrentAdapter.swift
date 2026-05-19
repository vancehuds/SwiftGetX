import Foundation

#if canImport(CSwiftGetXLibtorrent)
import CSwiftGetXLibtorrent

actor LibtorrentAdapter: TorrentEngineAdapter {
    private let sessionBox: LibtorrentSessionBox
    private var handleIDs: [UUID: Int32] = [:]
    private var pollingTasks: [UUID: Task<Void, Never>] = [:]

    init?() {
        guard let sessionBox = LibtorrentSessionBox() else { return nil }
        self.sessionBox = sessionBox
    }

    deinit {
        for task in pollingTasks.values {
            task.cancel()
        }
    }

    func start(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws {
        let session = sessionBox.raw
        let selected = request.selectedFileIndexes.map(Int32.init)
        let handleID: Int32

        if request.source.hasPrefix("magnet:") {
            handleID = request.source.withCString { magnet in
                request.savePath.withCString { savePath in
                    selected.withUnsafeBufferPointer { buffer in
                        sgx_libtorrent_add_magnet(
                            session,
                            magnet,
                            savePath,
                            buffer.baseAddress,
                            Int32(buffer.count)
                        )
                    }
                }
            }
        } else {
            handleID = request.source.withCString { torrentPath in
                request.savePath.withCString { savePath in
                    selected.withUnsafeBufferPointer { buffer in
                        sgx_libtorrent_add_torrent_file(
                            session,
                            torrentPath,
                            savePath,
                            buffer.baseAddress,
                            Int32(buffer.count)
                        )
                    }
                }
            }
        }

        guard handleID >= 0 else {
            throw LibtorrentAdapterError.nativeError(lastError())
        }

        handleIDs[request.id] = handleID
        pollingTasks[request.id]?.cancel()
        pollingTasks[request.id] = Task { [weak self] in
            await self?.poll(requestID: request.id, handleID: handleID, onSnapshot: onSnapshot)
        }
    }

    func pause(id: UUID) async {
        guard let handleID = handleIDs[id] else { return }
        sgx_libtorrent_pause(sessionBox.raw, handleID)
    }

    func cancel(id: UUID) async {
        guard let handleID = handleIDs[id] else { return }
        sgx_libtorrent_remove(sessionBox.raw, handleID, 0)
        pollingTasks[id]?.cancel()
        pollingTasks[id] = nil
        handleIDs[id] = nil
    }

    func remove(id: UUID, deletingFiles: Bool) async {
        guard let handleID = handleIDs[id] else { return }
        sgx_libtorrent_remove(sessionBox.raw, handleID, deletingFiles ? 1 : 0)
        pollingTasks[id]?.cancel()
        pollingTasks[id] = nil
        handleIDs[id] = nil
    }

    func recheck(id: UUID) async {
        guard let handleID = handleIDs[id] else { return }
        sgx_libtorrent_recheck(sessionBox.raw, handleID)
    }

    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async {
        sgx_libtorrent_set_speed_limits(
            sessionBox.raw,
            Int32(clamping: downloadBytesPerSecond),
            Int32(clamping: uploadBytesPerSecond)
        )
    }

    func setFileSelection(id: UUID, selectedFileIndexes: [Int]) async {
        guard let handleID = handleIDs[id] else { return }
        let selected = selectedFileIndexes.map(Int32.init)
        selected.withUnsafeBufferPointer { buffer in
            sgx_libtorrent_set_file_selection(
                sessionBox.raw,
                handleID,
                buffer.baseAddress,
                Int32(buffer.count)
            )
        }
    }

    private func poll(
        requestID: UUID,
        handleID: Int32,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async {
        while !Task.isCancelled {
            var nativeStatus = SGXTorrentStatus()
            guard sgx_libtorrent_get_status(sessionBox.raw, handleID, &nativeStatus) != 0 else {
                try? await Task.sleep(for: .seconds(1))
                continue
            }

            let files = copyFiles(session: sessionBox.raw, handleID: handleID)
            let completed = nativeStatus.total_wanted > 0
                && nativeStatus.total_wanted_done >= nativeStatus.total_wanted
            let status: DownloadStatus = completed ? .completed : .running
            let connectionSummary = "\(nativeStatus.num_peers) peers · ratio \(String(format: "%.2f", nativeStatus.share_ratio))"

            onSnapshot(
                DownloadSnapshot(
                    taskID: requestID,
                    status: status,
                    totalBytes: nativeStatus.total_wanted,
                    downloadedBytes: nativeStatus.total_wanted_done,
                    speedBytesPerSecond: nativeStatus.download_rate,
                    etaSeconds: nativeStatus.download_rate > 0
                        ? TimeInterval(max(0, nativeStatus.total_wanted - nativeStatus.total_wanted_done) / nativeStatus.download_rate)
                        : nil,
                    errorMessage: nil,
                    supportsResume: true,
                    eTag: nil,
                    lastModified: nil,
                    torrentFiles: files,
                    connectionSummary: connectionSummary
                )
            )

            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func copyFiles(session: OpaquePointer, handleID: Int32) -> [TorrentFile] {
        let capacity = 4096
        let buffer = UnsafeMutablePointer<SGXTorrentFile>.allocate(capacity: capacity)
        defer {
            buffer.deallocate()
        }

        let count = Int(sgx_libtorrent_copy_files(session, handleID, buffer, Int32(capacity)))
        guard count > 0 else { return [] }
        defer {
            sgx_libtorrent_free_file_paths(buffer, Int32(count))
        }

        return (0..<count).map { index in
            let file = buffer[index]
            return TorrentFile(
                index: Int(file.index),
                path: file.path.map { String(cString: $0) } ?? "file-\(index)",
                size: file.size,
                priority: Int(file.priority),
                progress: Double(file.progress)
            )
        }
    }

    private func lastError() -> String {
        guard let message = sgx_libtorrent_last_error(sessionBox.raw) else {
            return "Unknown libtorrent error"
        }
        return String(cString: message)
    }
}

private final class LibtorrentSessionBox: @unchecked Sendable {
    let raw: OpaquePointer

    init?() {
        guard let raw = sgx_libtorrent_session_create() else { return nil }
        self.raw = raw
    }

    deinit {
        sgx_libtorrent_session_destroy(raw)
    }
}

enum LibtorrentAdapterError: LocalizedError {
    case sessionUnavailable
    case nativeError(String)

    var errorDescription: String? {
        switch self {
        case .sessionUnavailable:
            "libtorrent session is unavailable"
        case .nativeError(let message):
            message
        }
    }
}
#endif
