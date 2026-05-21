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
    var selectedTaskIDs = Set<UUID>()
    var activeFilter: DownloadFilter = .all
    var activeCategory: DownloadTaskCategory?
    var activeTag: String?
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

    var selectedTasks: [DownloadTask] {
        let ids = effectiveSelectedTaskIDs
        guard !ids.isEmpty else { return [] }
        return allTasks().filter { ids.contains($0.id) }
    }

    var effectiveSelectedTaskIDs: Set<UUID> {
        if selectedTaskIDs.isEmpty, let selectedTaskID {
            return [selectedTaskID]
        }
        return selectedTaskIDs
    }

    var selectedTaskCount: Int {
        effectiveSelectedTaskIDs.count
    }

    var activeListTitle: String {
        if let activeCategory {
            return activeCategory.title
        }
        if let activeTag {
            return "#\(activeTag)"
        }
        return activeFilter.title
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
        SystemBehaviorController.shared.applyLaunchAtLogin(enabled: settings.launchAtLoginEnabled)
        normalizeMissingQueuePositions()
        updateSleepPrevention()
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
        SystemBehaviorController.shared.applyLaunchAtLogin(enabled: settings.launchAtLoginEnabled)
        scheduleQueue()
        updateSleepPrevention()
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
        for task in tasks where task.usesActiveDownloadSlot || task.status == .seeding {
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
        return filteredTasks(from: allTasks, filter: filter)
    }

    func filteredTasks(from tasks: [DownloadTask]) -> [DownloadTask] {
        filteredTasks(from: tasks, filter: activeFilter)
    }

    func filteredTasks(from tasks: [DownloadTask], filter: DownloadFilter) -> [DownloadTask] {
        sortedTasks(tasks.filter { task in
            let matchesFilter = filter.matches(task)
            let matchesCategory = activeCategory.map { task.category == $0 && !task.isArchived } ?? true
            let matchesTag = activeTag.map { tag in
                task.normalizedTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                    && !task.isArchived
            } ?? true
            let matchesSearch = searchText.isEmpty
                || task.name.localizedCaseInsensitiveContains(searchText)
                || task.source.localizedCaseInsensitiveContains(searchText)
                || task.category.title.localizedCaseInsensitiveContains(searchText)
                || task.normalizedTags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesFilter && matchesCategory && matchesTag && matchesSearch
        })
    }

    func selectFilter(_ filter: DownloadFilter) {
        activeFilter = filter
        activeCategory = nil
        activeTag = nil
    }

    func selectCategory(_ category: DownloadTaskCategory) {
        activeFilter = .all
        activeCategory = category
        activeTag = nil
    }

    func selectTag(_ tag: String) {
        let normalized = Self.normalizedTag(tag)
        guard !normalized.isEmpty else { return }
        activeFilter = .all
        activeCategory = nil
        activeTag = normalized
    }

    func clearSmartFilter() {
        activeCategory = nil
        activeTag = nil
    }

    func categories(in tasks: [DownloadTask]) -> [DownloadTaskCategory] {
        let present = Set(tasks.filter { !$0.isArchived }.map(\.category))
        return DownloadTaskCategory.allCases.filter { present.contains($0) }
    }

    func tags(in tasks: [DownloadTask]) -> [String] {
        var seen = Set<String>()
        return tasks
            .filter { !$0.isArchived }
            .flatMap(\.normalizedTags)
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func allTasks() -> [DownloadTask] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<DownloadTask>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return sortedTasks((try? modelContext.fetch(descriptor)) ?? [])
    }

    var hasActiveDownloadsForSystemPolicy: Bool {
        allTasks().contains { !$0.isArchived && ($0.usesActiveDownloadSlot || $0.status == .seeding) }
    }

    func pauseActiveTasksForQuit() {
        for task in allTasks() where !task.isArchived && (task.usesActiveDownloadSlot || task.status == .seeding || task.status == .queued) {
            pause(task, schedulesQueueAfterFreeingSlot: false)
        }
        updateSleepPrevention()
    }

    func sortedTasks(_ tasks: [DownloadTask]) -> [DownloadTask] {
        tasks.sorted(by: Self.queuePrecedes)
    }

    func selectOnly(_ task: DownloadTask) {
        selectedTaskID = task.id
        selectedTaskIDs = [task.id]
    }

    func toggleSelection(_ task: DownloadTask) {
        if selectedTaskIDs.isEmpty, let selectedTaskID {
            selectedTaskIDs = [selectedTaskID]
        }
        if selectedTaskIDs.contains(task.id) {
            selectedTaskIDs.remove(task.id)
            if selectedTaskID == task.id {
                selectedTaskID = selectedTaskIDs.first
            }
        } else {
            selectedTaskIDs.insert(task.id)
            selectedTaskID = task.id
        }
    }

    func selectAllVisible(_ tasks: [DownloadTask]) {
        let ids = Set(tasks.map(\.id))
        selectedTaskIDs = ids
        selectedTaskID = tasks.first?.id
    }

    func clearSelection() {
        selectedTaskID = nil
        selectedTaskIDs.removeAll()
    }

    func pruneSelection() {
        let existingIDs = Set(allTasks().map(\.id))
        selectedTaskIDs = selectedTaskIDs.intersection(existingIDs)
        if let selectedTaskID, !existingIDs.contains(selectedTaskID) {
            self.selectedTaskID = selectedTaskIDs.first
        }
        if selectedTaskIDs.isEmpty, selectedTaskID == nil {
            clearSelection()
        }
    }

    func moveQueueItemToTop(_ task: DownloadTask) {
        guard task.isQueueManageable, !task.isArchived else { return }
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
        guard !task.isArchived, task.queuePriority != priority else { return }
        task.queuePriority = priority
        task.appendLog(L10n.string("log_queue_priority_changed", priority.title))
        save()
        scheduleQueue()
    }

    func pauseSelected() {
        let tasks = selectedTasks.filter {
            !$0.isArchived && ($0.usesActiveDownloadSlot || $0.status == .seeding || $0.status == .queued)
        }
        guard !tasks.isEmpty else { return }
        for task in tasks {
            pause(task, schedulesQueueAfterFreeingSlot: false)
        }
        scheduleQueue()
    }

    func resumeSelected() {
        let tasks = selectedTasks.filter {
            !$0.isArchived
                && ($0.status == .paused || $0.status == .failed || $0.status == .cancelled || $0.status == .queued)
        }
        guard !tasks.isEmpty else { return }
        for task in tasks {
            resume(task)
        }
    }

    func cancelSelected() {
        let tasks = selectedTasks.filter { !$0.isArchived && !$0.isTerminal }
        guard !tasks.isEmpty else { return }
        for task in tasks {
            cancel(task)
        }
    }

    func retrySelected() {
        let tasks = selectedTasks.filter {
            !$0.isArchived && ($0.status == .failed || $0.status == .cancelled || $0.status == .paused)
        }
        guard !tasks.isEmpty else { return }
        for task in tasks {
            retry(task)
        }
    }

    func recheckSelected() {
        let tasks = selectedTasks.filter { !$0.isArchived }
        guard !tasks.isEmpty else { return }
        for task in tasks {
            recheck(task)
        }
    }

    func revealSelectedInFinder() {
        let urls = selectedTasks.map(\.revealURL)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func removeSelected(deletingFiles: Bool) {
        let tasks = selectedTasks
        guard !tasks.isEmpty else { return }
        for task in tasks {
            remove(task, deletingFiles: deletingFiles)
        }
        pruneSelection()
    }

    func moveSelectedToTop() {
        let selectedIDs = effectiveSelectedTaskIDs
        var queueTasks = queueManageableTasks()
        let selected = queueTasks.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        queueTasks.removeAll { selectedIDs.contains($0.id) }
        queueTasks.insert(contentsOf: selected, at: 0)
        rewriteQueuePositions(queueTasks)
        for task in selected {
            task.appendLog(L10n.string("log_queue_moved_top"))
        }
        save()
        scheduleQueue()
    }

    func moveSelectedUp() {
        moveSelectedQueueItems(offset: -1)
    }

    func moveSelectedDown() {
        moveSelectedQueueItems(offset: 1)
    }

    func setSelectedQueuePriority(_ priority: DownloadQueuePriority) {
        let tasks = selectedTasks.filter { !$0.isArchived && $0.isQueueManageable }
        guard !tasks.isEmpty else { return }
        for task in tasks where task.queuePriority != priority {
            task.queuePriority = priority
            task.appendLog(L10n.string("log_queue_priority_changed", priority.title))
        }
        save()
        scheduleQueue()
    }

    func setSelectedDownloadLimit(_ bytesPerSecond: Int64) {
        setSelectedSpeedLimit(downloadBytesPerSecond: bytesPerSecond, uploadBytesPerSecond: 0)
    }

    func setSelectedSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) {
        let downloadLimit = downloadBytesPerSecond > 0 ? downloadBytesPerSecond : nil
        let uploadLimit = max(0, uploadBytesPerSecond)
        let tasks = selectedTasks.filter { !$0.isArchived }
        guard !tasks.isEmpty else { return }
        for task in tasks {
            task.perTaskDownloadLimitBytes = max(0, downloadBytesPerSecond)
            task.perTaskUploadLimitBytes = uploadLimit
            if task.kind == .http {
                let options = runtimeHTTPOptions[task.id] ?? task.httpOptions ?? HTTPDownloadOptions()
                let updated = HTTPDownloadOptions(
                    segmentCountOverride: options.segmentCountOverride,
                    retryLimitOverride: options.retryLimitOverride,
                    perTaskDownloadLimitBytes: downloadLimit,
                    filenameOverride: options.filenameOverride,
                    additionalHeaders: options.additionalHeaders
                )
                task.httpOptions = updated
                runtimeHTTPOptions[task.id] = updated
            }
            task.appendLog(L10n.string("log_batch_speed_limit_changed", formattedSpeedLimit(downloadBytesPerSecond)))
        }
        save()
    }

    func setSelectedCategory(_ category: DownloadTaskCategory) {
        let tasks = selectedTasks
        guard !tasks.isEmpty else { return }
        for task in tasks {
            task.category = category
            task.appendLog(L10n.string("log_category_changed", category.title))
        }
        save()
    }

    func setSelectedTags(_ tags: [String]) {
        let normalizedTags = DownloadTask.normalizedTagList(tags)
        let tasks = selectedTasks
        guard !tasks.isEmpty else { return }
        for task in tasks {
            task.tags = normalizedTags
            task.appendLog(L10n.string("log_tags_changed", normalizedTags.joined(separator: ", ")))
        }
        save()
    }

    func archiveSelected() {
        archiveTasks(selectedTasks)
    }

    func unarchiveSelected() {
        let tasks = selectedTasks.filter(\.isArchived)
        guard !tasks.isEmpty else { return }
        for task in tasks {
            task.archivedAt = nil
            task.appendLog(L10n.string("log_unarchived_task"))
        }
        save()
        scheduleQueue()
    }

    func archiveCompletedTasks() {
        archiveTasks(allTasks().filter { !$0.isArchived && $0.hasFinishedDownloading })
    }

    func archiveFailedTasks() {
        archiveTasks(allTasks().filter { !$0.isArchived && ($0.status == .failed || $0.status == .cancelled) })
    }

    func cleanupCompletedAndFailed(deletingFiles: Bool) {
        let tasks = allTasks().filter {
            !$0.isArchived
                && ($0.status == .completed || $0.status == .failed || $0.status == .cancelled)
        }
        guard !tasks.isEmpty else { return }
        for task in tasks {
            remove(task, deletingFiles: deletingFiles)
        }
        pruneSelection()
    }

    func removeArchivedTaskRecords() {
        let tasks = allTasks().filter(\.isArchived)
        guard !tasks.isEmpty else { return }
        for task in tasks {
            remove(task, deletingFiles: false)
        }
    }

    func moveSelectedToDefaultDirectory() {
        let directory = settings?.defaultDownloadDirectory ?? AppDefaults.downloadDirectory
        moveSelected(toSaveDirectory: directory)
    }

    func moveSelected(toSaveDirectory directory: URL) {
        let tasks = selectedTasks.filter { !$0.isArchived }
        guard !tasks.isEmpty else { return }
        for task in tasks {
            move(task, toSaveDirectory: directory)
        }
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
            let initialDisplayName = displayName(
                for: source,
                kind: kind,
                suggestedFilename: creationSuggestedFilename,
                sourceCount: sources.count
            )
            let rule = matchingDownloadRule(
                source: source,
                kind: kind,
                filename: initialDisplayName,
                totalBytes: nil
            )
            let plannedURL = rule?.plannedSaveURL(
                fallbackURL: saveDirectory.appendingPathComponent(initialDisplayName),
                source: source,
                filename: initialDisplayName
            ) ?? saveDirectory.appendingPathComponent(initialDisplayName)
            let displayName = plannedURL.lastPathComponent
            let resolvedHTTPOptions = mergedHTTPOptions(
                explicitOptions: kind == .http ? httpOptions : nil,
                rule: rule
            )
            let task = DownloadTask(
                name: displayName,
                source: source,
                kind: kind,
                status: rule?.autoStart == false ? .paused : .queued,
                savePath: plannedURL.path,
                browserContext: browserContext?.persistable,
                httpResponseMetadata: kind == .http
                    ? HTTPResponseMetadata.fromCreationContext(
                        source: source,
                        browserContext: browserContext,
                        suggestedFilename: displayName
                    )
                    : nil,
                httpOptions: kind == .http ? resolvedHTTPOptions : nil
            )
            if task.isTorrent {
                task.applyTorrentLayout(
                    saveDirectory: plannedURL.deletingLastPathComponent(),
                    outputName: displayName
                )
            }
            task.category = DownloadTaskCategory.inferred(
                kind: kind,
                source: source,
                filename: displayName
            )
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
            if task.kind == .http, let httpOptions = task.httpOptions {
                runtimeHTTPOptions[task.id] = httpOptions
            }
        }
        if let firstTask = tasks.first {
            selectOnly(firstTask)
        }
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
            let fallbackURL = preview.kind == .http
                ? URL(fileURLWithPath: savePath)
                : saveDirectory.appendingPathComponent(preview.displayName)
            let rule = matchingDownloadRule(
                source: preview.source,
                kind: preview.kind,
                filename: preview.displayName,
                totalBytes: preview.totalBytes > 0 ? preview.totalBytes : nil
            )
            let plannedURL = rule?.plannedSaveURL(
                fallbackURL: fallbackURL,
                source: preview.source,
                filename: preview.displayName
            ) ?? fallbackURL
            let resolvedSavePath = preview.kind == .http ? plannedURL.path : plannedURL.deletingLastPathComponent().path
            let displayName = rule?.hasSavePathOverride == true
                ? plannedURL.lastPathComponent
                : preview.displayName
            let resolvedHTTPOptions = mergedHTTPOptions(
                explicitOptions: preview.kind == .http ? httpOptions : nil,
                rule: rule
            )
            let task = DownloadTask(
                name: displayName,
                source: preview.source,
                kind: preview.kind,
                status: rule?.autoStart == false ? .paused : .queued,
                savePath: resolvedSavePath,
                totalBytes: preview.totalBytes,
                supportsResume: preview.kind == .http
                    ? preview.supportsResume
                    : preview.kind == .torrentMagnet || preview.kind == .torrentFile,
                resolvedTorrentFilePath: preview.resolvedTorrentFilePath,
                torrentMetadataStatus: preview.metadataStatus,
                selectedFileIndexes: selectedFileIndexes[preview.source] ?? preview.selectedFileIndexes,
                browserContext: preview.browserContext?.persistable,
                httpResponseMetadata: preview.kind == .http
                    ? (preview.httpResponseMetadata ?? HTTPResponseMetadata.fromCreationContext(
                        source: preview.source,
                        browserContext: preview.browserContext,
                        totalBytes: preview.totalBytes
                    )).replacingSuggestedFilename(displayName)
                    : nil,
                httpOptions: preview.kind == .http ? resolvedHTTPOptions : nil
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
                    saveDirectory: plannedURL.deletingLastPathComponent(),
                    outputName: displayName,
                    files: files,
                    isMultiFile: preview.resolvedTorrentFilePath.flatMap { path in
                        (try? TorrentMetainfo.parse(url: URL(fileURLWithPath: path)))?.isMultiFile
                    }
                )
            }
            task.category = DownloadTaskCategory.inferred(
                kind: preview.kind,
                source: preview.source,
                filename: displayName
            )
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
            if task.kind == .http, let httpOptions = task.httpOptions {
                runtimeHTTPOptions[task.id] = httpOptions
            }
        }
        if let firstTask = tasks.first {
            selectOnly(firstTask)
        }
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
        guard !task.isArchived else { return }
        if task.startedAt == nil {
            task.startedAt = .now
        }
        task.finishedAt = nil
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
        updateSleepPrevention()

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

    private func matchingDownloadRule(
        source: String,
        kind: DownloadKind,
        filename: String,
        totalBytes: Int64?
    ) -> DownloadRule? {
        settings?.downloadRules.first {
            $0.matches(source: source, kind: kind, filename: filename, totalBytes: totalBytes)
        }
    }

    private func mergedHTTPOptions(
        explicitOptions: HTTPDownloadOptions?,
        rule: DownloadRule?
    ) -> HTTPDownloadOptions? {
        guard let rule else { return explicitOptions }
        let explicitOptions = explicitOptions ?? HTTPDownloadOptions()
        let mergedHeaders = explicitOptions.additionalHeaders + rule.headers.filter { ruleHeader in
            !explicitOptions.additionalHeaders.contains {
                $0.normalizedName == ruleHeader.normalizedName
            }
        }
        let merged = HTTPDownloadOptions(
            segmentCountOverride: explicitOptions.segmentCountOverride ?? rule.segmentCount,
            retryLimitOverride: explicitOptions.retryLimitOverride ?? rule.retryLimit,
            perTaskDownloadLimitBytes: explicitOptions.perTaskDownloadLimitBytes,
            filenameOverride: explicitOptions.filenameOverride,
            additionalHeaders: mergedHeaders
        )
        return merged.isEmpty ? nil : merged
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
        updateSleepPrevention()

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
        guard !task.isArchived else { return }
        task.status = .queued
        task.errorMessage = nil
        task.speedBytesPerSecond = 0
        task.finishedAt = nil
        task.nextQueueRetryAt = nil
        if task.queueFailureCount > 0 {
            task.queueFailureCount = 0
        }
        task.appendLog(L10n.string("log_queued_for_resume"))
        save()
        updateSleepPrevention()
        scheduleQueue()
    }

    func retry(_ task: DownloadTask) {
        guard !task.isArchived else { return }
        guard task.status == .failed || task.status == .cancelled || task.status == .paused else { return }
        task.appendLog(L10n.string("log_retry_task"))
        resume(task)
    }

    func cancel(_ task: DownloadTask) {
        let shouldScheduleQueue = task.usesActiveDownloadSlot
        task.status = .cancelled
        task.speedBytesPerSecond = 0
        task.finishedAt = .now
        task.errorMessage = L10n.string("error_task_cancelled")
        task.nextQueueRetryAt = nil
        task.queueFailureCount = 0
        task.appendLog(L10n.string("log_task_cancelled"))
        let request = DownloadRequest(task: task)
        save()
        updateSleepPrevention()

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
        selectedTaskIDs.remove(task.id)
        if selectedTaskID == task.id {
            selectedTaskID = selectedTaskIDs.first ?? filteredTasks(from: allTasks()).first?.id
        }
        save()
        updateSleepPrevention()

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

    func copyLogs(_ task: DownloadTask) {
        let text = Self.logExportText(for: task)
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        task.appendLog(L10n.string("log_copied_logs"))
        save()
    }

    @discardableResult
    func exportLogs(_ task: DownloadTask, to directory: URL? = nil) -> URL? {
        let text = Self.logExportText(for: task)
        guard !text.isEmpty else { return nil }

        let exportDirectory = directory
            ?? URL(fileURLWithPath: task.displaySavePath)
                .deletingLastPathComponent()
        let sanitizedName = SourceParser
            .sanitizeFilename(task.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let exportName = sanitizedName.isEmpty ? "swiftgetx-task" : sanitizedName
        let filename = "\(exportName)-swiftgetx.log"
        let destination = FileManager.default.uniqueFileURL(
            for: exportDirectory.appendingPathComponent(filename)
        )

        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: destination, atomically: true, encoding: .utf8)
            task.appendLog(L10n.string("log_exported_logs", destination.path))
            save()
            return destination
        } catch {
            task.appendLog(error.localizedDescription)
            save()
            return nil
        }
    }

    func clearLogs(_ task: DownloadTask) {
        guard !task.logEntries.isEmpty else { return }
        task.logEntries.removeAll()
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

    func move(_ task: DownloadTask, toSaveDirectory directory: URL) {
        let normalizedDirectory = directory.standardizedFileURL
        guard normalizedDirectory.isFileURL, !normalizedDirectory.path.isEmpty else { return }
        if task.isTorrent {
            relocateTorrent(task, toSaveDirectory: normalizedDirectory)
            return
        }

        let destination = FileManager.default.uniqueFileURL(
            for: normalizedDirectory.appendingPathComponent(task.name)
        )
        let oldPath = task.savePath
        let wasActive = task.usesActiveDownloadSlot
        let oldRequest = DownloadRequest(task: task)
        if wasActive {
            task.status = .paused
            task.speedBytesPerSecond = 0
            task.appendLog(L10n.string("log_paused_for_relocation"))
        }

        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try HTTPPartialDataStore(savePath: oldPath).moveData(to: destination.path)
            if FileManager.default.fileExists(atPath: oldPath),
               !FileManager.default.fileExists(atPath: destination.path)
            {
                try FileManager.default.moveItem(
                    at: URL(fileURLWithPath: oldPath),
                    to: destination
                )
            }
            task.savePath = destination.path
            task.name = destination.lastPathComponent
            task.appendLog(L10n.string("log_moved_task_file", destination.path))
            let request = DownloadRequest(task: task)
            save()

            guard runsEngines, wasActive else { return }
            Task {
                await engine(for: oldRequest.kind).pause(oldRequest)
                await engine(for: request.kind).recheck(request)
            }
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
        guard !task.isArchived else { return }
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
            if selected.contains(files[index].index) {
                files[index].priority = files[index].priorityLevel.isWanted
                    ? files[index].priority
                    : TorrentFilePriority.normal.rawValue
            } else {
                files[index].priority = TorrentFilePriority.skip.rawValue
            }
        }
        task.torrentFiles = files
        task.appendLog(L10n.string("log_updated_bt_file_selection", selectedFileIndexes.count))
        let request = DownloadRequest(task: task)
        save()

        guard runsEngines else { return }
        Task {
            await engine(for: request.kind).setFileSelection(request, selectedFileIndexes: selectedFileIndexes)
        }
    }

    func setTorrentFilePriority(_ task: DownloadTask, fileIndex: Int, priority: TorrentFilePriority) {
        setTorrentFilePriorities(task, fileIndexes: [fileIndex], priority: priority)
    }

    func setTorrentFilePriorities(_ task: DownloadTask, fileIndexes: [Int], priority: TorrentFilePriority) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        let targetIndexes = Set(fileIndexes)
        guard !targetIndexes.isEmpty else { return }
        var files = task.torrentFiles
        var updated = [TorrentFile]()
        for index in files.indices where targetIndexes.contains(files[index].index) {
            files[index].priority = priority.rawValue
            updated.append(files[index])
        }
        guard !updated.isEmpty else { return }
        task.torrentFiles = files
        task.selectedFileIndexes = files
            .filter { $0.priorityLevel.isWanted }
            .map(\.index)
            .sorted()
        if updated.count == 1, let file = updated.first {
            task.appendLog(L10n.string("log_updated_bt_file_priority", file.path, priority.title))
        } else {
            task.appendLog(L10n.string("log_updated_bt_file_priorities", updated.count, priority.title))
        }
        let request = DownloadRequest(task: task)
        save()

        guard runsEngines else { return }
        Task {
            for file in updated {
                await engine(for: request.kind).setTorrentFilePriority(
                    request,
                    fileIndex: file.index,
                    priority: priority.rawValue
                )
            }
        }
    }

    func setTorrentFolderPriority(_ task: DownloadTask, folderPath: String, priority: TorrentFilePriority) {
        let normalizedFolder = Self.normalizedTorrentFolderPath(folderPath)
        guard !normalizedFolder.isEmpty else { return }
        let indexes = task.torrentFiles
            .filter { Self.torrentFile($0, isInFolder: normalizedFolder) }
            .map(\.index)
        setTorrentFilePriorities(task, fileIndexes: indexes, priority: priority)
    }

    func setTorrentExtensionPriority(_ task: DownloadTask, extensionFilter: String, priority: TorrentFilePriority) {
        let extensions = Self.normalizedTorrentExtensions(from: extensionFilter)
        guard !extensions.isEmpty else { return }
        let indexes = task.torrentFiles
            .filter { file in
                extensions.contains(URL(fileURLWithPath: file.path).pathExtension.lowercased())
            }
            .map(\.index)
        guard !indexes.isEmpty else {
            task.appendLog(L10n.string("log_no_bt_files_matched_filter", extensionFilter))
            save()
            return
        }
        setTorrentFilePriorities(task, fileIndexes: indexes, priority: priority)
    }

    func setTorrentSequentialDownload(_ task: DownloadTask, enabled: Bool) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        var options = task.torrentRuntimeOptions ?? settings?.torrentRuntimeOptions ?? TorrentRuntimeOptions()
        options.isSequentialDownloadEnabled = enabled
        task.torrentRuntimeOptions = options
        task.appendLog(enabled ? L10n.string("log_enabled_sequential_download") : L10n.string("log_disabled_sequential_download"))
        let request = DownloadRequest(task: task)
        save()

        guard runsEngines else { return }
        Task {
            await engine(for: request.kind).setTorrentSequentialDownload(request, enabled: enabled)
        }
    }

    func setTorrentSeedingLimitMode(_ task: DownloadTask, mode: TorrentSeedingLimitMode) {
        setTorrentRuntimeOptions(task, logMessage: nil) { options in
            options.seedingLimitMode = mode
        }
    }

    func setTorrentStopSeedingAtRatio(_ task: DownloadTask, ratio: Double) {
        setTorrentRuntimeOptions(task, logMessage: nil) { options in
            options.stopSeedingAtRatio = ratio
        }
    }

    func setTorrentStopSeedingAfterSeconds(_ task: DownloadTask, seconds: TimeInterval) {
        setTorrentRuntimeOptions(task, logMessage: nil) { options in
            options.stopSeedingAfterSeconds = seconds
        }
    }

    private func setTorrentRuntimeOptions(
        _ task: DownloadTask,
        logMessage: String?,
        update: (inout TorrentRuntimeOptions) -> Void
    ) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        var options = task.torrentRuntimeOptions ?? settings?.torrentRuntimeOptions ?? TorrentRuntimeOptions()
        update(&options)
        task.torrentRuntimeOptions = options
        task.appendLog(logMessage ?? L10n.string("log_updated_bt_seeding_policy", options.seedingPolicyDescription))
        let request = DownloadRequest(task: task)
        save()

        guard runsEngines else { return }
        Task {
            await engine(for: request.kind).setTorrentRuntimeOptions(request, options: options)
        }
    }

    func addTorrentTracker(_ task: DownloadTask, url: String) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidTrackerURL(trimmed) else { return }
        var trackers = task.torrentTrackers
        guard !trackers.contains(where: { $0.url == trimmed }) else { return }
        trackers.append(TorrentTrackerInfo(url: trimmed, tier: 0, status: L10n.string("torrent_tracker_waiting")))
        task.torrentTrackers = trackers
        task.appendLog(L10n.string("log_added_tracker", trimmed))
        let request = DownloadRequest(task: task)
        save()

        guard runsEngines else { return }
        Task {
            await engine(for: request.kind).addTorrentTracker(request, url: trimmed)
        }
    }

    func addTorrentTrackers(_ task: DownloadTask, urlsText: String) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        let urls = Self.trackerURLs(from: urlsText)
        guard !urls.isEmpty else { return }
        let existing = Set(task.torrentTrackers.map(\.url))
        let newURLs = urls.filter { !existing.contains($0) }
        guard !newURLs.isEmpty else { return }
        var trackers = task.torrentTrackers
        trackers.append(contentsOf: newURLs.map {
            TorrentTrackerInfo(url: $0, tier: 0, status: L10n.string("torrent_tracker_waiting"))
        })
        task.torrentTrackers = trackers
        task.appendLog(L10n.string("log_added_trackers", newURLs.count))
        let request = DownloadRequest(task: task)
        save()

        guard runsEngines else { return }
        Task {
            for url in newURLs {
                await engine(for: request.kind).addTorrentTracker(request, url: url)
            }
        }
    }

    func removeTorrentTracker(_ task: DownloadTask, url: String) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        guard task.torrentTrackers.contains(where: { $0.url == url }) else { return }
        task.torrentTrackers = task.torrentTrackers.filter { $0.url != url }
        task.appendLog(L10n.string("log_removed_tracker", url))
        let request = DownloadRequest(task: task)
        save()

        guard runsEngines else { return }
        Task {
            await engine(for: request.kind).removeTorrentTracker(request, url: url)
        }
    }

    func removeTorrentTrackers(_ task: DownloadTask, urls: [String]) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        let removalURLs = Set(urls)
        guard !removalURLs.isEmpty else { return }
        let existingURLs = Set(task.torrentTrackers.map(\.url))
        let removed = removalURLs.intersection(existingURLs)
        guard !removed.isEmpty else { return }
        task.torrentTrackers = task.torrentTrackers.filter { !removed.contains($0.url) }
        task.appendLog(L10n.string("log_removed_trackers", removed.count))
        let request = DownloadRequest(task: task)
        save()

        guard runsEngines else { return }
        Task {
            for url in removed {
                await engine(for: request.kind).removeTorrentTracker(request, url: url)
            }
        }
    }

    func relocateTorrent(_ task: DownloadTask, toSaveDirectoryPath path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        relocateTorrent(task, toSaveDirectory: URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath, isDirectory: true))
    }

    func relocateTorrent(_ task: DownloadTask, toSaveDirectory newSaveDirectory: URL) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        let normalizedDirectory = newSaveDirectory.standardizedFileURL
        guard normalizedDirectory.isFileURL, !normalizedDirectory.path.isEmpty else { return }
        let wasActive = task.usesActiveDownloadSlot || task.status == .seeding
        let oldContentURLs = task.localContentDeletionURLs
        let outputName = task.effectiveTorrentOutputName
        let oldRequest = DownloadRequest(task: task)
        if wasActive {
            task.status = .paused
            task.speedBytesPerSecond = 0
            task.appendLog(L10n.string("log_paused_for_relocation"))
        }
        task.applyTorrentLayout(
            saveDirectory: normalizedDirectory,
            outputName: outputName,
            files: task.torrentFiles
        )
        let newContentURLs = task.localContentDeletionURLs
        let movedCount = moveTorrentContentIfSafe(from: oldContentURLs, to: newContentURLs)
        task.appendLog(L10n.string("log_relocated_torrent", normalizedDirectory.path))
        if movedCount > 0 {
            task.appendLog(L10n.string("log_moved_torrent_content", movedCount))
        }
        let request = DownloadRequest(task: task)
        save()

        guard runsEngines else { return }
        Task {
            if wasActive {
                await engine(for: oldRequest.kind).pause(oldRequest)
            }
            await engine(for: request.kind).recheck(request)
        }
    }

    func forceTorrentReannounce(_ task: DownloadTask) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        task.appendLog(L10n.string("log_forced_tracker_announce"))
        let request = DownloadRequest(task: task)
        save()

        guard runsEngines else { return }
        Task {
            await engine(for: request.kind).forceTorrentReannounce(request)
        }
    }

    func pauseAll() {
        for task in allTasks() where !task.isArchived && (task.usesActiveDownloadSlot || task.status == .seeding || task.status == .queued) {
            pause(task, schedulesQueueAfterFreeingSlot: false)
        }
    }

    func resumeAll() {
        for task in allTasks() where !task.isArchived && (task.status == .paused || task.status == .failed || task.status == .cancelled || task.status == .queued) {
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
        let running = tasks.filter { !$0.isArchived && $0.usesActiveDownloadSlot }.count
        let availableSlots = max(0, (settings?.concurrentTaskLimit ?? 3) - running)
        scheduleNextQueueWake(from: tasks, now: now)
        guard availableSlots > 0 else { return }

        for task in tasks
            .filter({ !$0.isArchived && $0.status == .queued && $0.isQueueRetryDue(at: now) })
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

        let previousStatus = task.status
        task.status = snapshot.status
        updateTimingMetrics(for: task, snapshot: snapshot)
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
                task.selectedFileIndexes = snapshot.torrentFiles
                    .filter { $0.priorityLevel.isWanted }
                    .map(\.index)
                    .sorted()
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
        if let httpSegments = snapshot.httpSegments {
            task.httpSegments = httpSegments
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
                let finishedAt = task.finishedAt ?? Date()
                task.finishedAt = finishedAt
                task.completedAt = finishedAt
                task.appendLog(L10n.string("log_download_ready_seeding"))
                if settings?.completionNotificationsEnabled ?? true {
                    NotificationManager.notifyCompletion(for: task)
                }
                if let settings {
                    SystemBehaviorController.shared.performCompletionActions(for: task, settings: settings)
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
                let finishedAt = task.finishedAt ?? Date()
                task.finishedAt = finishedAt
                task.completedAt = finishedAt
                task.appendLog(L10n.string("log_download_completed"))
                if settings?.completionNotificationsEnabled ?? true {
                    NotificationManager.notifyCompletion(for: task)
                }
                if let settings {
                    SystemBehaviorController.shared.performCompletionActions(for: task, settings: settings)
                }
                scheduleQueue()
            } else if previousStatus == .seeding {
                task.appendLog(L10n.string("log_seeding_stopped"))
                if settings?.completionNotificationsEnabled ?? true {
                    NotificationManager.notifySeedingStopped(for: task)
                }
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
        updateSleepPrevention()
    }

    private func updateTimingMetrics(for task: DownloadTask, snapshot: DownloadSnapshot) {
        if snapshot.status.usesActiveClock, task.startedAt == nil {
            task.startedAt = .now
        }
        if snapshot.status.isTerminalForMetrics || snapshot.status == .seeding {
            if task.finishedAt == nil {
                task.finishedAt = .now
            }
        } else if snapshot.status.usesActiveClock {
            task.finishedAt = nil
        }

        task.peakSpeedBytesPerSecond = max(
            task.peakSpeedBytesPerSecond,
            snapshot.speedBytesPerSecond
        )

        guard let startedAt = task.startedAt else { return }
        let endDate = task.effectiveFinishedAt ?? Date()
        let elapsed = max(0, endDate.timeIntervalSince(startedAt))
        guard elapsed > 0, snapshot.downloadedBytes > 0 else { return }
        task.averageSpeedBytesPerSecond = max(
            0,
            Int64(Double(snapshot.downloadedBytes) / elapsed)
        )
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

    private func updateSleepPrevention() {
        SystemBehaviorController.shared.updateSleepPrevention(
            isEnabled: settings?.preventSleepDuringDownloads ?? true,
            hasActiveDownloads: hasActiveDownloadsForSystemPolicy
        )
    }

    private func moveTorrentContentIfSafe(from oldURLs: [URL], to newURLs: [URL]) -> Int {
        guard oldURLs.count == newURLs.count else { return 0 }
        var movedCount = 0
        for (oldURL, newURL) in zip(oldURLs, newURLs) {
            let oldURL = oldURL.standardizedFileURL
            let newURL = newURL.standardizedFileURL
            guard oldURL.path != newURL.path,
                  FileManager.default.fileExists(atPath: oldURL.path),
                  !FileManager.default.fileExists(atPath: newURL.path)
            else {
                continue
            }
            do {
                try FileManager.default.createDirectory(
                    at: newURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: oldURL, to: newURL)
                movedCount += 1
            } catch {
                statusMessage = L10n.string("status_save_failed", error.localizedDescription)
            }
        }
        return movedCount
    }

    private func moveQueueItem(_ task: DownloadTask, offset: Int) {
        var queueTasks = queueManageableTasks()
        guard task.isQueueManageable,
              !task.isArchived,
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

    private func moveSelectedQueueItems(offset: Int) {
        let selectedIDs = effectiveSelectedTaskIDs
        var queueTasks = queueManageableTasks()
        guard !selectedIDs.isEmpty else { return }
        if offset < 0 {
            for index in queueTasks.indices.dropFirst() where selectedIDs.contains(queueTasks[index].id) {
                let previousIndex = queueTasks.index(before: index)
                if !selectedIDs.contains(queueTasks[previousIndex].id) {
                    queueTasks.swapAt(index, previousIndex)
                }
            }
        } else {
            for index in queueTasks.indices.dropLast().reversed() where selectedIDs.contains(queueTasks[index].id) {
                let nextIndex = queueTasks.index(after: index)
                if !selectedIDs.contains(queueTasks[nextIndex].id) {
                    queueTasks.swapAt(index, nextIndex)
                }
            }
        }
        rewriteQueuePositions(queueTasks)
        for task in queueTasks where selectedIDs.contains(task.id) {
            task.appendLog(offset < 0 ? L10n.string("log_queue_moved_up") : L10n.string("log_queue_moved_down"))
        }
        save()
        scheduleQueue()
    }

    private func archiveTasks(_ tasks: [DownloadTask]) {
        let tasks = tasks.filter { !$0.isArchived }
        guard !tasks.isEmpty else { return }
        let now = Date()
        var activeRequests = [DownloadRequest]()
        for task in tasks {
            if task.usesActiveDownloadSlot || task.status == .seeding {
                activeRequests.append(DownloadRequest(task: task))
                task.status = .paused
                task.speedBytesPerSecond = 0
                task.nextQueueRetryAt = nil
            } else if task.status == .queued {
                task.status = .paused
                task.nextQueueRetryAt = nil
            }
            task.archivedAt = now
            task.appendLog(L10n.string("log_archived_task"))
        }
        selectedTaskIDs.subtract(tasks.map(\.id))
        if let selectedTaskID, tasks.contains(where: { $0.id == selectedTaskID }) {
            self.selectedTaskID = selectedTaskIDs.first
        }
        save()

        if runsEngines {
            for request in activeRequests {
                Task {
                    await engine(for: request.kind).pause(request)
                }
            }
        }
        scheduleQueue()
    }

    private func queueManageableTasks() -> [DownloadTask] {
        allTasks().filter { !$0.isArchived && $0.isQueueManageable }
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
            .filter { !$0.isArchived && $0.status == .queued }
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
        if lhs.isArchived != rhs.isArchived {
            return !lhs.isArchived
        }

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
        case .fetchingMetadata:
            1
        case .fetchingPeers:
            2
        case .connectingPeers:
            3
        case .verifying:
            4
        case .queued:
            5
        case .paused:
            6
        case .failed:
            7
        case .cancelled:
            8
        case .seeding:
            9
        case .completed:
            10
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

    private static func normalizedTorrentFolderPath(_ path: String) -> String {
        path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .joined(separator: "/")
    }

    private static func torrentFile(_ file: TorrentFile, isInFolder folderPath: String) -> Bool {
        file.path == folderPath || file.path.hasPrefix(folderPath + "/")
    }

    private static func normalizedTorrentExtensions(from filter: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: ",; \n\t")
        return Set(filter
            .components(separatedBy: separators)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "*."))
                    .lowercased()
            }
            .filter { !$0.isEmpty })
    }

    private static func trackerURLs(from text: String) -> [String] {
        var seen = Set<String>()
        let separators = CharacterSet(charactersIn: ", \n\t")
        return text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isValidTrackerURL($0) }
            .filter { seen.insert($0).inserted }
    }

    private static func isValidTrackerURL(_ rawValue: String) -> Bool {
        guard let components = URLComponents(string: rawValue),
              let scheme = components.scheme?.lowercased(),
              ["http", "https", "udp"].contains(scheme),
              components.host?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return false
        }
        return true
    }

    private static func normalizedTag(_ tag: String) -> String {
        DownloadTask.normalizedTagList([tag]).first ?? ""
    }

    private static func logExportText(for task: DownloadTask) -> String {
        task.logEntries.joined(separator: "\n")
    }

    private func formattedSpeedLimit(_ bytesPerSecond: Int64) -> String {
        guard bytesPerSecond > 0 else {
            return L10n.string("speed_unlimited")
        }
        return ByteCountFormatter.downloadFormatter.string(fromByteCount: bytesPerSecond) + "/s"
    }
}

enum DownloadFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case recent
    case large
    case needsAttention
    case running
    case seeding
    case queued
    case paused
    case completed
    case failed
    case cancelled
    case http
    case torrent
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L10n.string("filter_all")
        case .today: L10n.string("filter_today")
        case .recent: L10n.string("filter_recent_7_days")
        case .large: L10n.string("filter_large")
        case .needsAttention: L10n.string("filter_needs_attention")
        case .running: L10n.string("download_status_running")
        case .seeding: L10n.string("download_status_seeding")
        case .queued: L10n.string("download_status_queued")
        case .paused: L10n.string("download_status_paused")
        case .completed: L10n.string("download_status_completed")
        case .failed: L10n.string("download_status_failed")
        case .cancelled: L10n.string("download_status_cancelled")
        case .http: "HTTP"
        case .torrent: "BT"
        case .archived: L10n.string("filter_archived")
        }
    }

    var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .today: "calendar"
        case .recent: "clock.arrow.circlepath"
        case .large: "internaldrive"
        case .needsAttention: "exclamationmark.bubble"
        case .running: "arrow.down.circle"
        case .seeding: "arrow.up.circle"
        case .queued: "clock"
        case .paused: "pause.circle"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .cancelled: "xmark.circle"
        case .http: "link"
        case .torrent: "point.3.connected.trianglepath.dotted"
        case .archived: "archivebox"
        }
    }

    func matches(_ task: DownloadTask) -> Bool {
        if self == .archived {
            return task.isArchived
        }
        guard !task.isArchived else { return false }

        return switch self {
        case .all:
            true
        case .today:
            Calendar.current.isDateInToday(task.createdAt)
        case .recent:
            task.createdAt >= (Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())
        case .large:
            task.totalBytes >= 1_000_000_000
        case .needsAttention:
            task.status == .failed
                || task.status == .cancelled
                || task.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || task.nextQueueRetryAt.map { $0 > Date() } == true
        case .running:
            task.status == .running || task.status == .fetchingMetadata || task.status == .fetchingPeers || task.status == .connectingPeers
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
        case .archived:
            task.isArchived
        }
    }
}
