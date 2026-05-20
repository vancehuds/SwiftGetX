import Foundation

#if canImport(CSwiftGetXLibtorrent)
import CSwiftGetXLibtorrent

actor LibtorrentAdapter: TorrentEngineAdapter {
    private let sessionBox: LibtorrentSessionBox
    private var handleIDs: [UUID: Int32] = [:]
    private var pollingTasks: [UUID: Task<Void, Never>] = [:]
    private var selectedFileIndexes: [UUID: [Int]] = [:]

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
        if let handleID = handleIDs[request.id] {
            rememberFileSelection(for: request)
            if request.hasExplicitFileSelection {
                applyFileSelection(handleID: handleID, selectedFileIndexes: request.selectedFileIndexes)
            }
            sgx_libtorrent_resume(sessionBox.raw, handleID)
            startPolling(request: request, handleID: handleID, onSnapshot: onSnapshot)
            return
        }

        let session = sessionBox.raw
        let selected = request.selectedFileIndexes.map(Int32.init)
        let handleID: Int32

        if request.displaySource.hasPrefix("magnet:") {
            handleID = request.displaySource.withCString { magnet in
                request.savePath.withCString { savePath in
                    selected.withUnsafeBufferPointer { buffer in
                        sgx_libtorrent_add_magnet(
                            session,
                            magnet,
                            savePath,
                            request.hasExplicitFileSelection ? buffer.baseAddress : nil,
                            request.hasExplicitFileSelection ? Int32(buffer.count) : -1
                        )
                    }
                }
            }
        } else {
            let torrentPath = request.resolvedTorrentFilePath ?? request.displaySource
            handleID = torrentPath.withCString { torrentPath in
                request.savePath.withCString { savePath in
                    selected.withUnsafeBufferPointer { buffer in
                        sgx_libtorrent_add_torrent_file(
                            session,
                            torrentPath,
                            savePath,
                            request.hasExplicitFileSelection ? buffer.baseAddress : nil,
                            request.hasExplicitFileSelection ? Int32(buffer.count) : -1
                        )
                    }
                }
            }
        }

        guard handleID >= 0 else {
            throw LibtorrentAdapterError.nativeError(lastError())
        }

        handleIDs[request.id] = handleID
        rememberFileSelection(for: request)
        startPolling(request: request, handleID: handleID, onSnapshot: onSnapshot)
    }

    func resume(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async throws {
        try await start(request, onSnapshot: onSnapshot)
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
        selectedFileIndexes[id] = nil
    }

    func remove(id: UUID, deletingFiles: Bool) async {
        guard let handleID = handleIDs[id] else { return }
        sgx_libtorrent_remove(sessionBox.raw, handleID, deletingFiles ? 1 : 0)
        pollingTasks[id]?.cancel()
        pollingTasks[id] = nil
        handleIDs[id] = nil
        selectedFileIndexes[id] = nil
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
        self.selectedFileIndexes[id] = selectedFileIndexes
        applyFileSelection(handleID: handleID, selectedFileIndexes: selectedFileIndexes)
    }

    private func startPolling(
        request: TorrentStartRequest,
        handleID: Int32,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) {
        pollingTasks[request.id]?.cancel()
        pollingTasks[request.id] = Task { [weak self] in
            await self?.poll(request: request, handleID: handleID, onSnapshot: onSnapshot)
        }
    }

    private func rememberFileSelection(for request: TorrentStartRequest) {
        if request.hasExplicitFileSelection {
            selectedFileIndexes[request.id] = request.selectedFileIndexes
        } else {
            selectedFileIndexes[request.id] = nil
        }
    }

    private func applyFileSelection(handleID: Int32, selectedFileIndexes: [Int]) {
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
        request: TorrentStartRequest,
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
            if nativeStatus.has_metadata != 0,
               let selected = selectedFileIndexes[request.id] {
                applyFileSelection(handleID: handleID, selectedFileIndexes: selected)
            }

            if nativeStatus.has_error != 0 {
                onSnapshot(
                    DownloadSnapshot(
                        taskID: request.id,
                        status: .failed,
                        totalBytes: max(nativeStatus.total_wanted, 0),
                        downloadedBytes: max(nativeStatus.total_wanted_done, 0),
                        speedBytesPerSecond: 0,
                        etaSeconds: nil,
                        errorMessage: lastError(),
                        supportsResume: true,
                        eTag: nil,
                        lastModified: nil,
                        torrentFiles: files,
                        connectionSummary: connectionSummary(from: nativeStatus),
                        torrentMetadataStatus: metadataStatus(from: nativeStatus),
                        torrentConnection: connectionInfo(from: nativeStatus)
                    )
                )
                pollingTasks[request.id] = nil
                handleIDs[request.id] = nil
                selectedFileIndexes[request.id] = nil
                return
            }

            if nativeStatus.is_seeding != 0,
               request.stopSeedingAtRatio > 0,
               Double(nativeStatus.share_ratio) >= request.stopSeedingAtRatio {
                sgx_libtorrent_pause(sessionBox.raw, handleID)
                onSnapshot(
                    DownloadSnapshot(
                        taskID: request.id,
                        status: .completed,
                        totalBytes: max(nativeStatus.total_wanted, 0),
                        downloadedBytes: max(nativeStatus.total_wanted_done, 0),
                        speedBytesPerSecond: 0,
                        etaSeconds: nil,
                        errorMessage: nil,
                        supportsResume: true,
                        eTag: nil,
                        lastModified: nil,
                        torrentFiles: files,
                        connectionSummary: connectionSummary(from: nativeStatus),
                        torrentMetadataStatus: metadataStatus(from: nativeStatus),
                        torrentConnection: connectionInfo(from: nativeStatus)
                    )
                )
                pollingTasks[request.id] = nil
                return
            }

            let completed = nativeStatus.total_wanted > 0
                && nativeStatus.total_wanted_done >= nativeStatus.total_wanted
            let status = status(from: nativeStatus, completed: completed)

            onSnapshot(
                DownloadSnapshot(
                    taskID: request.id,
                    status: status,
                    totalBytes: max(nativeStatus.total_wanted, 0),
                    downloadedBytes: max(nativeStatus.total_wanted_done, 0),
                    speedBytesPerSecond: status == .running ? nativeStatus.download_rate : 0,
                    etaSeconds: nativeStatus.download_rate > 0
                        ? TimeInterval(max(0, nativeStatus.total_wanted - nativeStatus.total_wanted_done) / nativeStatus.download_rate)
                        : nil,
                    errorMessage: nil,
                    supportsResume: true,
                    eTag: nil,
                    lastModified: nil,
                    torrentFiles: files,
                    connectionSummary: connectionSummary(from: nativeStatus),
                    torrentMetadataStatus: metadataStatus(from: nativeStatus),
                    torrentConnection: connectionInfo(from: nativeStatus)
                )
            )

            if status == .completed {
                pollingTasks[request.id] = nil
                return
            }

            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func status(from nativeStatus: SGXTorrentStatus, completed: Bool) -> DownloadStatus {
        if nativeStatus.is_paused != 0 {
            return .paused
        }
        if nativeStatus.state == 1 || nativeStatus.state == 2 {
            return .verifying
        }
        if completed && nativeStatus.is_seeding == 0 {
            return .completed
        }
        return .running
    }

    private func metadataStatus(from nativeStatus: SGXTorrentStatus) -> TorrentMetadataStatus {
        nativeStatus.has_metadata != 0 ? .available : .fetching
    }

    private func connectionInfo(from nativeStatus: SGXTorrentStatus) -> TorrentConnectionInfo {
        TorrentConnectionInfo(
            metadataStatus: metadataStatus(from: nativeStatus),
            peerCount: Int(nativeStatus.num_peers),
            downloadRate: nativeStatus.download_rate,
            uploadRate: nativeStatus.upload_rate,
            shareRatio: Double(nativeStatus.share_ratio),
            distributedCopies: Double(nativeStatus.distributed_copies),
            isDHTEnabled: true,
            isPEXEnabled: true,
            localPortDescription: L10n.string("connection_port_ready"),
            nativeEngineAvailable: true
        )
    }

    private func connectionSummary(from nativeStatus: SGXTorrentStatus) -> String {
        let downloadSpeed = Self.speedLabel(nativeStatus.download_rate)
        let uploadSpeed = Self.speedLabel(nativeStatus.upload_rate)
        return "\(nativeStatus.num_peers) peers · ↓ \(downloadSpeed) · ↑ \(uploadSpeed) · ratio \(String(format: "%.2f", nativeStatus.share_ratio))"
    }

    private nonisolated static func speedLabel(_ bytesPerSecond: Int64) -> String {
        let value = Double(max(bytesPerSecond, 0))
        if value >= 1_000_000_000 {
            return String(format: "%.1f GB/s", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1f MB/s", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0f KB/s", value / 1_000)
        }
        return "\(Int(value)) B/s"
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

struct LibtorrentMagnetPreview: Sendable {
    var displayName: String?
    var files: [TorrentFile]
}

actor LibtorrentMetadataPreviewer {
    private let sessionBox: LibtorrentSessionBox

    init?() {
        guard let sessionBox = LibtorrentSessionBox() else { return nil }
        self.sessionBox = sessionBox
    }

    func preview(magnet: String) async throws -> LibtorrentMagnetPreview {
        let handleID = magnet.withCString { magnet in
            NSTemporaryDirectory().withCString { savePath in
                sgx_libtorrent_add_magnet(sessionBox.raw, magnet, savePath, nil, 0)
            }
        }

        guard handleID >= 0 else {
            throw LibtorrentAdapterError.nativeError(lastError())
        }
        defer {
            sgx_libtorrent_remove(sessionBox.raw, handleID, 1)
        }

        while !Task.isCancelled {
            if sgx_libtorrent_has_metadata(sessionBox.raw, handleID) != 0 {
                let files = copyFiles(handleID: handleID)
                return LibtorrentMagnetPreview(
                    displayName: SourceParser.displayName(for: magnet, kind: .torrentMagnet),
                    files: files
                )
            }
            try await Task.sleep(for: .milliseconds(500))
        }

        throw CancellationError()
    }

    private func copyFiles(handleID: Int32) -> [TorrentFile] {
        let capacity = 4096
        let buffer = UnsafeMutablePointer<SGXTorrentFile>.allocate(capacity: capacity)
        defer {
            buffer.deallocate()
        }

        let count = Int(sgx_libtorrent_copy_files(sessionBox.raw, handleID, buffer, Int32(capacity)))
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
#endif
