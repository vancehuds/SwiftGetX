import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class DownloadCoordinator {
    private var modelContext: ModelContext?
    private var settings: AppSettings?
    private let httpEngine = HTTPDownloadEngine()
    private let torrentEngine = TorrentDownloadEngine()

    var selectedTaskID: UUID?
    var activeFilter: DownloadFilter = .all
    var searchText = ""
    var downloadLimitBytes: Int64 = 0
    var uploadLimitBytes: Int64 = 0

    private(set) var statusMessage = L10n.string("status_ready")

    var selectedTask: DownloadTask? {
        guard let selectedTaskID, let modelContext else { return nil }
        let descriptor = FetchDescriptor<DownloadTask>(
            predicate: #Predicate { $0.id == selectedTaskID }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func attach(modelContext: ModelContext, settings: AppSettings) {
        self.modelContext = modelContext
        self.settings = settings
        httpEngine.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in self?.apply(snapshot) }
        }
        torrentEngine.onSnapshot = { [weak self] snapshot in
            Task { @MainActor in self?.apply(snapshot) }
        }
        httpEngine.configure(
            multithreadingEnabled: settings.httpMultithreadingEnabled,
            segmentCount: settings.httpSegmentCount,
            hidesTemporaryFiles: settings.hideHTTPTemporaryFiles,
            retryLimit: settings.retryLimit
        )
        torrentEngine.configure(runtimeOptions: settings.torrentRuntimeOptions)
        setSpeedLimit(
            downloadBytesPerSecond: settings.globalDownloadLimitBytes,
            uploadBytesPerSecond: settings.globalUploadLimitBytes
        )
    }

    func reloadSettings(_ settings: AppSettings) {
        self.settings = settings
        httpEngine.configure(
            multithreadingEnabled: settings.httpMultithreadingEnabled,
            segmentCount: settings.httpSegmentCount,
            hidesTemporaryFiles: settings.hideHTTPTemporaryFiles,
            retryLimit: settings.retryLimit
        )
        torrentEngine.configure(runtimeOptions: settings.torrentRuntimeOptions)
        setSpeedLimit(
            downloadBytesPerSecond: settings.globalDownloadLimitBytes,
            uploadBytesPerSecond: settings.globalUploadLimitBytes
        )
    }

    func restoreIncompleteTasks() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<DownloadTask>(
            predicate: #Predicate { task in
                task.statusRawValue != "completed"
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        guard let tasks = try? modelContext.fetch(descriptor) else { return }
        for task in tasks where task.status == .running || task.status == .seeding || task.status == .verifying {
            task.status = .paused
            task.appendLog(L10n.string("log_restored_paused_after_restart"))
        }
        save()
    }

    func tasks(for filter: DownloadFilter = .all) -> [DownloadTask] {
        let allTasks = allTasks()
        return allTasks.filter { task in
            let matchesFilter = filter.matches(task)
            let matchesSearch = searchText.isEmpty
                || task.name.localizedCaseInsensitiveContains(searchText)
                || task.source.localizedCaseInsensitiveContains(searchText)
            return matchesFilter && matchesSearch
        }
    }

    func allTasks() -> [DownloadTask] {
        guard let modelContext else { return [] }
        var descriptor = FetchDescriptor<DownloadTask>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    @discardableResult
    func add(source: String, saveDirectory: URL? = nil, suggestedFilename: String? = nil) -> [DownloadTask] {
        let sources = SourceParser.extractSources(from: source)
        let saveDirectory = saveDirectory ?? settings?.defaultDownloadDirectory ?? AppDefaults.downloadDirectory
        let tasks = sources.map { source in
            let kind = SourceParser.kind(for: source)
            let displayName = displayName(for: source, kind: kind, suggestedFilename: suggestedFilename, sourceCount: sources.count)
            let task = DownloadTask(
                name: displayName,
                source: source,
                kind: kind,
                savePath: saveDirectory.appendingPathComponent(displayName).path
            )
            configureTorrentDefaults(for: task)
            task.appendLog(L10n.string("log_task_created"))
            return task
        }

        guard let modelContext else { return tasks }
        for task in tasks {
            modelContext.insert(task)
        }
        selectedTaskID = tasks.first?.id ?? selectedTaskID
        save()
        statusMessage = L10n.string("status_added_tasks", tasks.count)
        scheduleQueue()
        return tasks
    }

    @discardableResult
    func add(
        previews: [TorrentMetadataPreview],
        saveDirectory: URL? = nil,
        selectedFileIndexes: [String: [Int]] = [:],
        filePriorities: [String: [Int: Int]] = [:]
    ) -> [DownloadTask] {
        let saveDirectory = saveDirectory ?? settings?.defaultDownloadDirectory ?? AppDefaults.downloadDirectory
        let tasks = previews.map { preview in
            let task = DownloadTask(
                name: preview.displayName,
                source: preview.source,
                kind: preview.kind,
                savePath: saveDirectory.appendingPathComponent(preview.displayName).path,
                totalBytes: preview.totalBytes,
                supportsResume: preview.kind == .torrentMagnet || preview.kind == .torrentFile,
                resolvedTorrentFilePath: preview.resolvedTorrentFilePath,
                torrentMetadataStatus: preview.metadataStatus,
                selectedFileIndexes: selectedFileIndexes[preview.source] ?? preview.selectedFileIndexes
            )
            var files = preview.files
            if let priorities = filePriorities[preview.source] {
                for index in files.indices {
                    files[index].priority = priorities[files[index].index] ?? files[index].priority
                }
            }
            task.torrentFiles = files
            configureTorrentDefaults(for: task)
            task.appendLog(L10n.string("log_task_created"))
            if let errorMessage = preview.errorMessage {
                task.appendLog(errorMessage)
            }
            return task
        }

        guard let modelContext else { return tasks }
        for task in tasks {
            modelContext.insert(task)
        }
        selectedTaskID = tasks.first?.id ?? selectedTaskID
        save()
        statusMessage = L10n.string("status_added_tasks", tasks.count)
        scheduleQueue()
        return tasks
    }

    private func displayName(
        for source: String,
        kind: DownloadKind,
        suggestedFilename: String?,
        sourceCount: Int
    ) -> String {
        guard sourceCount == 1,
              let suggestedFilename = suggestedFilename?.trimmingCharacters(in: .whitespacesAndNewlines),
              !suggestedFilename.isEmpty
        else {
            return SourceParser.displayName(for: source, kind: kind)
        }

        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let sanitizedFilename = suggestedFilename
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitizedFilename.isEmpty ? SourceParser.displayName(for: source, kind: kind) : sanitizedFilename
    }

    func start(_ task: DownloadTask) {
        task.status = .running
        task.errorMessage = nil
        task.retryCount = 0
        task.appendLog(L10n.string("log_start_download"))
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).start(request)
        }
    }

    private func configureTorrentDefaults(for task: DownloadTask) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        let options = settings?.torrentRuntimeOptions ?? TorrentRuntimeOptions()
        task.torrentRuntimeOptions = options
        if let resumeDataPath = TorrentResumeStore.resumeDataPath(for: task.id) {
            task.torrentResumeState = TorrentResumeState(
                resumeDataPath: resumeDataPath,
                status: FileManager.default.fileExists(atPath: resumeDataPath) ? .loaded : .missing
            )
        }
    }

    func pause(_ task: DownloadTask) {
        task.status = .paused
        task.speedBytesPerSecond = 0
        task.appendLog(L10n.string("log_paused"))
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).pause(request)
        }
    }

    func resume(_ task: DownloadTask) {
        start(task)
    }

    func cancel(_ task: DownloadTask) {
        task.status = .failed
        task.speedBytesPerSecond = 0
        task.errorMessage = L10n.string("error_task_cancelled")
        task.appendLog(L10n.string("log_task_cancelled"))
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).cancel(request)
        }
    }

    func remove(_ task: DownloadTask, deletingFiles: Bool) {
        guard let modelContext else { return }
        let shouldDeleteLocalData = deletingFiles || !task.hasFinishedDownloading
        let request = DownloadRequest(task: task)
        Task {
            await engine(for: request.kind).remove(request, deletingFiles: shouldDeleteLocalData)
        }

        if shouldDeleteLocalData {
            try? FileManager.default.removeItem(atPath: task.savePath)
        }
        if task.kind == .torrentMagnet || task.kind == .torrentFile {
            TorrentResumeStore.removeResumeData(for: task.id)
        }
        modelContext.delete(task)
        if selectedTaskID == task.id {
            selectedTaskID = tasks().first?.id
        }
        save()
    }

    func recheck(_ task: DownloadTask) {
        task.status = .verifying
        task.appendLog(L10n.string("log_start_recheck"))
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).recheck(request)
        }
    }

    func setTorrentFileSelection(_ task: DownloadTask, selectedFileIndexes: [Int]) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        task.selectedFileIndexes = selectedFileIndexes.sorted()
        var files = task.torrentFiles
        let selected = Set(selectedFileIndexes)
        for index in files.indices {
            files[index].priority = selected.contains(files[index].index)
                ? max(files[index].priority, TorrentFilePriority.normal.rawValue)
                : TorrentFilePriority.skip.rawValue
        }
        task.torrentFiles = files
        task.appendLog(L10n.string("log_updated_bt_file_selection", selectedFileIndexes.count))
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).setFileSelection(request, selectedFileIndexes: selectedFileIndexes)
        }
    }

    func setTorrentFilePriority(_ task: DownloadTask, fileIndex: Int, priority: TorrentFilePriority) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        var files = task.torrentFiles
        guard let index = files.firstIndex(where: { $0.index == fileIndex }) else { return }
        files[index].priority = priority.rawValue
        task.torrentFiles = files
        task.selectedFileIndexes = files
            .filter { $0.priority > TorrentFilePriority.skip.rawValue }
            .map(\.index)
            .sorted()
        task.appendLog(L10n.string("log_updated_bt_file_priority", files[index].path, priority.title))
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).setTorrentFilePriority(
                request,
                fileIndex: fileIndex,
                priority: priority.rawValue
            )
        }
    }

    func setTorrentSequentialDownload(_ task: DownloadTask, enabled: Bool) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        var options = task.torrentRuntimeOptions ?? settings?.torrentRuntimeOptions ?? TorrentRuntimeOptions()
        options.isSequentialDownloadEnabled = enabled
        task.torrentRuntimeOptions = options
        task.appendLog(enabled ? L10n.string("log_enabled_sequential_download") : L10n.string("log_disabled_sequential_download"))
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).setTorrentSequentialDownload(request, enabled: enabled)
        }
    }

    func addTorrentTracker(_ task: DownloadTask, url: String) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        task.appendLog(L10n.string("log_added_tracker", trimmed))
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).addTorrentTracker(request, url: trimmed)
        }
    }

    func removeTorrentTracker(_ task: DownloadTask, url: String) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        task.torrentTrackers = task.torrentTrackers.filter { $0.url != url }
        task.appendLog(L10n.string("log_removed_tracker", url))
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).removeTorrentTracker(request, url: url)
        }
    }

    func forceTorrentReannounce(_ task: DownloadTask) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        task.appendLog(L10n.string("log_forced_tracker_announce"))
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).forceTorrentReannounce(request)
        }
    }

    func pauseAll() {
        for task in tasks() where task.status == .running || task.status == .seeding || task.status == .queued || task.status == .verifying {
            pause(task)
        }
    }

    func resumeAll() {
        for task in tasks() where task.status == .paused || task.status == .failed || task.status == .queued {
            resume(task)
        }
    }

    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) {
        downloadLimitBytes = downloadBytesPerSecond
        uploadLimitBytes = uploadBytesPerSecond
        Task {
            await httpEngine.setSpeedLimit(
                downloadBytesPerSecond: downloadBytesPerSecond,
                uploadBytesPerSecond: uploadBytesPerSecond
            )
            await torrentEngine.setSpeedLimit(
                downloadBytesPerSecond: downloadBytesPerSecond,
                uploadBytesPerSecond: uploadBytesPerSecond
            )
        }
    }

    private func scheduleQueue() {
        let running = tasks().filter { $0.status == .running }.count
        let availableSlots = max(0, (settings?.concurrentTaskLimit ?? 3) - running)
        guard availableSlots > 0 else { return }

        for task in tasks().filter({ $0.status == .queued }).prefix(availableSlots) {
            start(task)
        }
    }

    private func apply(_ snapshot: DownloadSnapshot) {
        guard let modelContext else { return }
        let taskID = snapshot.taskID
        let descriptor = FetchDescriptor<DownloadTask>(
            predicate: #Predicate { $0.id == taskID }
        )
        guard let task = try? modelContext.fetch(descriptor).first else { return }

        task.status = snapshot.status
        if let savePath = snapshot.savePath {
            task.savePath = savePath
        }
        if let resolvedTorrentFilePath = snapshot.resolvedTorrentFilePath {
            task.resolvedTorrentFilePath = resolvedTorrentFilePath
        }
        if let torrentMetadataStatus = snapshot.torrentMetadataStatus {
            task.torrentMetadataStatus = torrentMetadataStatus
        }
        task.totalBytes = snapshot.totalBytes
        task.downloadedBytes = snapshot.downloadedBytes
        task.speedBytesPerSecond = snapshot.speedBytesPerSecond
        task.etaSeconds = snapshot.etaSeconds
        task.errorMessage = snapshot.errorMessage
        task.supportsResume = snapshot.supportsResume
        task.eTag = snapshot.eTag
        task.lastModified = snapshot.lastModified
        if let retryCount = snapshot.retryCount {
            task.retryCount = retryCount
        }
        if !snapshot.torrentFiles.isEmpty {
            task.torrentFiles = snapshot.torrentFiles
            if task.selectedFileIndexes.isEmpty {
                task.selectedFileIndexes = snapshot.torrentFiles.map(\.index)
            }
        }
        if let connectionSummary = snapshot.connectionSummary {
            task.connectionSummary = connectionSummary
        }
        if let torrentConnection = snapshot.torrentConnection {
            task.torrentConnection = torrentConnection
            task.connectionSummary = torrentConnection.summary
        }
        if let torrentResumeState = snapshot.torrentResumeState {
            task.torrentResumeState = torrentResumeState
        }
        if let torrentTrackers = snapshot.torrentTrackers {
            task.torrentTrackers = torrentTrackers
        }
        if let torrentPeers = snapshot.torrentPeers {
            task.torrentPeers = torrentPeers
        }
        if let torrentRuntimeOptions = snapshot.torrentRuntimeOptions {
            task.torrentRuntimeOptions = torrentRuntimeOptions
        }
        if let torrentHealth = snapshot.torrentHealth {
            task.torrentHealth = torrentHealth
        }

        switch snapshot.status {
        case .seeding:
            if task.completedAt == nil {
                task.completedAt = .now
                task.appendLog(L10n.string("log_download_ready_seeding"))
                if settings?.completionNotificationsEnabled ?? true {
                    NotificationManager.notifyCompletion(for: task)
                }
                scheduleQueue()
            }
        case .completed:
            task.speedBytesPerSecond = 0
            if task.completedAt == nil {
                task.completedAt = .now
                task.appendLog(L10n.string("log_download_completed"))
                if settings?.completionNotificationsEnabled ?? true {
                    NotificationManager.notifyCompletion(for: task)
                }
                scheduleQueue()
            }
        case .failed:
            task.speedBytesPerSecond = 0
            task.appendLog(snapshot.errorMessage ?? L10n.string("error_download_failed"))
            scheduleQueue()
        default:
            break
        }

        save()
    }

    private func engine(for kind: DownloadKind) -> any DownloadEngine {
        switch kind {
        case .http:
            httpEngine
        case .torrentMagnet, .torrentFile:
            torrentEngine
        }
    }

    private func save() {
        do {
            try modelContext?.save()
        } catch {
            statusMessage = L10n.string("status_save_failed", error.localizedDescription)
        }
    }
}

enum DownloadFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case seeding
    case queued
    case paused
    case completed
    case failed
    case http
    case torrent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L10n.string("filter_all")
        case .running: L10n.string("download_status_running")
        case .seeding: L10n.string("download_status_seeding")
        case .queued: L10n.string("download_status_queued")
        case .paused: L10n.string("download_status_paused")
        case .completed: L10n.string("download_status_completed")
        case .failed: L10n.string("download_status_failed")
        case .http: "HTTP"
        case .torrent: "BT"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .running: "arrow.down.circle"
        case .seeding: "arrow.up.circle"
        case .queued: "clock"
        case .paused: "pause.circle"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .http: "link"
        case .torrent: "point.3.connected.trianglepath.dotted"
        }
    }

    func matches(_ task: DownloadTask) -> Bool {
        switch self {
        case .all:
            true
        case .running:
            task.status == .running
        case .seeding:
            task.status == .seeding
        case .queued:
            task.status == .queued
        case .paused:
            task.status == .paused
        case .completed:
            task.status == .completed
        case .failed:
            task.status == .failed
        case .http:
            task.kind == .http
        case .torrent:
            task.kind == .torrentMagnet || task.kind == .torrentFile
        }
    }
}
