import Foundation

#if canImport(CSwiftGetXLibtorrent)
import CSwiftGetXLibtorrent

actor LibtorrentAdapter: TorrentEngineAdapter {
    nonisolated var engineKind: TorrentEngineKind { .libtorrent }
    nonisolated var engineStatus: TorrentEngineStatus { .available }

    private let sessionBox: LibtorrentSessionBox
    private var handleIDs: [UUID: Int32] = [:]
    private var pollingTasks: [UUID: Task<Void, Never>] = [:]
    private var selectedFileIndexes: [UUID: [Int]] = [:]
    private var filePriorities: [UUID: [Int: Int]] = [:]
    private var resumeDataPaths: [UUID: String] = [:]
    private var runtimeOptionsByID: [UUID: TorrentRuntimeOptions] = [:]
    private var seedingStartedAtByID: [UUID: Date] = [:]

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
        applyRuntimeOptions(request.runtimeOptions)
        if let handleID = handleIDs[request.id] {
            rememberFileSelection(for: request)
            rememberFilePriorities(for: request)
            rememberResumeDataPath(for: request)
            runtimeOptionsByID[request.id] = request.runtimeOptions
            if request.hasExplicitFileSelection {
                applyFileSelection(handleID: handleID, selectedFileIndexes: request.selectedFileIndexes)
            }
            applyFilePriorities(handleID: handleID, filePriorities: request.filePriorities)
            applyTorrentRuntimeOptions(handleID: handleID, options: request.runtimeOptions)
            sgx_libtorrent_resume(sessionBox.raw, handleID)
            startPolling(request: request, handleID: handleID, onSnapshot: onSnapshot)
            return
        }

        let selected = request.selectedFileIndexes.map(Int32.init)
        let priorityPairs = request.filePriorities.sorted { $0.key < $1.key }
        let priorityIndexes = priorityPairs.map { Int32($0.key) }
        let priorityValues = priorityPairs.map { Int32(Self.enginePriority(forStoredPriority: $0.value)) }
        let handleID: Int32

        if request.displaySource.hasPrefix("magnet:") {
            handleID = sessionBox.addMagnet(
                request.displaySource,
                savePath: request.savePath,
                selectedFileIndexes: selected,
                hasExplicitFileSelection: request.hasExplicitFileSelection,
                priorityIndexes: priorityIndexes,
                priorityValues: priorityValues,
                resumeDataPath: request.resumeDataPath,
                runtimeOptions: request.runtimeOptions
            )
        } else {
            let torrentPath = request.resolvedTorrentFilePath ?? request.displaySource
            handleID = sessionBox.addTorrentFile(
                torrentPath,
                savePath: request.savePath,
                selectedFileIndexes: selected,
                hasExplicitFileSelection: request.hasExplicitFileSelection,
                priorityIndexes: priorityIndexes,
                priorityValues: priorityValues,
                resumeDataPath: request.resumeDataPath,
                runtimeOptions: request.runtimeOptions
            )
        }

        guard handleID >= 0 else {
            throw LibtorrentAdapterError.nativeError(lastError())
        }

        handleIDs[request.id] = handleID
        rememberFileSelection(for: request)
        rememberFilePriorities(for: request)
        rememberResumeDataPath(for: request)
        runtimeOptionsByID[request.id] = request.runtimeOptions
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
        _ = saveResumeData(id: id, handleID: handleID)
        sgx_libtorrent_pause(sessionBox.raw, handleID)
    }

    func cancel(id: UUID) async {
        guard let handleID = handleIDs[id] else { return }
        _ = saveResumeData(id: id, handleID: handleID)
        sgx_libtorrent_remove(sessionBox.raw, handleID, 0)
        pollingTasks[id]?.cancel()
        pollingTasks[id] = nil
        handleIDs[id] = nil
        selectedFileIndexes[id] = nil
        filePriorities[id] = nil
        resumeDataPaths[id] = nil
        runtimeOptionsByID[id] = nil
        seedingStartedAtByID[id] = nil
    }

    func remove(id: UUID, deletingFiles: Bool) async {
        guard let handleID = handleIDs[id] else { return }
        if !deletingFiles {
            _ = saveResumeData(id: id, handleID: handleID)
        }
        sgx_libtorrent_remove(sessionBox.raw, handleID, deletingFiles ? 1 : 0)
        pollingTasks[id]?.cancel()
        pollingTasks[id] = nil
        handleIDs[id] = nil
        selectedFileIndexes[id] = nil
        filePriorities[id] = nil
        resumeDataPaths[id] = nil
        runtimeOptionsByID[id] = nil
        seedingStartedAtByID[id] = nil
    }

    func recheck(
        _ request: TorrentStartRequest,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async {
        let id = request.id
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

    func setFilePriority(id: UUID, fileIndex: Int, priority: Int) async {
        guard let handleID = handleIDs[id] else { return }
        var priorities = filePriorities[id] ?? [:]
        priorities[fileIndex] = priority
        filePriorities[id] = priorities
        sgx_libtorrent_set_file_priority(
            sessionBox.raw,
            handleID,
            Int32(clamping: fileIndex),
            Int32(clamping: Self.enginePriority(forStoredPriority: priority))
        )
    }

    func setSequentialDownload(id: UUID, enabled: Bool) async {
        guard let handleID = handleIDs[id] else { return }
        if var options = runtimeOptionsByID[id] {
            options.isSequentialDownloadEnabled = enabled
            runtimeOptionsByID[id] = options
            applyTorrentRuntimeOptions(handleID: handleID, options: options)
        } else {
            sgx_libtorrent_set_sequential_download(sessionBox.raw, handleID, enabled ? 1 : 0)
        }
    }

    func setRuntimeOptions(id: UUID, options: TorrentRuntimeOptions) async {
        runtimeOptionsByID[id] = options
        guard let handleID = handleIDs[id] else { return }
        applyTorrentRuntimeOptions(handleID: handleID, options: options)
    }

    func addTracker(id: UUID, url: String) async {
        guard let handleID = handleIDs[id] else { return }
        url.withCString { sgx_libtorrent_add_tracker(sessionBox.raw, handleID, $0) }
        sgx_libtorrent_force_reannounce(sessionBox.raw, handleID)
    }

    func removeTracker(id: UUID, url: String) async {
        guard let handleID = handleIDs[id] else { return }
        url.withCString { sgx_libtorrent_remove_tracker(sessionBox.raw, handleID, $0) }
    }

    func forceReannounce(id: UUID) async {
        guard let handleID = handleIDs[id] else { return }
        sgx_libtorrent_force_reannounce(sessionBox.raw, handleID)
    }

    func configure(runtimeOptions: TorrentRuntimeOptions) async {
        applyRuntimeOptions(runtimeOptions)
        for (id, handleID) in handleIDs {
            var options = runtimeOptionsByID[id] ?? runtimeOptions
            let sequentialDownloadEnabled = options.isSequentialDownloadEnabled
            options.isDHTEnabled = runtimeOptions.isDHTEnabled
            options.isPEXEnabled = runtimeOptions.isPEXEnabled
            options.isLSDEnabled = runtimeOptions.isLSDEnabled
            options.magnetMetadataTimeoutSeconds = runtimeOptions.magnetMetadataTimeoutSeconds
            options.maxConnections = runtimeOptions.maxConnections
            options.maxUploadSlots = runtimeOptions.maxUploadSlots
            options.seedingLimitMode = runtimeOptions.seedingLimitMode
            options.stopSeedingAtRatio = runtimeOptions.stopSeedingAtRatio
            options.stopSeedingAfterSeconds = runtimeOptions.stopSeedingAfterSeconds
            options.isSequentialDownloadEnabled = sequentialDownloadEnabled
            runtimeOptionsByID[id] = options
            applyTorrentRuntimeOptions(handleID: handleID, options: options)
        }
    }

    private func applyRuntimeOptions(_ options: TorrentRuntimeOptions) {
        sgx_libtorrent_apply_runtime_options(
            sessionBox.raw,
            options.isDHTEnabled ? 1 : 0,
            options.isLSDEnabled ? 1 : 0,
            Int32(clamping: options.maxConnections),
            Int32(clamping: options.maxUploadSlots)
        )
    }

    private func applyTorrentRuntimeOptions(handleID: Int32, options: TorrentRuntimeOptions) {
        sgx_libtorrent_set_torrent_runtime_options(
            sessionBox.raw,
            handleID,
            options.isDHTEnabled ? 1 : 0,
            options.isPEXEnabled ? 1 : 0,
            options.isLSDEnabled ? 1 : 0,
            options.isSequentialDownloadEnabled ? 1 : 0
        )
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

    private func rememberFilePriorities(for request: TorrentStartRequest) {
        filePriorities[request.id] = request.filePriorities.isEmpty ? nil : request.filePriorities
    }

    private func rememberResumeDataPath(for request: TorrentStartRequest) {
        if let resumeDataPath = request.resumeDataPath {
            resumeDataPaths[request.id] = resumeDataPath
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

    private func applyFilePriorities(handleID: Int32, filePriorities: [Int: Int]) {
        for (fileIndex, priority) in filePriorities {
            sgx_libtorrent_set_file_priority(
                sessionBox.raw,
                handleID,
                Int32(clamping: fileIndex),
                Int32(clamping: Self.enginePriority(forStoredPriority: priority))
            )
        }
    }

    private func poll(
        request: TorrentStartRequest,
        handleID: Int32,
        onSnapshot: @escaping @Sendable (DownloadSnapshot) -> Void
    ) async {
        var detailTick = 0
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
            if nativeStatus.has_metadata != 0,
               let priorities = filePriorities[request.id] {
                applyFilePriorities(handleID: handleID, filePriorities: priorities)
            }

            let shouldRefreshDetails = detailTick % 3 == 0
            let trackers = shouldRefreshDetails ? copyTrackers(handleID: handleID) : nil
            let peers = shouldRefreshDetails ? copyPeers(handleID: handleID) : nil
            let seedingDurationSeconds = seedingDurationSeconds(
                id: request.id,
                isSeeding: nativeStatus.is_seeding != 0
            )
            let health = healthInfo(
                from: nativeStatus,
                trackerCount: trackers?.count,
                seedingDurationSeconds: seedingDurationSeconds
            )
            let currentOptions = runtimeOptionsByID[request.id] ?? request.runtimeOptions
            detailTick += 1

            if nativeStatus.has_error != 0 {
                let resumeState = saveResumeData(id: request.id, handleID: handleID)
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
                        torrentConnection: connectionInfo(
                            from: nativeStatus,
                            options: currentOptions,
                            seedingDurationSeconds: seedingDurationSeconds
                        ),
                        torrentResumeState: resumeState,
                        torrentTrackers: trackers,
                        torrentPeers: peers,
                        torrentRuntimeOptions: currentOptions,
                        torrentHealth: health
                    )
                )
                pollingTasks[request.id] = nil
                handleIDs[request.id] = nil
                selectedFileIndexes[request.id] = nil
                filePriorities[request.id] = nil
                resumeDataPaths[request.id] = nil
                runtimeOptionsByID[request.id] = nil
                seedingStartedAtByID[request.id] = nil
                return
            }

            let completed = nativeStatus.total_wanted > 0
                && nativeStatus.total_wanted_done >= nativeStatus.total_wanted

            if currentOptions.shouldStopSeeding(
                isSeeding: nativeStatus.is_seeding != 0,
                shareRatio: Double(nativeStatus.share_ratio),
                completed: completed,
                seedingDurationSeconds: seedingDurationSeconds
            ) {
                sgx_libtorrent_pause(sessionBox.raw, handleID)
                let resumeState = saveResumeData(id: request.id, handleID: handleID)
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
                        torrentConnection: connectionInfo(
                            from: nativeStatus,
                            options: currentOptions,
                            seedingDurationSeconds: seedingDurationSeconds
                        ),
                        torrentResumeState: resumeState,
                        torrentTrackers: trackers,
                        torrentPeers: peers,
                        torrentRuntimeOptions: currentOptions,
                        torrentHealth: health
                    )
                )
                pollingTasks[request.id] = nil
                seedingStartedAtByID[request.id] = nil
                return
            }

            let status = status(from: nativeStatus, completed: completed)
            let resumeState = nativeStatus.needs_resume_data_save != 0
                ? request.resumeDataPath.map {
                    TorrentResumeState(resumeDataPath: $0, status: .loaded)
                }
                : nil

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
                    torrentConnection: connectionInfo(
                        from: nativeStatus,
                        options: currentOptions,
                        seedingDurationSeconds: seedingDurationSeconds
                    ),
                    torrentResumeState: resumeState,
                    torrentTrackers: trackers,
                    torrentPeers: peers,
                    torrentRuntimeOptions: currentOptions,
                    torrentHealth: health
                )
            )

            if status == .completed {
                _ = saveResumeData(id: request.id, handleID: handleID)
                pollingTasks[request.id] = nil
                seedingStartedAtByID[request.id] = nil
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
        if nativeStatus.has_metadata == 0 {
            return .fetchingMetadata
        }
        if completed && nativeStatus.is_seeding != 0 {
            return .seeding
        }
        if completed && nativeStatus.is_seeding == 0 {
            return .completed
        }
        return .running
    }

    private func metadataStatus(from nativeStatus: SGXTorrentStatus) -> TorrentMetadataStatus {
        nativeStatus.has_metadata != 0 ? .available : .fetching
    }

    private func connectionInfo(
        from nativeStatus: SGXTorrentStatus,
        options: TorrentRuntimeOptions,
        seedingDurationSeconds: TimeInterval
    ) -> TorrentConnectionInfo {
        TorrentConnectionInfo(
            metadataStatus: metadataStatus(from: nativeStatus),
            engine: .libtorrent,
            engineStatus: .available,
            peerCount: Int(nativeStatus.num_peers),
            downloadRate: nativeStatus.download_rate,
            uploadRate: nativeStatus.upload_rate,
            shareRatio: Double(nativeStatus.share_ratio),
            seedingDurationSeconds: seedingDurationSeconds,
            distributedCopies: Double(nativeStatus.distributed_copies),
            isDHTEnabled: options.isDHTEnabled,
            isPEXEnabled: options.isPEXEnabled,
            isLSDEnabled: options.isLSDEnabled,
            localPortDescription: nativeStatus.listen_port > 0
                ? "\(nativeStatus.listen_port)"
                : L10n.string("connection_port_ready"),
            nativeEngineAvailable: true
        )
    }

    private func seedingDurationSeconds(id: UUID, isSeeding: Bool) -> TimeInterval {
        guard isSeeding else {
            seedingStartedAtByID[id] = nil
            return 0
        }
        let startedAt = seedingStartedAtByID[id] ?? Date()
        seedingStartedAtByID[id] = startedAt
        return Date().timeIntervalSince(startedAt)
    }

    private func healthInfo(
        from nativeStatus: SGXTorrentStatus,
        trackerCount: Int?,
        seedingDurationSeconds: TimeInterval
    ) -> TorrentHealthInfo {
        TorrentHealthInfo(
            nativeEngineAvailable: true,
            engine: .libtorrent,
            engineStatus: .available,
            hasMetadata: nativeStatus.has_metadata != 0,
            isSequentialDownload: nativeStatus.is_sequential_download != 0,
            needsResumeDataSave: nativeStatus.needs_resume_data_save != 0,
            peerCount: Int(nativeStatus.num_peers),
            connectionCount: Int(nativeStatus.num_connections),
            uploadSlotCount: Int(nativeStatus.num_uploads),
            listenPort: Int(nativeStatus.listen_port),
            dhtNodeCount: Int(nativeStatus.dht_nodes),
            distributedCopies: Double(nativeStatus.distributed_copies),
            trackerCount: trackerCount ?? 0,
            seedingDurationSeconds: seedingDurationSeconds,
            lastError: nativeStatus.has_error != 0 ? lastError() : nil
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
                priority: Self.storedPriority(forEnginePriority: Int(file.priority)),
                progress: Double(file.progress)
            )
        }
    }

    private func copyTrackers(handleID: Int32) -> [TorrentTrackerInfo] {
        let capacity = 128
        let buffer = UnsafeMutablePointer<SGXTorrentTracker>.allocate(capacity: capacity)
        defer {
            buffer.deallocate()
        }

        let count = Int(sgx_libtorrent_copy_trackers(sessionBox.raw, handleID, buffer, Int32(capacity)))
        guard count > 0 else { return [] }
        defer {
            sgx_libtorrent_free_trackers(buffer, Int32(count))
        }

        return (0..<count).map { index in
            let tracker = buffer[index]
            return TorrentTrackerInfo(
                url: tracker.url.map { String(cString: $0) } ?? "",
                tier: Int(tracker.tier),
                status: tracker.status.map { String(cString: $0) } ?? "",
                seedCount: Int(tracker.seed_count),
                leecherCount: Int(tracker.leecher_count),
                downloadedCount: Int(tracker.downloaded_count),
                lastAnnounce: tracker.last_announce.map { String(cString: $0) } ?? "",
                nextAnnounce: tracker.next_announce.map { String(cString: $0) } ?? "",
                errorMessage: tracker.error_message
                    .map { String(cString: $0) }
                    .flatMap { $0.isEmpty ? nil : $0 }
            )
        }
    }

    private func copyPeers(handleID: Int32) -> [TorrentPeerInfo] {
        let capacity = 100
        let buffer = UnsafeMutablePointer<SGXTorrentPeer>.allocate(capacity: capacity)
        defer {
            buffer.deallocate()
        }

        let count = Int(sgx_libtorrent_copy_peers(sessionBox.raw, handleID, buffer, Int32(capacity)))
        guard count > 0 else { return [] }
        defer {
            sgx_libtorrent_free_peers(buffer, Int32(count))
        }

        return (0..<count).map { index in
            let peer = buffer[index]
            return TorrentPeerInfo(
                address: peer.address.map { String(cString: $0) } ?? "",
                client: peer.client.map { String(cString: $0) } ?? "",
                progress: Double(peer.progress),
                downloadRate: peer.download_rate,
                uploadRate: peer.upload_rate,
                direction: peer.direction.map { String(cString: $0) } ?? "",
                flags: peer.flags.map { String(cString: $0) } ?? ""
            )
        }
    }

    private func saveResumeData(id: UUID, handleID: Int32) -> TorrentResumeState? {
        guard let path = resumeDataPaths[id] else { return nil }
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return TorrentResumeState(
                resumeDataPath: path,
                status: .failed,
                updatedAt: .now,
                errorMessage: error.localizedDescription
            )
        }

        if sgx_libtorrent_save_resume_data(sessionBox.raw, handleID, path) != 0 {
            return TorrentResumeState(resumeDataPath: path, status: .saved, updatedAt: .now)
        }

        return TorrentResumeState(
            resumeDataPath: path,
            status: .failed,
            updatedAt: .now,
            errorMessage: lastError()
        )
    }

    private nonisolated static func enginePriority(forStoredPriority priority: Int) -> Int {
        (TorrentFilePriority(rawValue: priority) ?? TorrentFilePriority.fromEnginePriority(priority)).enginePriority
    }

    private nonisolated static func storedPriority(forEnginePriority priority: Int) -> Int {
        TorrentFilePriority.fromEnginePriority(priority).rawValue
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

    func addMagnet(
        _ magnetURI: String,
        savePath: String,
        selectedFileIndexes: [Int32],
        hasExplicitFileSelection: Bool,
        priorityIndexes: [Int32],
        priorityValues: [Int32],
        resumeDataPath: String?,
        runtimeOptions: TorrentRuntimeOptions
    ) -> Int32 {
        magnetURI.withCString { magnet in
            savePath.withCString { savePath in
                Self.withOptionalCString(resumeDataPath) { resumeDataPath in
                    selectedFileIndexes.withUnsafeBufferPointer { selectedBuffer in
                        priorityIndexes.withUnsafeBufferPointer { priorityIndexBuffer in
                            priorityValues.withUnsafeBufferPointer { priorityValueBuffer in
                                sgx_libtorrent_add_magnet_with_options(
                                    raw,
                                    magnet,
                                    savePath,
                                    hasExplicitFileSelection ? selectedBuffer.baseAddress : nil,
                                    hasExplicitFileSelection ? Int32(selectedBuffer.count) : -1,
                                    priorityIndexBuffer.baseAddress,
                                    priorityValueBuffer.baseAddress,
                                    Int32(priorityIndexBuffer.count),
                                    resumeDataPath,
                                    runtimeOptions.isSequentialDownloadEnabled ? 1 : 0,
                                    runtimeOptions.isDHTEnabled ? 1 : 0,
                                    runtimeOptions.isPEXEnabled ? 1 : 0,
                                    runtimeOptions.isLSDEnabled ? 1 : 0
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    func addTorrentFile(
        _ torrentPath: String,
        savePath: String,
        selectedFileIndexes: [Int32],
        hasExplicitFileSelection: Bool,
        priorityIndexes: [Int32],
        priorityValues: [Int32],
        resumeDataPath: String?,
        runtimeOptions: TorrentRuntimeOptions
    ) -> Int32 {
        torrentPath.withCString { torrentPath in
            savePath.withCString { savePath in
                Self.withOptionalCString(resumeDataPath) { resumeDataPath in
                    selectedFileIndexes.withUnsafeBufferPointer { selectedBuffer in
                        priorityIndexes.withUnsafeBufferPointer { priorityIndexBuffer in
                            priorityValues.withUnsafeBufferPointer { priorityValueBuffer in
                                sgx_libtorrent_add_torrent_file_with_options(
                                    raw,
                                    torrentPath,
                                    savePath,
                                    hasExplicitFileSelection ? selectedBuffer.baseAddress : nil,
                                    hasExplicitFileSelection ? Int32(selectedBuffer.count) : -1,
                                    priorityIndexBuffer.baseAddress,
                                    priorityValueBuffer.baseAddress,
                                    Int32(priorityIndexBuffer.count),
                                    resumeDataPath,
                                    runtimeOptions.isSequentialDownloadEnabled ? 1 : 0,
                                    runtimeOptions.isDHTEnabled ? 1 : 0,
                                    runtimeOptions.isPEXEnabled ? 1 : 0,
                                    runtimeOptions.isLSDEnabled ? 1 : 0
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    func addMagnetForPreview(_ magnetURI: String, savePath: String) -> Int32 {
        magnetURI.withCString { magnet in
            savePath.withCString { savePath in
                sgx_libtorrent_add_magnet(raw, magnet, savePath, nil, 0)
            }
        }
    }

    private static func withOptionalCString<Result>(
        _ value: String?,
        _ body: (UnsafePointer<CChar>?) -> Result
    ) -> Result {
        guard let value, !value.isEmpty else {
            return body(nil)
        }
        return value.withCString(body)
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
        let handleID = sessionBox.addMagnetForPreview(magnet, savePath: NSTemporaryDirectory())

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
                priority: Self.storedPriority(forEnginePriority: Int(file.priority)),
                progress: Double(file.progress)
            )
        }
    }

    private nonisolated static func enginePriority(forStoredPriority priority: Int) -> Int {
        (TorrentFilePriority(rawValue: priority) ?? TorrentFilePriority.fromEnginePriority(priority)).enginePriority
    }

    private nonisolated static func storedPriority(forEnginePriority priority: Int) -> Int {
        TorrentFilePriority.fromEnginePriority(priority).rawValue
    }

    private func lastError() -> String {
        guard let message = sgx_libtorrent_last_error(sessionBox.raw) else {
            return "Unknown libtorrent error"
        }
        return String(cString: message)
    }
}
#endif
