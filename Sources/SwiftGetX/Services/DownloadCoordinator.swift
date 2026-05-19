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

    private(set) var statusMessage = "就绪"

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
        httpEngine.configure(segmentCount: settings.httpSegmentCount, retryLimit: settings.retryLimit)
        setSpeedLimit(
            downloadBytesPerSecond: settings.globalDownloadLimitBytes,
            uploadBytesPerSecond: settings.globalUploadLimitBytes
        )
    }

    func reloadSettings(_ settings: AppSettings) {
        self.settings = settings
        httpEngine.configure(segmentCount: settings.httpSegmentCount, retryLimit: settings.retryLimit)
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
        for task in tasks where task.status == .running || task.status == .verifying {
            task.status = .paused
            task.appendLog("应用重启后任务已恢复为暂停状态")
        }
        save()
    }

    func tasks(for filter: DownloadFilter = .all) -> [DownloadTask] {
        guard let modelContext else { return [] }
        var descriptor = FetchDescriptor<DownloadTask>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500

        let allTasks = (try? modelContext.fetch(descriptor)) ?? []
        return allTasks.filter { task in
            let matchesFilter = filter.matches(task)
            let matchesSearch = searchText.isEmpty
                || task.name.localizedCaseInsensitiveContains(searchText)
                || task.source.localizedCaseInsensitiveContains(searchText)
            return matchesFilter && matchesSearch
        }
    }

    @discardableResult
    func add(source: String, saveDirectory: URL? = nil) -> [DownloadTask] {
        let sources = SourceParser.extractSources(from: source)
        let saveDirectory = saveDirectory ?? settings?.defaultDownloadDirectory ?? AppDefaults.downloadDirectory
        let tasks = sources.map { source in
            let kind = SourceParser.kind(for: source)
            let task = DownloadTask(
                name: SourceParser.displayName(for: source, kind: kind),
                source: source,
                kind: kind,
                savePath: saveDirectory.appendingPathComponent(
                    SourceParser.displayName(for: source, kind: kind)
                ).path
            )
            task.appendLog("任务已创建")
            return task
        }

        guard let modelContext else { return tasks }
        for task in tasks {
            modelContext.insert(task)
        }
        selectedTaskID = tasks.first?.id ?? selectedTaskID
        save()
        statusMessage = "已添加 \(tasks.count) 个任务"
        scheduleQueue()
        return tasks
    }

    func start(_ task: DownloadTask) {
        task.status = .running
        task.errorMessage = nil
        task.appendLog("开始下载")
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).start(request)
        }
    }

    func pause(_ task: DownloadTask) {
        task.status = .paused
        task.speedBytesPerSecond = 0
        task.appendLog("已暂停")
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
        task.errorMessage = "任务已取消"
        task.appendLog("任务已取消")
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).cancel(request)
        }
    }

    func remove(_ task: DownloadTask, deletingFiles: Bool) {
        guard let modelContext else { return }
        let request = DownloadRequest(task: task)
        Task {
            await engine(for: request.kind).remove(request, deletingFiles: deletingFiles)
        }

        if deletingFiles {
            try? FileManager.default.removeItem(atPath: task.savePath)
        }
        modelContext.delete(task)
        if selectedTaskID == task.id {
            selectedTaskID = tasks().first?.id
        }
        save()
    }

    func recheck(_ task: DownloadTask) {
        task.status = .verifying
        task.appendLog("开始校验")
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).recheck(request)
        }
    }

    func setTorrentFileSelection(_ task: DownloadTask, selectedFileIndexes: [Int]) {
        guard task.kind == .torrentMagnet || task.kind == .torrentFile else { return }
        task.selectedFileIndexes = selectedFileIndexes.sorted()
        task.appendLog("已更新 BT 文件选择：\(selectedFileIndexes.count) 个文件")
        let request = DownloadRequest(task: task)
        save()

        Task {
            await engine(for: request.kind).setFileSelection(request, selectedFileIndexes: selectedFileIndexes)
        }
    }

    func pauseAll() {
        for task in tasks() where task.status == .running || task.status == .queued || task.status == .verifying {
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
        task.totalBytes = snapshot.totalBytes
        task.downloadedBytes = snapshot.downloadedBytes
        task.speedBytesPerSecond = snapshot.speedBytesPerSecond
        task.etaSeconds = snapshot.etaSeconds
        task.errorMessage = snapshot.errorMessage
        task.supportsResume = snapshot.supportsResume
        task.eTag = snapshot.eTag
        task.lastModified = snapshot.lastModified
        if !snapshot.torrentFiles.isEmpty {
            task.torrentFiles = snapshot.torrentFiles
            if task.selectedFileIndexes.isEmpty {
                task.selectedFileIndexes = snapshot.torrentFiles.map(\.index)
            }
        }
        if let connectionSummary = snapshot.connectionSummary {
            task.connectionSummary = connectionSummary
        }

        switch snapshot.status {
        case .completed:
            task.completedAt = .now
            task.speedBytesPerSecond = 0
            task.appendLog("下载完成")
            if settings?.completionNotificationsEnabled ?? true {
                NotificationManager.notifyCompletion(for: task)
            }
            scheduleQueue()
        case .failed:
            task.speedBytesPerSecond = 0
            task.appendLog(snapshot.errorMessage ?? "下载失败")
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
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}

enum DownloadFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case queued
    case paused
    case completed
    case failed
    case http
    case torrent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .running: "下载中"
        case .queued: "等待中"
        case .paused: "已暂停"
        case .completed: "已完成"
        case .failed: "失败"
        case .http: "HTTP"
        case .torrent: "BT"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "tray.full"
        case .running: "arrow.down.circle"
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
