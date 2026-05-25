import Foundation

struct TorrentTrackerBatchValidation: Equatable {
    var validURLs: [String]
    var newURLs: [String]
    var duplicateURLs: [String]
    var invalidEntries: [String]

    var hasUsableAdditions: Bool {
        !newURLs.isEmpty
    }

    var summary: String {
        let parts = [
            L10n.string("torrent_tracker_batch_valid_count", newURLs.count),
            duplicateURLs.isEmpty ? nil : L10n.string("torrent_tracker_batch_duplicate_count", duplicateURLs.count),
            invalidEntries.isEmpty ? nil : L10n.string("torrent_tracker_batch_invalid_count", invalidEntries.count)
        ].compactMap { $0 }
        return parts.joined(separator: L10n.string("torrent_detail_separator"))
    }
}

enum TorrentTrackerBatchParser {
    static func validate(_ text: String, existingURLs: [String] = []) -> TorrentTrackerBatchValidation {
        let existing = Set(existingURLs)
        var seen = Set<String>()
        var valid = [String]()
        var newURLs = [String]()
        var duplicates = [String]()
        var invalid = [String]()

        for candidate in candidates(from: text) {
            guard isValidTrackerURL(candidate) else {
                invalid.append(candidate)
                continue
            }

            if !valid.contains(candidate) {
                valid.append(candidate)
            }

            let isDuplicate = existing.contains(candidate) || !seen.insert(candidate).inserted
            if isDuplicate {
                duplicates.append(candidate)
                continue
            }

            newURLs.append(candidate)
        }

        return TorrentTrackerBatchValidation(
            validURLs: valid,
            newURLs: newURLs,
            duplicateURLs: duplicates,
            invalidEntries: invalid
        )
    }

    static func validURLs(from text: String) -> [String] {
        validate(text).validURLs
    }

    private static func candidates(from text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ", \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isValidTrackerURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "udp"].contains(scheme),
              let host = url.host,
              !host.isEmpty
        else {
            return false
        }
        return true
    }
}

struct TorrentFilePriorityPlan: Equatable {
    var selectedFileIndexes: Set<Int>
    var priorities: [Int: TorrentFilePriority]
}

struct TorrentFileFolderGroup: Identifiable, Equatable {
    var path: String
    var fileIndexes: [Int]
    var totalBytes: Int64

    var id: String { path }

    var displayName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    var depth: Int {
        max(0, path.split(separator: "/", omittingEmptySubsequences: true).count - 1)
    }
}

enum TorrentFileUX {
    static func folderGroups(in files: [TorrentFile]) -> [TorrentFileFolderGroup] {
        var grouped = [String: (indexes: [Int], bytes: Int64)]()
        var orderedPaths = [String]()
        for file in files {
            for folder in folderPaths(for: file.path) {
                if grouped[folder] == nil {
                    orderedPaths.append(folder)
                }
                var value = grouped[folder] ?? ([], 0)
                value.indexes.append(file.index)
                value.bytes += file.size
                grouped[folder] = value
            }
        }

        return orderedPaths.compactMap { path in
            guard let value = grouped[path] else { return nil }
            return TorrentFileFolderGroup(
                path: path,
                fileIndexes: value.indexes.sorted(),
                totalBytes: value.bytes
            )
        }
    }

    @MainActor
    static func filteredFiles(_ files: [TorrentFile], searchText: String) -> [TorrentFile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return files }
        return files.filter { file in
            file.path.lowercased().contains(query)
                || ByteCountFormatter.downloadFormatter.string(fromByteCount: file.size).lowercased().contains(query)
        }
    }

    static func normalizedExtensions(from text: String) -> Set<String> {
        Set(
            text.components(separatedBy: CharacterSet(charactersIn: ",; \n\t"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
                .map { $0.lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    static func fileIndexes(in files: [TorrentFile], matchingExtensions text: String) -> [Int] {
        let extensions = normalizedExtensions(from: text)
        guard !extensions.isEmpty else { return [] }
        return files
            .filter { extensions.contains(URL(fileURLWithPath: $0.path).pathExtension.lowercased()) }
            .map(\.index)
    }

    static func apply(
        priority: TorrentFilePriority,
        to fileIndexes: [Int],
        files: [TorrentFile],
        selectedFileIndexes: Set<Int>,
        priorities: [Int: TorrentFilePriority]
    ) -> TorrentFilePriorityPlan {
        let targets = Set(fileIndexes)
        guard !targets.isEmpty else {
            return TorrentFilePriorityPlan(selectedFileIndexes: selectedFileIndexes, priorities: priorities)
        }

        var nextSelected = selectedFileIndexes
        var nextPriorities = priorities
        for file in files where targets.contains(file.index) {
            nextPriorities[file.index] = priority
            if priority.isWanted {
                nextSelected.insert(file.index)
            } else {
                nextSelected.remove(file.index)
            }
        }

        return TorrentFilePriorityPlan(
            selectedFileIndexes: nextSelected,
            priorities: nextPriorities
        )
    }

    static func inferredPriority(
        for file: TorrentFile,
        selectedFileIndexes: Set<Int>,
        priorities: [Int: TorrentFilePriority]
    ) -> TorrentFilePriority {
        priorities[file.index] ?? (selectedFileIndexes.contains(file.index) ? file.priorityLevel : .skip)
    }

    private static func folderPaths(for filePath: String) -> [String] {
        let components = filePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count > 1 else { return [] }
        return (1..<components.count).map { components.prefix($0).joined(separator: "/") }
    }
}

enum TorrentStatusAdvice {
    static func messages(for task: DownloadTask) -> [String] {
        guard task.isTorrent else { return [] }
        var messages = [String]()

        if task.status == .fetchingMetadata || task.torrentMetadataStatus == .fetching {
            let trackerCount = task.torrentTrackers.count
            messages.append(L10n.string("torrent_advice_metadata_fetching", trackerCount))
        }

        if task.status == .fetchingPeers || task.status == .connectingPeers {
            let health = task.torrentHealth
            let peerCount = health?.peerCount ?? task.torrentPeers.count
            let trackerPeers = health?.trackerPeerCount ?? 0
            let dhtPeers = health?.dhtPeerCount ?? 0
            messages.append(L10n.string("torrent_advice_peer_discovery", peerCount, trackerPeers, dhtPeers))
        }

        if task.status == .failed {
            if let errorMessage = task.errorMessage, !errorMessage.isEmpty {
                messages.append(errorMessage)
            } else if task.torrentPeers.isEmpty {
                messages.append(L10n.string("torrent_advice_no_peers"))
            }
        }

        if let health = task.torrentHealth {
            if health.engineStatus.supportsRuntimeControls == false {
                messages.append(L10n.string("torrent_advice_engine_unavailable", health.engineStatus.title))
            }
            if health.hasMetadata,
               health.trackerPeerCount == 0,
               health.dhtPeerCount == 0,
               health.pexPeerCount == 0,
               health.lsdPeerCount == 0,
               health.peerCount == 0
            {
                messages.append(L10n.string("torrent_advice_no_peer_sources"))
            }
            if health.hasMetadata,
               task.torrentRuntimeOptions?.isDHTEnabled == true,
               task.torrentConnection?.isDHTEnabled == false
            {
                messages.append(L10n.string("torrent_advice_private_discovery"))
            }
            if health.needsResumeDataSave {
                messages.append(L10n.string("torrent_advice_resume_dirty"))
            }
        }

        if let resumeState = task.torrentResumeState {
            switch resumeState.status {
            case .missing:
                messages.append(L10n.string("torrent_advice_resume_missing"))
            case .failed:
                messages.append(resumeState.errorMessage ?? L10n.string("torrent_advice_resume_failed"))
            case .loaded, .saved:
                break
            }
        } else if task.isTorrent && task.downloadedBytes > 0 && !task.status.usesActiveClock {
            messages.append(L10n.string("torrent_advice_resume_missing"))
        }

        return uniqued(messages)
    }

    static func restartRecoveryMessages(for task: DownloadTask) -> [String] {
        guard task.isTorrent else { return [] }
        var messages = [String]()
        if let resumeState = task.torrentResumeState {
            switch resumeState.status {
            case .saved, .loaded:
                messages.append(L10n.string("log_torrent_resume_data_available"))
            case .missing:
                messages.append(L10n.string("log_torrent_resume_data_missing_recheck"))
            case .failed:
                messages.append(resumeState.errorMessage ?? L10n.string("log_torrent_resume_data_failed_recheck"))
            }
        } else if task.downloadedBytes > 0 {
            messages.append(L10n.string("log_torrent_resume_data_missing_recheck"))
        }
        return messages
    }

    private static func uniqued(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
