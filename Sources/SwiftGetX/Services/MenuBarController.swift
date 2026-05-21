import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private weak var coordinator: DownloadCoordinator?
    private weak var settings: AppSettings?
    private var refreshTimer: Timer?
    private var taskLookup: [UUID: DownloadTask] = [:]

    override init() {
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading
        updateStatusItem()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusItem()
            }
        }
    }

    func attach(coordinator: DownloadCoordinator, settings: AppSettings) {
        self.coordinator = coordinator
        self.settings = settings
        updateStatusItem()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        updateStatusItem()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        taskLookup.removeAll()

        let snapshot = makeSnapshot()
        addSummaryItems(snapshot)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: L10n.string("command_new_download"),
            action: #selector(showNewTask),
            keyEquivalent: "n"
        ).target = self

        if !snapshot.recentTasks.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let title = disabledItem(L10n.string("menu_recent_tasks"))
            menu.addItem(title)

            for taskSnapshot in snapshot.recentTasks {
                guard let task = task(for: taskSnapshot.id) else { continue }
                taskLookup[task.id] = task
                menu.addItem(menuItem(for: taskSnapshot))
            }
        }

        menu.addItem(NSMenuItem.separator())

        let pauseItem = menu.addItem(
            withTitle: L10n.string("command_pause_all"),
            action: #selector(pauseAll),
            keyEquivalent: ""
        )
        pauseItem.target = self
        pauseItem.isEnabled = snapshot.runningCount > 0 || snapshot.queuedCount > 0 || snapshot.verifyingCount > 0

        let resumeItem = menu.addItem(
            withTitle: L10n.string("command_resume_all"),
            action: #selector(resumeAll),
            keyEquivalent: ""
        )
        resumeItem.target = self
        resumeItem.isEnabled = snapshot.pausedCount > 0
            || snapshot.failedCount > 0
            || snapshot.cancelledCount > 0
            || snapshot.queuedCount > 0

        menu.addItem(
            withTitle: L10n.string("menu_open_download_directory"),
            action: #selector(openDownloadDirectory),
            keyEquivalent: ""
        ).target = self

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: L10n.string("menu_open_app"),
            action: #selector(openApp),
            keyEquivalent: ""
        ).target = self

        menu.addItem(
            withTitle: L10n.string("menu_settings"),
            action: #selector(openSettings),
            keyEquivalent: ","
        ).target = self

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: L10n.string("menu_quit_app"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        ).target = self
    }

    private func addSummaryItems(_ snapshot: MenuBarSnapshot) {
        let summary = disabledItem(
            L10n.string(
                "menu_summary",
                snapshot.totalCount,
                snapshot.runningCount,
                snapshot.queuedCount
            )
        )
        summary.image = NSImage(systemSymbolName: snapshot.statusSymbolName, accessibilityDescription: nil)
        menu.addItem(summary)

        let speed = ByteCountFormatter.downloadFormatter.string(fromByteCount: snapshot.totalDownloadSpeed)
        menu.addItem(disabledItem(
            L10n.string("menu_speed_summary", speed, snapshot.completedCount, snapshot.failedCount)
        ))
    }

    private func menuItem(for task: MenuBarTaskSnapshot) -> NSMenuItem {
        let item = NSMenuItem(title: taskMenuTitle(for: task), action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: task.status.symbolName, accessibilityDescription: task.status.title)
        item.submenu = taskSubmenu(for: task)
        return item
    }

    private func taskSubmenu(for task: MenuBarTaskSnapshot) -> NSMenu {
        let submenu = NSMenu()
        submenu.addItem(disabledItem(task.name))
        submenu.addItem(disabledItem(taskDetailTitle(for: task)))
        submenu.addItem(NSMenuItem.separator())

        let isPausable = task.status == .running || task.status == .seeding
        let toggleItem = submenu.addItem(
            withTitle: isPausable ? L10n.string("action_pause") : L10n.string("action_start"),
            action: #selector(toggleTask(_:)),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.representedObject = task.id
        toggleItem.isEnabled = task.status != .completed && task.status != .verifying

        let revealItem = submenu.addItem(
            withTitle: L10n.string("action_reveal_in_finder"),
            action: #selector(revealTask(_:)),
            keyEquivalent: ""
        )
        revealItem.target = self
        revealItem.representedObject = task.id

        submenu.addItem(NSMenuItem.separator())

        let deleteItem = submenu.addItem(
            withTitle: L10n.string("action_delete_task"),
            action: #selector(deleteTask(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.representedObject = task.id

        return submenu
    }

    private func updateStatusItem() {
        let snapshot = makeSnapshot()
        let image = NSImage(systemSymbolName: snapshot.statusSymbolName, accessibilityDescription: "SwiftGetX")
        image?.isTemplate = true
        statusItem.button?.image = image

        if snapshot.totalDownloadSpeed > 0 {
            statusItem.button?.title = ByteCountFormatter.downloadFormatter
                .string(fromByteCount: snapshot.totalDownloadSpeed) + "/s"
        } else {
            statusItem.button?.title = ""
        }
        statusItem.button?.toolTip = toolTip(for: snapshot)
    }

    private func makeSnapshot() -> MenuBarSnapshot {
        MenuBarSnapshot(tasks: coordinator?.allTasks() ?? [])
    }

    private func task(for id: UUID) -> DownloadTask? {
        if let task = taskLookup[id] {
            return task
        }
        return coordinator?.allTasks().first { $0.id == id }
    }

    private func taskMenuTitle(for task: MenuBarTaskSnapshot) -> String {
        let percent = Int((task.progress * 100).rounded())
        switch task.status {
        case .running:
            let speed = ByteCountFormatter.downloadFormatter.string(fromByteCount: task.speedBytesPerSecond)
            return "\(task.name) · \(percent)% · \(speed)/s"
        case .seeding:
            return "\(task.name) · \(L10n.string("download_status_seeding"))"
        case .completed:
            return "\(task.name) · \(L10n.string("download_status_completed"))"
        case .failed:
            return "\(task.name) · \(L10n.string("download_status_failed"))"
        case .cancelled:
            return "\(task.name) · \(L10n.string("download_status_cancelled"))"
        default:
            return "\(task.name) · \(task.status.title) · \(percent)%"
        }
    }

    private func taskDetailTitle(for task: MenuBarTaskSnapshot) -> String {
        let percent = Int((task.progress * 100).rounded())
        if task.status == .running {
            let speed = ByteCountFormatter.downloadFormatter.string(fromByteCount: task.speedBytesPerSecond)
            return "\(task.status.title) · \(percent)% · \(speed)/s"
        }
        return "\(task.status.title) · \(percent)%"
    }

    private func toolTip(for snapshot: MenuBarSnapshot) -> String {
        let speed = ByteCountFormatter.downloadFormatter.string(fromByteCount: snapshot.totalDownloadSpeed)
        return L10n.string("menu_tooltip", snapshot.runningCount, speed)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func showNewTask() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .showNewTaskSheet, object: nil)
    }

    @objc private func pauseAll() {
        if let coordinator {
            coordinator.pauseAll()
        } else {
            NotificationCenter.default.post(name: .pauseAllDownloads, object: nil)
        }
    }

    @objc private func resumeAll() {
        if let coordinator {
            coordinator.resumeAll()
        } else {
            NotificationCenter.default.post(name: .resumeAllDownloads, object: nil)
        }
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openSwiftGetXSettings, object: nil)
    }

    @objc private func openDownloadDirectory() {
        let directory = settings?.defaultDownloadDirectory ?? AppDefaults.downloadDirectory
        NSWorkspace.shared.open(directory)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func toggleTask(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let task = task(for: id),
              task.status != .completed,
              task.status != .verifying
        else {
            return
        }

        if task.status == .running || task.status == .seeding {
            coordinator?.pause(task)
        } else {
            coordinator?.resume(task)
        }
        updateStatusItem()
    }

    @objc private func revealTask(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let task = task(for: id)
        else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([task.revealURL])
    }

    @objc private func deleteTask(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let task = task(for: id)
        else {
            return
        }

        coordinator?.remove(task, deletingFiles: !task.hasFinishedDownloading)
        updateStatusItem()
    }
}

extension Notification.Name {
    static let pauseAllDownloads = Notification.Name("SwiftGetX.pauseAllDownloads")
    static let resumeAllDownloads = Notification.Name("SwiftGetX.resumeAllDownloads")
    static let openSwiftGetXSettings = Notification.Name("SwiftGetX.openSettings")
}
