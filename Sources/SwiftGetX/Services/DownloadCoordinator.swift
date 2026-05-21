import AppKit
import Foundation
import Observation
import SwiftData
import SwiftGetXCore
import SwiftGetXTorrentCore

@MainActor
@Observable
final class DownloadCoordinator {
    private var modelContext: ModelContext?
    private var settings: AppSettings?
    private let httpEngine = HTTPDownloadEngine()
    private let torrentEngine = TorrentDownloadEngine()
    private var runtimeBrowserContexts: [UUID: BrowserDownloadContext] = [:]
    private var runtimeHTTPOptions: [UUID: HTTPDownloadOptions] = [:]
    private var queueWakeTask: Task<Void, Never>?
    private var queueWakeDate: Date?
    private let runsEngines: Bool

    var selectedTaskID: UUID?
    var activeFilter: DownloadFilter = .all
    var searchText = ""
    var downloadLimitBytes: Int64 = 0
    var uploadLimitBytes: Int64 = 0

    private(set) var statusMessage = L10n.string("status_ready")

    init(runsEngines: Bool = true) {
        self.runsEngines = runsEngines
    }

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
        normalizeMissingQueuePositions()
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
        scheduleQueue()
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
            task.speedBytesPerSecond = 0
            task.errorMessage = nil
            task.nextQueueRetryAt = nil
            switch settings?.downloadRestartPolicy ?? .restorePaused {
            case .restorePaused:
                task.status = .paused
                task.appendLog(L10n.string("log_restored_paused_after_restart"))
            case .autoResume:
                task.status = .queued
                task.appendLog(L10n.string("log_restored_queued_after_restart"))
            }
        }
        save()
        if settings?.downloadRestartPolicy == .autoResume {
            scheduleQueue()
        }
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
        let descriptor = FetchDescriptor<DownloadTask>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return sortedTasks((try? modelContext.fetch(descriptor)) ?? [])
    }

    func sortedTasks(_ tasks: [DownloadTask]) -> [DownloadTask] {
        tasks.sorted(by: Self.queuePrecedes)
    }

    func moveQueueItemToTop(_ task: DownloadTask) {
        guard task.isQueueManageable else { return }
        var queueTasks = queueManageableTasks().filter { $0.id != task.id }
        queueTasks.insert(task, at: 0)
        rewriteQueuePositions(queueTasks)
        task.appendLog(L10n.string("log_queue_moved_top"))
        save()
        scheduleQueue()
    }

    func moveQueueItemUp(_ task: DownloadTask) {
        moveQueueItem(task, offset: -1)
    }

    func moveQueueItemDown(_ task: DownloadTask) {
        moveQueueItem(task, offset: 1)
    }

    func setQueuePriority(_ task: DownloadTask, priority: DownloadQueuePriority) {
        guard task.queuePriority != priority else { return }
        task.queuePriority = priority
        task.appendLog(L10n.string("log_queue_priority_changed", priority.title))
        save()
        scheduleQueue()
    }

    @discardableResult
    func add(
        source: String,
        saveDirectory: URL? = nil,
        suggestedFilename: String? = nil,
        browserContext: BrowserDownloadContext? = nil,
        httpOptions: HTTPDownloadOptions? = nil
    ) -> [DownloadTask] {
        let sources = SourceParser.extractSources(from: source)
        let saveDirectory = saveDirectory ?? settings?.defaultDownloadDirectory ?? AppDefaults.downloadDirectory
        let tasks = sources.map { source in
            let kind = SourceParser.kind(for: source)
            let creationSuggestedFilename = sources.count == 1 ? suggestedFilename : nil
            let displayName = displayName(
                for: source,
                kind: kind,
                suggestedFilename: creationSuggestedFilename,
                sourceCount: sources.count
            )
            let task = DownloadTask(
                name: displayName,
                source: source,
                kind: kind,
                savePath: saveDirectory.appendingPathComponent(displayName).path,
                browserContext: browserContext?.persistable,
                httpResponseMetadata: kind == .http
                    ? HTTPResponseMetadata.fromCreationContext(
                        source: source,
                        browserContext: browserContext,
                        suggestedFilename: creationSuggestedFilename
                    )
                    : nil,
                httpOptions: kind == .http ? httpOptions : nil
            )
            if task.isTorrent {
                task.applyTorrentLayout(saveDirectory: saveDirectory, outputName: displayName)
            }
            configureTorrentDefaults(for: task)
            task.appendLog(L10n.string("log_task_created"))
            return task
        }

        guard let modelContext else { return tasks }
        assignQueuePositions(to: tasks)
        for task in tasks {
            modelContext.insert(task)
            if let browserContext {
                runtimeBrowserContexts[task.id] = browserContext
            }
            if task.kind == .http, let httpOptions {
                runtimeHTTPOptions[task.id] = httpOptions
            }
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
        filePriorities: [String: [Int: Int]] = [:],
        httpOptions: HTTPDownloadOptions? = nil
    ) -> [DownloadTask] {
        let saveDirectory = saveDirectory ?? settings?.defaultDownloadDirectory ?? AppDefaults.downloadDirectory
        let tasks = previews.map { preview in
            let savePath = preview.kind == .http
                ? preview.savePath ?? saveDirectory.appendingPathComponent(preview.displayName).path
                : saveDirectory.path
            let task = DownloadTask(
                name: preview.displayName,
                source: preview.source,
                kind: preview.kind,
                savePath: savePath,
                totalBytes: preview.totalBytes,
                supportsResume: preview.kind == .http
                    ? preview.supportsResume
                    : preview.kind == .torrentMagnet || preview.kind == .torrentFile,
                resolvedTorrentFilePath: preview.resolvedTorrentFilePath,
                torrentMetadataStatus: preview.metadataStatus,
                selectedFileIndexes: selectedFileIndexes[preview.source] ?? preview.selectedFileIndexes,
                browserContext: preview.browserContext?.persistable,
                httpResponseMetadata: preview.kind == .http
                    ? preview.httpResponseMetadata
                    : nil,
                httpOptions: preview.kind == .http ? httpOptions : nil
            )
            var files = preview.files
            if let priorities = filePriorities[preview.source] {
                for index in files.indices {
                    files[index].priority = priorities[files[index].index] ?? files[index].priority
                }
            }
            task.torrentFiles = files
            if task.isTorrent {
                task.applyTorrentLayout(
                    saveDirectory: saveDirectory,
                    outputName: preview.displayName,
                    files: files,
                    isMultiFile: preview.resolvedTorrentFilePath.flatMap { path in
                        (try? TorrentMetainfo.parse(url: URL(fileURLWithPath: path)))?.isMultiFile
                    }
                )
            }
            configureTorrentDefaults(for: task)
            task.appendLog(L10n.string("log_task_created"))
            if let errorMessage = preview.errorMessage {
                task.appendLog(errorMessage)
            }
            return task
        }

        guard let modelContext else { return tasks }
        assignQueuePositions(to: tasks)
        for task in tasks {
            modelContext.insert(task)
            if let preview = previews.first(where: { $0.source == task.source }),
               let browserContext = preview.browserContext
            {
                runtimeBrowserContexts[task.id] = browserContext
            }
            if task.kind == .http, let httpOptions {
                runtimeHTTPOptions[task.id] = httpOptions
            }
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

        let sanitizedFilename = SourceParser.sanitizeFilename(suggestedFilename)
        return sanitizedFilename.isEmpty ? SourceParser.displayName(for: source, kind: kind) : sanitizedFilename
    }

    func start(_ task: DownloadTask) {
        start(task, resetsQueueFailureState: true)
    }

    private func start(_ task: DownloadTask, resetsQueueFailureState: Bool) {
        task.status = .running
        task.errorMessage = nil
        task.retryCount = 0
        task.nextQueueRetryAt = nil
        if resetsQueueFailureState {
            task.queueFailureCount = 0
        }
        task.appendLog(L10n.string("log_start_download"))
        let request = DownloadRequest(
            task: task,
            browserContext: runtimeBrowserContexts[task.id] ?? task.browserContext,
            httpOptions: runtimeHTTPOptions[task.id] ?? task.httpOptions
        )
        save()

        guard runsEngines else { return }
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
        pause(task, schedulesQueueAfterFreeingSlot: true)
    }

    private func pause(_ task: DownloadTask, schedulesQueueAfterFreeingSlot: Bool) {
        let shouldScheduleQueue = schedulesQueueAfterFreeingSlot && task.usesActiveDownloadSlot
        task.status = .paused
        task.speedBytesPerSecond = 0
        task.nextQueueRetryAt = nil
        task.appendLog(L10n.string("log_paused"))
        let request = DownloadRequest(task: task)
        save()

        if runsEngines {
            Task {
                await engine(for: request.kind).pause(request)
                if shouldScheduleQueue {
                    scheduleQueue()
                }
            }
        } else if shouldScheduleQueue {
            scheduleQueue()
        }
    }

    private func runEngineOperation(
        schedulesQueueAfterFreeingSlot shouldScheduleQueue: Bool,
        operation: @escaping @MainActor () async -> Void
    ) {
        if runsEngines {
            Task {
                await operation()
                if shouldScheduleQueue {
                    scheduleQueue()
                }
            }
        } else if shouldScheduleQueue {
            scheduleQueue()
        }
    }

    func resume(_ task: DownloadTask) {
        task.status = .queued
        task.errorMessage = nil
        task.speedBytesPerSecond = 0
        task.nextQueueRetryAt = nil
        if task.queueFailureCount > 0 {
            task.queueFailureCount = 0
        }
        task.appendLog(L10n.string("log_queued_for_resume"))
        save()
        scheduleQueue()
    }

    func retry(_ task: DownloadTask) {
        guard task.status == .failed || task.status == .cancelled || task.status == .paused else { return }
        task.appendLog(L10n.string("log_retry_task"))
        resume(task)
    }

    func cancel(_ task: DownloadTask) {
        let shouldScheduleQueue = task.usesActiveDownloadSlot
        task.status = .cancelled
        task.speedBytesPerSecond = 0
        task.errorMessage = L10n.string("error_task_cancelled")
        task.nextQueueRetryAt = nil
        task.queueFailureCount = 0
        task.appendLog(L10n.string("log_task_cancelled"))
        let request = DownloadRequest(task: task)
        save()

        runEngineOperation(schedulesQueueAfterFreeingSlot: shouldScheduleQueue) {
            await self.engine(for: request.kind).cancel(request)
        }
    }

    func remove(_ task: DownloadTask, deletingFiles: Bool) {
        guard let modelContext else { return }
        let shouldScheduleQueue = task.usesActiveDownloadSlot
        let localDeletionURLs = task.localContentDeletionURLs
        let shouldDeleteLocalData = deletingFiles && (task.kind == .http || !localDeletionURLs.isEmpty)
        let request = DownloadRequest(task: task)

        if shouldDeleteLocalData {
            if task.kind == .http {
                try? FileManager.default.removeItem(atPath: task.savePath)
                HTTPPartialDataStore(savePath: task.savePath).removeData()
            } else {
                for deletionURL in localDeletionURLs {
                    try? FileManager.default.removeItem(at: deletionURL)
                }
            }
        }
        if task.kind == .torrentMagnet || task.kind == .torrentFile {
            TorrentResumeStore.removeResumeData(for: task.id)
        }
        runtimeBrowserContexts[task.id] = nil
        runtimeHTTPOptions[task.id] = nil
        modelContext.delete(task)
        if selectedTaskID == task.id {
            selectedTaskID = tasks().first?.id
        }
        save()

        runEngineOperation(schedulesQueueAfterFreeingSlot: shouldScheduleQueue) {
            await self.engine(for: request.kind).remove(request, deletingFiles: shouldDeleteLocalData)
        }
    }

    func deletePartialData(_ task: DownloadTask) {
        guard task.kind == .http else { return }
        HTTPPartialDataStore(savePath: task.savePath).removeData()
        if !task.hasFinishedDownloading {
            task.downloadedBytes = 0
            task.speedBytesPerSecond = 0
        }
        task.appendLog(L10n.string("log_deleted_partial_data"))
        save()
    }

    func retainPartialData(_ task: DownloadTask) {
        guard task.kind == .http else { return }
        let store = HTTPPartialDataStore(savePath: task.savePath)
        guard store.hasData else { return }
        task.downloadedBytes = max(task.downloadedBytes, store.downloadedBytes)
        task.speedBytesPerSecond = 0
        task.appendLog(L10n.string("log_retained_partial_data"))
        save()
    }

    func openPartialData(_ task: DownloadTask) {
        guard task.kind == .http,
              let url = HTTPPartialDataStore(savePath: task.savePath).preferredDataURL
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealPartialData(_ task: DownloadTask) {
        guard task.kind == .http else { return }
        guard let url = HTTPPartialDataStore(savePath: task.savePath).preferredDataURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyErrorMessage(_ task: DownloadTask) {
        guard let errorMessage = task.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !errorMessage.isEmpty
        else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(errorMessage, forType: .string)
        task.appendLog(L10n.string("log_copied_error"))
        save()
    }

    func renameAndContinue(_ task: DownloadTask) {
        guard task.kind == .http,
              task.status == .failed || task.status == .cancelled || task.status == .paused
        else {
            return
        }
        let currentURL = URL(fileURLWithPath: task.savePath)
        let resolvedURL = Self.nextContinuationURL(for: currentURL)

        do {
            try HTTPPartialDataStore(savePath: task.savePath).moveData(to: resolvedURL.path)
            task.savePath = resolvedURL.path
            task.name = resolvedURL.lastPathComponent
            task.appendLog(L10n.string("log_renamed_and_queued", resolvedURL.lastPathComponent))
            resume(task)
        } catch {
            task.status = .failed
            task.errorMessage = error.localizedDescription
            task.appendLog(error.localizedDescription)
            save()
        }
    }

    func reprobeHTTPMetadata(_ task: DownloadTask) {
        guard task.kind == .http,
              let url = URL(string: task.source)
        else {
            return
        }
        let previousStatus = task.status
        task.status = .verifying
        task.speedBytesPerSecond = 0
        task.appendLog(L10n.string("log_reprobe_metadata_started"))
        let request = DownloadRequest(
            task: task,
            browserContext: runtimeBrowserContexts[task.id] ?? task.browserContext,
            httpOptions: runtimeHTTPOptions[task.id] ?? task.httpOptions
        )
        save()

        guard runsEngines else {
            task.status = previousStatus
            save()
            return
        }

        Task {
            let metadata = await HTTPMetadataProbe(
                segmentCount: settings?.httpSegmentCount ?? 1,
                probesRangeForIncompleteMetadata: true,
                timeoutInterval: 12
            ).probe(url: url, request: request)
            task.totalBytes = metadata.contentLength > 0 ? metadata.contentLength : task.totalBytes
            task.supportsResume = metadata.supportsResume
            task.eTag = metadata.eTag ?? task.eTag
            task.lastModified = metadata.lastModified ?? task.lastModified
            if let responseMetadata = metadata.responseMetadata {
                task.httpResponseMetadata = responseMetadata.merged(over: task.httpResponseMetadata)
            }
            task.status = previousStatus == .running || previousStatus == .verifying ? .paused : previousStatus
            task.appendLog(L10n.string("log_reprobe_metadata_finished"))
            save()
        }
    }

    func recheck(_ task: DownloadTask) {
        task.status = .verifying
        task.nextQueueRetryAt = nil
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
        for task in allTasks() where task.status == .running || task.status == .seeding || task.status == .queued || task.status == .verifying {
            pause(task, schedulesQueueAfterFreeingSlot: false)
        }
    }

    func resumeAll() {
        for task in allTasks() where task.status == .paused || task.status == .failed || task.status == .cancelled || task.status == .queued {
            resume(task)
        }
    }

    func setSpeedLimit(
        downloadBytesPerSecond: Int64,
        uploadBytesPerSecond: Int64,
        persistsToSettings: Bool = false
    ) {
        downloadLimitBytes = downloadBytesPerSecond
        uploadLimitBytes = uploadBytesPerSecond
        if persistsToSettings, let settings {
            settings.globalDownloadLimitBytes = downloadBytesPerSecond
            settings.globalUploadLimitBytes = uploadBytesPerSecond
            persistSettings(settings)
        }
        if runsEngines {
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
    }

    private func persistSettings(_ settings: AppSettings) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<AppSettingsRecord>(
            predicate: #Predicate { $0.id == "default" }
        )

        do {
            if let record = try modelContext.fetch(descriptor).first {
                settings.update(record)
            } else {
                modelContext.insert(settings.makeRecord())
            }
            try modelContext.save()
        } catch {
            statusMessage = L10n.string("status_save_failed", error.localizedDescription)
        }
    }

    func scheduleQueue() {
        let now = Date()
        let tasks = allTasks()
        let running = tasks.filter(\.usesActiveDownloadSlot).count
        let availableSlots = max(0, (settings?.concurrentTaskLimit ?? 3) - running)
        scheduleNextQueueWake(from: tasks, now: now)
        guard availableSlots > 0 else { return }

        for task in tasks
            .filter({ $0.status == .queued && $0.isQueueRetryDue(at: now) })
            .prefix(availableSlots)
        {
            start(task, resetsQueueFailureState: false)
        }
    }

    func apply(_ snapshot: DownloadSnapshot) {
        guard let modelContext else { return }
        let taskID = snapshot.taskID
        let descriptor = FetchDescriptor<DownloadTask>(
            predicate: #Predicate { $0.id == taskID }
        )
        guard let task = try? modelContext.fetch(descriptor).first else { return }
        if task.status == .cancelled {
            task.speedBytesPerSecond = 0
            task.downloadedBytes = max(task.downloadedBytes, snapshot.downloadedBytes)
            save()
            return
        }

        task.status = snapshot.status
        if let name = snapshot.name {
            task.name = name
        }
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
            if task.isTorrent {
                task.applyTorrentLayout(
                    saveDirectory: URL(fileURLWithPath: task.effectiveTorrentSaveDirectoryPath, isDirectory: true),
                    outputName: task.torrentOutputName,
                    files: snapshot.torrentFiles
                )
            }
        }
        if let connectionSummary = snapshot.connectionSummary {
            task.connectionSummary = connectionSummary
        }
        if let httpResponseMetadata = snapshot.httpResponseMetadata {
            task.httpResponseMetadata = httpResponseMetadata.merged(over: task.httpResponseMetadata)
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
            task.queueFailureCount = 0
            task.nextQueueRetryAt = nil
            if task.completedAt == nil {
                task.completedAt = .now
                task.appendLog(L10n.string("log_download_ready_seeding"))
                if settings?.completionNotificationsEnabled ?? true {
                    NotificationManager.notifyCompletion(for: task)
                }
                scheduleQueue()
            }
            runtimeBrowserContexts[task.id] = nil
            runtimeHTTPOptions[task.id] = nil
        case .completed:
            task.speedBytesPerSecond = 0
            task.queueFailureCount = 0
            task.nextQueueRetryAt = nil
            if task.completedAt == nil {
                task.completedAt = .now
                task.appendLog(L10n.string("log_download_completed"))
                if settings?.completionNotificationsEnabled ?? true {
                    NotificationManager.notifyCompletion(for: task)
                }
                scheduleQueue()
            }
            runtimeBrowserContexts[task.id] = nil
            runtimeHTTPOptions[task.id] = nil
        case .failed:
            task.speedBytesPerSecond = 0
            handleFailedTask(task, message: snapshot.errorMessage ?? L10n.string("error_download_failed"))
            scheduleQueue()
            runtimeBrowserContexts[task.id] = nil
            runtimeHTTPOptions[task.id] = nil
        case .cancelled:
            task.speedBytesPerSecond = 0
            task.nextQueueRetryAt = nil
            task.appendLog(L10n.string("log_task_cancelled"))
            scheduleQueue()
            runtimeBrowserContexts[task.id] = nil
            runtimeHTTPOptions[task.id] = nil
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

    private func moveQueueItem(_ task: DownloadTask, offset: Int) {
        var queueTasks = queueManageableTasks()
        guard task.isQueueManageable,
              let index = queueTasks.firstIndex(where: { $0.id == task.id })
        else {
            return
        }
        let targetIndex = index + offset
        guard targetIndex >= 0,
              targetIndex < queueTasks.count
        else {
            return
        }

        queueTasks.swapAt(index, targetIndex)
        rewriteQueuePositions(queueTasks)
        task.appendLog(offset < 0 ? L10n.string("log_queue_moved_up") : L10n.string("log_queue_moved_down"))
        save()
        scheduleQueue()
    }

    private func queueManageableTasks() -> [DownloadTask] {
        allTasks().filter(\.isQueueManageable)
    }

    private func rewriteQueuePositions(_ tasks: [DownloadTask]) {
        for (index, task) in tasks.enumerated() {
            task.queuePosition = Double(index + 1)
        }
    }

    private func handleFailedTask(_ task: DownloadTask, message: String) {
        let shouldRequeue = settings?.automaticallyRequeuesFailedTasks == true
            && task.queueFailureCount < max(0, settings?.queueFailureRetryLimit ?? 0)
            && message != L10n.string("error_task_cancelled")

        if shouldRequeue {
            task.queueFailureCount += 1
            task.status = .queued
            task.errorMessage = message
            task.nextQueueRetryAt = Date().addingTimeInterval(Self.queueRetryDelay(for: task.queueFailureCount))
            task.appendLog(L10n.string("log_queue_retry_scheduled", task.queueFailureCount))
            return
        }

        task.status = .failed
        task.nextQueueRetryAt = nil
        task.appendLog(message)
    }

    private func normalizeMissingQueuePositions() {
        let tasks = allTasks()
        var nextPosition = tasks.map(\.effectiveQueuePosition).max() ?? 0
        var didChange = false
        for task in tasks where task.queuePosition <= 0 {
            nextPosition += 1
            task.queuePosition = nextPosition
            didChange = true
        }
        if didChange {
            save()
        }
    }

    private func assignQueuePositions(to tasks: [DownloadTask]) {
        var nextPosition = allTasks().map(\.effectiveQueuePosition).max() ?? 0
        for task in tasks where task.queuePosition <= 0 {
            nextPosition += 1
            task.queuePosition = nextPosition
        }
    }

    private func scheduleNextQueueWake(from tasks: [DownloadTask], now: Date) {
        let nextDate = tasks
            .filter { $0.status == .queued }
            .compactMap(\.nextQueueRetryAt)
            .filter { $0 > now }
            .min()
        guard nextDate != queueWakeDate else { return }

        queueWakeTask?.cancel()
        queueWakeDate = nextDate
        guard let nextDate else {
            queueWakeTask = nil
            return
        }

        queueWakeTask = Task { [weak self] in
            let delay = max(0, nextDate.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.queueWakeDate = nil
                self?.queueWakeTask = nil
                self?.scheduleQueue()
            }
        }
    }

    private static func queuePrecedes(_ lhs: DownloadTask, _ rhs: DownloadTask) -> Bool {
        if lhs.usesActiveDownloadSlot != rhs.usesActiveDownloadSlot {
            return lhs.usesActiveDownloadSlot
        }

        if lhs.isQueueManageable && rhs.isQueueManageable {
            if lhs.queuePriorityRawValue != rhs.queuePriorityRawValue {
                return lhs.queuePriorityRawValue < rhs.queuePriorityRawValue
            }
            if lhs.effectiveQueuePosition != rhs.effectiveQueuePosition {
                return lhs.effectiveQueuePosition < rhs.effectiveQueuePosition
            }
        } else if lhs.isQueueManageable != rhs.isQueueManageable {
            return lhs.isQueueManageable
        } else if statusSortRank(lhs.status) != statusSortRank(rhs.status) {
            return statusSortRank(lhs.status) < statusSortRank(rhs.status)
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func statusSortRank(_ status: DownloadStatus) -> Int {
        switch status {
        case .running:
            0
        case .verifying:
            1
        case .queued:
            2
        case .paused:
            3
        case .failed:
            4
        case .cancelled:
            5
        case .seeding:
            6
        case .completed:
            7
        }
    }

    private static func nextContinuationURL(for url: URL) -> URL {
        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension

        var index = 2
        while true {
            let filename = pathExtension.isEmpty
                ? "\(baseName) \(index)"
                : "\(baseName) \(index).\(pathExtension)"
            let candidate = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: candidate.path),
               !HTTPPartialDataStore(savePath: candidate.path).hasData
            {
                return candidate
            }
            index += 1
        }
    }

    private static func queueRetryDelay(for failureCount: Int) -> TimeInterval {
        let attempt = max(1, failureCount)
        return min(300, pow(2, Double(attempt - 1)) * 30)
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
    case cancelled
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
        case .cancelled: L10n.string("download_status_cancelled")
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
        case .cancelled: "xmark.circle"
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
        case .cancelled:
            task.status == .cancelled
        case .http:
            task.kind == .http
        case .torrent:
            task.kind == .torrentMagnet || task.kind == .torrentFile
        }
    }
}
