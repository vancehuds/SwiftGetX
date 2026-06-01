import AppKit
import SwiftData
import SwiftGetXCore
import UniformTypeIdentifiers

@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private enum ToolbarItemID {
        static let add = NSToolbarItem.Identifier("SwiftGetX.toolbar.add")
        static let toggle = NSToolbarItem.Identifier("SwiftGetX.toolbar.toggle")
        static let delete = NSToolbarItem.Identifier("SwiftGetX.toolbar.delete")
        static let search = NSToolbarItem.Identifier("SwiftGetX.toolbar.search")
        static let speed = NSToolbarItem.Identifier("SwiftGetX.toolbar.speed")
        static let settings = NSToolbarItem.Identifier("SwiftGetX.toolbar.settings")
    }

    private let coordinator: DownloadCoordinator
    private let settings: AppSettings
    private let clipboardMonitor: ClipboardMonitor
    private let onNewTask: (DownloadDraft?) -> Void
    private let onSettings: () -> Void
    private let splitViewController: NSSplitViewController
    private let sidebarController: SidebarViewController
    private let taskListController: TaskListViewController
    private let inspectorController: InspectorViewController
    private let searchField = NSSearchField(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
    private var refreshTimer: Timer?
    private var clipboardSuggestionView: NSView?

    init(
        coordinator: DownloadCoordinator,
        settings: AppSettings,
        clipboardMonitor: ClipboardMonitor,
        onNewTask: @escaping (DownloadDraft?) -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.settings = settings
        self.clipboardMonitor = clipboardMonitor
        self.onNewTask = onNewTask
        self.onSettings = onSettings
        sidebarController = SidebarViewController(coordinator: coordinator)
        inspectorController = InspectorViewController(coordinator: coordinator)
        taskListController = TaskListViewController(coordinator: coordinator)
        splitViewController = NSSplitViewController()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SwiftGetX"
        window.minSize = NSSize(width: 820, height: 500)
        window.center()
        super.init(window: window)

        configureSplitView()
        configureToolbar()
        configureCallbacks()
        configureWindow()
        reload()
        startRefreshTimer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        sidebarController.reload()
        taskListController.reload()
        inspectorController.reload()
        updateClipboardSuggestion()
    }

    override func close() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        super.close()
    }

    func focusSearch() {
        window?.makeFirstResponder(searchField)
    }

    func focusSelectedTask() {
        taskListController.focusSelectedTask()
    }

    func confirmSelectedTaskRemoval() {
        let tasks = coordinator.selectedTasks
        guard !tasks.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = tasks.count > 1
            ? L10n.string("delete_tasks_dialog_title", tasks.count)
            : L10n.string("delete_task_dialog_title")
        alert.informativeText = deleteMessage(for: tasks)
        alert.addButton(withTitle: L10n.string("delete_task_only"))
        alert.addButton(withTitle: L10n.string("delete_task_and_local_file"))
        alert.addButton(withTitle: L10n.string("action_cancel"))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            coordinator.removeSelected(deletingFiles: false)
        } else if response == .alertSecondButtonReturn {
            coordinator.removeSelected(deletingFiles: true)
        }
        reload()
    }

    private func configureSplitView() {
        splitViewController.splitView.isVertical = true

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 170
        sidebarItem.maximumThickness = 260
        sidebarItem.canCollapse = false

        let listItem = NSSplitViewItem(viewController: taskListController)
        listItem.minimumThickness = 430

        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorController)
        inspectorItem.minimumThickness = 280
        inspectorItem.maximumThickness = 430

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(listItem)
        splitViewController.addSplitViewItem(inspectorItem)
    }

    private func configureWindow() {
        let rootView = DropHostingView(frame: .zero)
        rootView.translatesAutoresizingMaskIntoConstraints = false
        rootView.onDraft = { [weak self] draft in
            self?.onNewTask(draft)
        }

        let contentView = NSView()
        contentView.addSubview(rootView)
        addChildRootView(splitViewController.view, to: rootView)

        window?.contentView = contentView
        NSLayoutConstraint.activate([
            rootView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rootView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            rootView.topAnchor.constraint(equalTo: contentView.topAnchor),
            rootView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        WindowConfigurator.configure(window!)
    }

    private func addChildRootView(_ childView: NSView, to container: NSView) {
        childView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(childView)
        NSLayoutConstraint.activate([
            childView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            childView.topAnchor.constraint(equalTo: container.topAnchor),
            childView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: "SwiftGetX.mainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window?.toolbar = toolbar
        window?.toolbarStyle = .unified
    }

    private func configureCallbacks() {
        sidebarController.onSelectionChanged = { [weak self] in self?.reload() }
        taskListController.onSelectionChanged = { [weak self] in
            self?.inspectorController.reload()
        }
        taskListController.onDeleteRequested = { [weak self] in
            self?.confirmSelectedTaskRemoval()
        }
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    private func updateClipboardSuggestion() {
        clipboardSuggestionView?.removeFromSuperview()
        clipboardSuggestionView = nil
        guard let source = clipboardMonitor.suggestedSource,
              let contentView = window?.contentView
        else {
            return
        }

        let container = NSVisualEffectView()
        container.material = .popover
        container.state = .active
        container.blendingMode = .withinWindow
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "\(L10n.string("clipboard_detected_link"))  \(source)")
        label.lineBreakMode = .byTruncatingMiddle
        let ignore = NSButton(title: L10n.string("action_ignore"), target: self, action: #selector(ignoreClipboardSuggestion))
        let add = NSButton(title: L10n.string("action_add"), target: self, action: #selector(acceptClipboardSuggestion))
        add.bezelStyle = .rounded

        let stack = NSStackView(views: [label, ignore, add])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        contentView.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor, constant: 10),
            container.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            container.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.72),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 240)
        ])

        clipboardSuggestionView = container
    }

    @objc private func ignoreClipboardSuggestion() {
        clipboardMonitor.dismissSuggestion()
        updateClipboardSuggestion()
    }

    @objc private func acceptClipboardSuggestion() {
        clipboardMonitor.acceptSuggestion()
        reload()
    }

    private func deleteMessage(for tasks: [DownloadTask]) -> String {
        let paths = tasks
            .flatMap(\.localContentDeletionURLs)
            .map(\.path)
            .joined(separator: "\n")
        let summary = paths.isEmpty ? L10n.string("delete_task_no_known_local_content") : paths
        if tasks.allSatisfy(\.hasFinishedDownloading) {
            return L10n.string("delete_tasks_completed_message", tasks.count, summary)
        }
        return L10n.string("delete_tasks_unfinished_message", tasks.count, summary)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, ToolbarItemID.add, ToolbarItemID.toggle, ToolbarItemID.delete, .flexibleSpace, ToolbarItemID.search, ToolbarItemID.speed, ToolbarItemID.settings]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, ToolbarItemID.add, ToolbarItemID.toggle, ToolbarItemID.delete, .flexibleSpace, ToolbarItemID.search, ToolbarItemID.speed, ToolbarItemID.settings]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case ToolbarItemID.add:
            return makeToolbarButton(identifier: itemIdentifier, label: L10n.string("command_new_download"), symbol: "plus", action: #selector(addTask))
        case ToolbarItemID.toggle:
            return makeToolbarButton(identifier: itemIdentifier, label: L10n.string("help_toggle_selected_task"), symbol: "playpause", action: #selector(toggleSelected))
        case ToolbarItemID.delete:
            return makeToolbarButton(identifier: itemIdentifier, label: L10n.string("action_delete_task"), symbol: "trash", action: #selector(deleteSelected))
        case ToolbarItemID.settings:
            return makeToolbarButton(identifier: itemIdentifier, label: L10n.string("menu_settings_plain"), symbol: "gearshape", action: #selector(openSettings))
        case ToolbarItemID.search:
            searchField.placeholderString = L10n.string("search_placeholder")
            searchField.target = self
            searchField.action = #selector(searchChanged)
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = L10n.string("search_placeholder")
            item.view = searchField
            return item
        case ToolbarItemID.speed:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = L10n.string("speed_limit")
            item.view = SpeedLimitToolbarView(coordinator: coordinator)
            return item
        default:
            return nil
        }
    }

    private func makeToolbarButton(identifier: NSToolbarItem.Identifier, label: String, symbol: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    @objc private func addTask() {
        onNewTask(nil)
    }

    @objc private func toggleSelected() {
        if coordinator.selectedTasks.contains(where: { $0.usesActiveDownloadSlot || $0.status == .seeding }) {
            coordinator.pauseSelected()
        } else {
            coordinator.resumeSelected()
        }
        reload()
    }

    @objc private func deleteSelected() {
        confirmSelectedTaskRemoval()
    }

    @objc private func openSettings() {
        onSettings()
    }

    @objc private func searchChanged() {
        coordinator.searchText = searchField.stringValue
        reload()
    }
}

private final class DropHostingView: NSView {
    var onDraft: ((DownloadDraft) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let draft = DownloadInputSourceCollector.draft(from: sender.draggingPasteboard) else { return false }
        onDraft?(draft)
        return true
    }
}

@MainActor
private final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private enum Item: Hashable {
        case section(String)
        case filter(DownloadFilter)
        case category(DownloadTaskCategory)
        case tag(String)
    }

    private let coordinator: DownloadCoordinator
    private let outlineView = NSOutlineView()
    private let diagnostics = NativeHostDiagnostics()
    private var items = [Item]()
    var onSelectionChanged: (() -> Void)?

    init(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 30
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.style = .sourceList
        scrollView.documentView = outlineView
        view = scrollView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if diagnostics.status == .unchecked {
            diagnostics.check()
        }
        reload()
    }

    func reload() {
        let tasks = coordinator.allTasks()
        items = [.section(L10n.string("sidebar_tasks"))]
        items.append(contentsOf: DownloadFilter.allCases.map(Item.filter))
        let categories = coordinator.categories(in: tasks)
        if !categories.isEmpty {
            items.append(.section(L10n.string("sidebar_categories")))
            items.append(contentsOf: categories.map(Item.category))
        }
        let tags = coordinator.tags(in: tasks)
        if !tags.isEmpty {
            items.append(.section(L10n.string("sidebar_tags")))
            items.append(contentsOf: tags.map(Item.tag))
        }
        items.append(.section(L10n.string("browser_takeover")))
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        item == nil ? items.count : 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        false
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        items[index]
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? Item else { return nil }
        let cell = NSTableCellView()
        let imageView = NSImageView()
        let label = NSTextField(labelWithString: title(for: item))
        label.lineBreakMode = .byTruncatingTail
        label.font = font(for: item)
        label.textColor = textColor(for: item)
        imageView.image = image(for: item)
        imageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)

        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 18),
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let item = item as? Item else { return false }
        switch item {
        case .section:
            return false
        case .filter(let filter):
            coordinator.selectFilter(filter)
        case .category(let category):
            coordinator.selectCategory(category)
        case .tag(let tag):
            coordinator.selectTag(tag)
        }
        onSelectionChanged?()
        return true
    }

    private func title(for item: Item) -> String {
        switch item {
        case .section(let title):
            if title == L10n.string("browser_takeover") {
                return "\(title): \(diagnostics.sidebarStatusMessage)"
            }
            return title
        case .filter(let filter):
            return "\(filter.title)  \(count(for: filter))"
        case .category(let category):
            let count = coordinator.allTasks().filter { !$0.isArchived && $0.category == category }.count
            return "\(category.title)  \(count)"
        case .tag(let tag):
            let count = coordinator.allTasks().filter {
                !$0.isArchived && $0.normalizedTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }.count
            return "#\(tag)  \(count)"
        }
    }

    private func image(for item: Item) -> NSImage? {
        switch item {
        case .section:
            return nil
        case .filter(let filter):
            return NSImage(systemSymbolName: filter.symbolName, accessibilityDescription: filter.title)
        case .category(let category):
            return NSImage(systemSymbolName: category.symbolName, accessibilityDescription: category.title)
        case .tag:
            return NSImage(systemSymbolName: "tag", accessibilityDescription: nil)
        }
    }

    private func font(for item: Item) -> NSFont {
        switch item {
        case .section:
            return .systemFont(ofSize: 11, weight: .semibold)
        case .filter, .category, .tag:
            return .systemFont(ofSize: 13)
        }
    }

    private func textColor(for item: Item) -> NSColor {
        switch item {
        case .section:
            return .secondaryLabelColor
        case .filter, .category, .tag:
            return .labelColor
        }
    }

    private func count(for filter: DownloadFilter) -> Int {
        coordinator.allTasks().filter { filter.matches($0) }.count
    }
}

@MainActor
final class TaskListDataSource: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let coordinator: DownloadCoordinator
    private(set) var tasks = [DownloadTask]()
    var onSelectionChanged: (() -> Void)?

    init(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator
    }

    func reload() {
        let allTasks = coordinator.allTasks()
        tasks = coordinator.filteredTasks(from: allTasks)
        coordinator.pruneSelection()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tasks.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < tasks.count, let identifier = tableColumn?.identifier else { return nil }
        let task = tasks[row]
        let text: String
        switch identifier.rawValue {
        case "name":
            text = task.name
        case "status":
            text = task.status.title
        case "progress":
            text = task.progress.formatted(.percent.precision(.fractionLength(1)))
        case "speed":
            if task.status == .running || task.status == .fetchingMetadata || task.status == .fetchingPeers || task.status == .connectingPeers {
                text = ByteCountFormatter.downloadFormatter.string(fromByteCount: task.speedBytesPerSecond) + "/s"
            } else if task.status == .seeding {
                text = ByteCountFormatter.downloadFormatter.string(fromByteCount: task.torrentConnection?.uploadRate ?? 0) + "/s"
            } else {
                text = "--"
            }
        case "size":
            text = ByteCountFormatter.downloadFormatter.string(fromByteCount: task.totalBytes)
        case "kind":
            text = task.kind.title
        default:
            text = task.displaySource
        }

        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = identifier.rawValue == "source" ? .byTruncatingMiddle : .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }
        let selectedRows = tableView.selectedRowIndexes
        let selectedTasks = selectedRows.compactMap { $0 < tasks.count ? tasks[$0] : nil }
        coordinator.selectedTaskIDs = Set(selectedTasks.map(\.id))
        coordinator.selectedTaskID = selectedTasks.last?.id
        onSelectionChanged?()
    }
}

@MainActor
private final class TaskListViewController: NSViewController {
    private let coordinator: DownloadCoordinator
    private let dataSource: TaskListDataSource
    private let tableView = NSTableView()
    private let headerLabel = NSTextField(labelWithString: "")
    var onSelectionChanged: (() -> Void)?
    var onDeleteRequested: (() -> Void)?

    init(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator
        dataSource = TaskListDataSource(coordinator: coordinator)
        super.init(nibName: nil, bundle: nil)
        dataSource.onSelectionChanged = { [weak self] in self?.onSelectionChanged?() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        let toolbar = makeListToolbar()
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        configureTable()
        root.addSubview(toolbar)
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        view = root
    }

    func reload() {
        dataSource.reload()
        headerLabel.stringValue = "\(coordinator.activeListTitle)  \(summary(for: dataSource.tasks))"
        tableView.reloadData()
        selectRowsForCoordinatorSelection()
    }

    func focusSelectedTask() {
        selectRowsForCoordinatorSelection()
        if tableView.selectedRow >= 0 {
            tableView.scrollRowToVisible(tableView.selectedRow)
        }
    }

    private func configureTable() {
        tableView.dataSource = dataSource
        tableView.delegate = dataSource
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 28
        tableView.doubleAction = #selector(toggleSelected)
        tableView.target = self

        addColumn("name", title: L10n.string("metric_name", fallback: "Name"), width: 220)
        addColumn("status", title: L10n.string("metric_task_status"), width: 130)
        addColumn("progress", title: L10n.string("menu_progress_summary", "", 0).components(separatedBy: " ").first ?? "Progress", width: 90)
        addColumn("speed", title: L10n.string("metric_download_speed"), width: 110)
        addColumn("size", title: L10n.string("metric_downloaded"), width: 110)
        addColumn("kind", title: "Type", width: 70)
        addColumn("source", title: "Source", width: 260)

        tableView.menu = makeContextMenu()
    }

    private func addColumn(_ identifier: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = 60
        tableView.addTableColumn(column)
    }

    private func makeListToolbar() -> NSView {
        let selectAll = NSButton(title: L10n.string("action_select_all"), target: self, action: #selector(selectAllVisible))
        let cleanup = NSPopUpButton()
        cleanup.addItem(withTitle: L10n.string("task_list_actions"))
        cleanup.addItem(withTitle: L10n.string("batch_cleanup_completed_failed"))
        cleanup.addItem(withTitle: L10n.string("batch_cleanup_completed_failed_files"))
        cleanup.addItem(withTitle: L10n.string("batch_archive_completed"))
        cleanup.addItem(withTitle: L10n.string("batch_archive_failed"))
        cleanup.addItem(withTitle: L10n.string("batch_remove_archived_records"))
        cleanup.target = self
        cleanup.action = #selector(batchActionChanged(_:))

        headerLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        let stack = NSStackView(views: [headerLabel, NSView(), selectAll, cleanup])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        stack.views[1].setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        addContextItem(menu, title: L10n.string("action_start"), action: #selector(resumeSelected))
        addContextItem(menu, title: L10n.string("action_pause"), action: #selector(pauseSelected))
        addContextItem(menu, title: L10n.string("action_retry_task"), action: #selector(retrySelected))
        addContextItem(menu, title: L10n.string("action_recheck"), action: #selector(recheckSelected))
        menu.addItem(NSMenuItem.separator())
        addContextItem(menu, title: L10n.string("queue_move_top"), action: #selector(moveSelectedToTop))
        addContextItem(menu, title: L10n.string("queue_move_up"), action: #selector(moveSelectedUp))
        addContextItem(menu, title: L10n.string("queue_move_down"), action: #selector(moveSelectedDown))
        menu.addItem(NSMenuItem.separator())
        addContextItem(menu, title: L10n.string("action_reveal_in_finder"), action: #selector(revealSelected))
        addContextItem(menu, title: L10n.string("action_archive"), action: #selector(archiveSelected))
        addContextItem(menu, title: L10n.string("action_unarchive"), action: #selector(unarchiveSelected))
        addContextItem(menu, title: L10n.string("action_delete_task"), action: #selector(deleteSelected))
        return menu
    }

    private func addContextItem(_ menu: NSMenu, title: String, action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
    }

    private func selectRowsForCoordinatorSelection() {
        let ids = coordinator.effectiveSelectedTaskIDs
        let indexes = IndexSet(dataSource.tasks.enumerated().compactMap { ids.contains($0.element.id) ? $0.offset : nil })
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
    }

    private func summary(for tasks: [DownloadTask]) -> String {
        let running = tasks.filter(\.usesActiveDownloadSlot).count
        let completed = tasks.filter(\.hasFinishedDownloading).count
        return L10n.string("task_list_summary", tasks.count, running, completed)
    }

    @objc private func selectAllVisible() {
        coordinator.selectAllVisible(dataSource.tasks)
        reload()
        onSelectionChanged?()
    }

    @objc private func batchActionChanged(_ sender: NSPopUpButton) {
        defer { sender.selectItem(at: 0) }
        switch sender.indexOfSelectedItem {
        case 1:
            coordinator.cleanupCompletedAndFailed(deletingFiles: false)
        case 2:
            coordinator.cleanupCompletedAndFailed(deletingFiles: true)
        case 3:
            coordinator.archiveCompletedTasks()
        case 4:
            coordinator.archiveFailedTasks()
        case 5:
            coordinator.removeArchivedTaskRecords()
        default:
            return
        }
        reload()
    }

    @objc private func toggleSelected() {
        if coordinator.selectedTasks.contains(where: { $0.usesActiveDownloadSlot || $0.status == .seeding }) {
            coordinator.pauseSelected()
        } else {
            coordinator.resumeSelected()
        }
        reload()
    }

    @objc private func pauseSelected() { coordinator.pauseSelected(); reload() }
    @objc private func resumeSelected() { coordinator.resumeSelected(); reload() }
    @objc private func retrySelected() { coordinator.retrySelected(); reload() }
    @objc private func recheckSelected() { coordinator.recheckSelected(); reload() }
    @objc private func revealSelected() { coordinator.revealSelectedInFinder() }
    @objc private func archiveSelected() { coordinator.archiveSelected(); reload() }
    @objc private func unarchiveSelected() { coordinator.unarchiveSelected(); reload() }
    @objc private func moveSelectedToTop() { coordinator.moveSelectedToTop(); reload() }
    @objc private func moveSelectedUp() { coordinator.moveSelectedUp(); reload() }
    @objc private func moveSelectedDown() { coordinator.moveSelectedDown(); reload() }
    @objc private func deleteSelected() { onDeleteRequested?() }
}

@MainActor
private final class InspectorViewController: NSViewController {
    private let coordinator: DownloadCoordinator
    private let segmentedControl = NSSegmentedControl(labels: [], trackingMode: .selectOne, target: nil, action: nil)
    private let stackView = NSStackView()
    private let scrollView = NSScrollView()

    init(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        segmentedControl.target = self
        segmentedControl.action = #selector(tabChanged)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.addSubview(stackView)
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(segmentedControl)
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            segmentedControl.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            segmentedControl.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            segmentedControl.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        view = root
    }

    func reload() {
        configureTabs()
        rebuildContent()
    }

    private func configureTabs() {
        let task = coordinator.selectedTask
        let labels = task.map { InspectorTab.tabs(for: $0.kind).map(\.title) } ?? [L10n.string("inspector_tab_overview")]
        segmentedControl.segmentCount = labels.count
        for (index, label) in labels.enumerated() {
            segmentedControl.setLabel(label, forSegment: index)
            segmentedControl.setWidth(80, forSegment: index)
        }
        if segmentedControl.selectedSegment < 0 || segmentedControl.selectedSegment >= labels.count {
            segmentedControl.selectedSegment = 0
        }
    }

    private func rebuildContent() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let task = coordinator.selectedTask else {
            stackView.addArrangedSubview(label(L10n.string("inspector_select_task"), size: 14, weight: .semibold))
            return
        }

        stackView.addArrangedSubview(label(task.name, size: 16, weight: .semibold))
        stackView.addArrangedSubview(progressIndicator(task.progress))
        let tabs = InspectorTab.tabs(for: task.kind)
        let tab = tabs.indices.contains(segmentedControl.selectedSegment) ? tabs[segmentedControl.selectedSegment] : .overview
        switch tab {
        case .overview:
            addOverview(task)
        case .segments:
            addHTTPSegments(task)
        case .files:
            addTorrentFiles(task)
        case .connections:
            addConnections(task)
        case .logs:
            addLogs(task)
        }
    }

    private func addOverview(_ task: DownloadTask) {
        addDetail(L10n.string("metric_task_status"), task.status.title)
        addDetail(L10n.string("metric_downloaded"), "\(ByteCountFormatter.downloadFormatter.string(fromByteCount: task.downloadedBytes)) / \(ByteCountFormatter.downloadFormatter.string(fromByteCount: task.totalBytes))")
        addDetail(L10n.string("metric_download_speed"), ByteCountFormatter.downloadFormatter.string(fromByteCount: task.speedBytesPerSecond) + "/s")
        addDetail(L10n.string("metric_eta"), task.etaSeconds.map(TimeFormatter.eta) ?? "--")
        addDetail(L10n.string("save_directory"), task.displaySavePath)
        addDetail("Source", task.displaySource)
        if let error = task.errorMessage, !error.isEmpty {
            addDetail(L10n.string("startup_recovery_error"), error)
        }
        if let reason = BrowserDownloadRecoveryPolicy.persistedRequirement(for: task) {
            addDetail(L10n.string("browser_recovery_requirement_title"), reason.message)
        }
    }

    private func addHTTPSegments(_ task: DownloadTask) {
        let segments = task.httpSegments
        if segments.isEmpty {
            addDetail(L10n.string("inspector_tab_segments"), "--")
            return
        }
        for segment in segments {
            addDetail(
                "#\(segment.index)",
                "\(segment.progress.formatted(.percent.precision(.fractionLength(1))))  \(ByteCountFormatter.downloadFormatter.string(fromByteCount: segment.speedBytesPerSecond))/s"
            )
        }
    }

    private func addTorrentFiles(_ task: DownloadTask) {
        if task.torrentFiles.isEmpty {
            addDetail(L10n.string("inspector_tab_files"), "--")
            return
        }
        for file in task.torrentFiles.prefix(200) {
            addDetail(
                file.path,
                "\(ByteCountFormatter.downloadFormatter.string(fromByteCount: file.size))  \(file.priorityLevel.title)  \(file.progress.formatted(.percent.precision(.fractionLength(1))))"
            )
        }
    }

    private func addConnections(_ task: DownloadTask) {
        let connection = task.torrentConnection
        addDetail(L10n.string("torrent_peer_count"), "\(connection?.peerCount ?? 0)")
        addDetail(L10n.string("metric_upload_speed"), ByteCountFormatter.downloadFormatter.string(fromByteCount: connection?.uploadRate ?? 0) + "/s")
        addDetail(L10n.string("torrent_share_ratio"), String(format: "%.2f", connection?.shareRatio ?? 0))
        for tracker in task.torrentTrackers {
            addDetail(tracker.url, tracker.status)
        }
    }

    private func addLogs(_ task: DownloadTask) {
        if task.logEntries.isEmpty {
            addDetail(L10n.string("inspector_tab_logs"), "--")
            return
        }
        for entry in task.logEntries.suffix(120) {
            stackView.addArrangedSubview(label(entry, size: 11, weight: .regular, monospace: true))
        }
    }

    private func addDetail(_ title: String, _ value: String) {
        let titleLabel = label(title, size: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        let valueLabel = label(value, size: 12, weight: .regular)
        valueLabel.maximumNumberOfLines = 0
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(valueLabel)
    }

    private func label(_ value: String, size: CGFloat, weight: NSFont.Weight, monospace: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.font = monospace ? .monospacedSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 0
        return field
    }

    private func progressIndicator(_ value: Double) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.isIndeterminate = false
        indicator.minValue = 0
        indicator.maxValue = 1
        indicator.doubleValue = value
        indicator.controlSize = .small
        indicator.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return indicator
    }

    @objc private func tabChanged() {
        rebuildContent()
    }
}

private enum InspectorTab: String, CaseIterable {
    case overview
    case files
    case connections
    case segments
    case logs

    var title: String {
        switch self {
        case .overview: L10n.string("inspector_tab_overview")
        case .files: L10n.string("inspector_tab_files")
        case .connections: L10n.string("inspector_tab_connections")
        case .segments: L10n.string("inspector_tab_segments")
        case .logs: L10n.string("inspector_tab_logs")
        }
    }

    static func tabs(for kind: DownloadKind) -> [InspectorTab] {
        switch kind {
        case .http:
            [.overview, .segments, .logs]
        case .torrentMagnet, .torrentFile:
            [.overview, .files, .connections, .logs]
        }
    }
}

@MainActor
final class NewTaskWindowController: NSWindowController {
    let draft: DownloadDraft?
    private let settings: AppSettings
    private let coordinator: DownloadCoordinator
    private let onComplete: () -> Void
    private let sourceTextView = NSTextView()
    private let directoryLabel = NSTextField(labelWithString: "")
    private let filenameField = NSTextField()
    private let segmentStepper = NSStepper()
    private let segmentLabel = NSTextField(labelWithString: "")
    private let retryStepper = NSStepper()
    private let retryLabel = NSTextField(labelWithString: "")
    private let speedPopup = NSPopUpButton()
    private let checksumPopup = NSPopUpButton()
    private let checksumField = NSTextField()
    private let headersTextView = NSTextView()
    private let previewLabel = NSTextField(labelWithString: "")
    private var saveDirectory: URL
    private var suggestedFilename: String?
    private var didResolveNativeHandoff = false

    init(
        draft: DownloadDraft?,
        settings: AppSettings,
        coordinator: DownloadCoordinator,
        onComplete: @escaping () -> Void
    ) {
        self.draft = draft
        self.settings = settings
        self.coordinator = coordinator
        self.onComplete = onComplete
        saveDirectory = settings.defaultDownloadDirectory
        suggestedFilename = draft?.suggestedFilename

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = draft?.prefersTorrentInput == true ? L10n.string("new_task_torrent_title") : L10n.string("new_task_title")
        super.init(window: window)
        window.delegate = self
        configureContent()
        applyDraft()
        refreshPreviewSummary()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureContent() {
        guard let window else { return }
        let root = NSView()
        let scrollView = NSScrollView()
        let documentView = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: draft?.prefersTorrentInput == true ? L10n.string("new_task_torrent_title") : L10n.string("new_task_title"))
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        stack.addArrangedSubview(title)

        sourceTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        sourceTextView.minSize = NSSize(width: 0, height: 140)
        sourceTextView.delegate = self
        let sourceScroll = NSScrollView()
        sourceScroll.hasVerticalScroller = true
        sourceScroll.documentView = sourceTextView
        sourceScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        sourceScroll.widthAnchor.constraint(equalToConstant: 590).isActive = true
        stack.addArrangedSubview(labeledView(L10n.string("source_preview_title"), sourceScroll))

        let directoryRow = NSStackView()
        directoryRow.orientation = .horizontal
        directoryRow.alignment = .centerY
        directoryRow.spacing = 8
        directoryLabel.lineBreakMode = .byTruncatingMiddle
        let chooseButton = NSButton(title: L10n.string("choose_directory"), target: self, action: #selector(chooseDirectory))
        directoryRow.addArrangedSubview(directoryLabel)
        directoryRow.addArrangedSubview(chooseButton)
        stack.addArrangedSubview(labeledView(L10n.string("save_directory"), directoryRow))

        filenameField.placeholderString = L10n.string("http_options_filename_placeholder")
        stack.addArrangedSubview(labeledView(L10n.string("http_options_filename"), filenameField))

        segmentStepper.minValue = 1
        segmentStepper.maxValue = Double(HTTPDownloadOptions.maximumSegmentCount)
        segmentStepper.integerValue = settings.httpMultithreadingEnabled ? settings.httpSegmentCount : 1
        segmentStepper.target = self
        segmentStepper.action = #selector(optionChanged)
        retryStepper.minValue = 0
        retryStepper.maxValue = Double(HTTPDownloadOptions.maximumRetryLimit)
        retryStepper.integerValue = settings.retryLimit
        retryStepper.target = self
        retryStepper.action = #selector(optionChanged)
        let stepperRow = NSStackView(views: [segmentLabel, segmentStepper, retryLabel, retryStepper])
        stepperRow.orientation = .horizontal
        stepperRow.alignment = .centerY
        stepperRow.spacing = 8
        stack.addArrangedSubview(labeledView(L10n.string("http_options_title"), stepperRow))

        for value in speedLimitChoices {
            speedPopup.addItem(withTitle: speedLabel(for: value))
            speedPopup.lastItem?.representedObject = value
        }
        checksumPopup.addItems(withTitles: HTTPChecksumAlgorithm.allCases.map(\.title))
        let checksumRow = NSStackView(views: [speedPopup, checksumPopup, checksumField])
        checksumRow.orientation = .horizontal
        checksumRow.alignment = .centerY
        checksumRow.spacing = 8
        checksumField.placeholderString = L10n.string("http_options_checksum_placeholder")
        checksumField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        stack.addArrangedSubview(labeledView(L10n.string("http_options_checksum"), checksumRow))

        headersTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let headerScroll = NSScrollView()
        headerScroll.hasVerticalScroller = true
        headerScroll.documentView = headersTextView
        headerScroll.heightAnchor.constraint(equalToConstant: 72).isActive = true
        headerScroll.widthAnchor.constraint(equalToConstant: 590).isActive = true
        stack.addArrangedSubview(labeledView(L10n.string("http_options_headers_placeholder"), headerScroll))

        let torrentButton = NSButton(title: L10n.string("action_choose_torrent_file"), target: self, action: #selector(chooseTorrentFile))
        stack.addArrangedSubview(torrentButton)
        stack.addArrangedSubview(previewLabel)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10
        let cancel = NSButton(title: L10n.string("action_cancel"), target: self, action: #selector(cancel))
        let add = NSButton(title: L10n.string("add_task"), target: self, action: #selector(addTask))
        add.keyEquivalent = "\r"
        buttons.addArrangedSubview(NSView())
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(add)
        stack.addArrangedSubview(buttons)

        documentView.addSubview(stack)
        scrollView.documentView = documentView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        window.contentView = root
        updateOptionLabels()
        updateDirectoryLabel()
    }

    private func labeledView(_ title: String, _ view: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label, view])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    private func applyDraft() {
        sourceTextView.string = draft?.source ?? ""
        filenameField.stringValue = draft?.suggestedFilename ?? ""
    }

    private func updateDirectoryLabel() {
        directoryLabel.stringValue = saveDirectory.path
    }

    private func updateOptionLabels() {
        segmentLabel.stringValue = L10n.string("http_options_segments", segmentStepper.integerValue)
        retryLabel.stringValue = L10n.string("http_options_retries", retryStepper.integerValue)
    }

    private func refreshPreviewSummary() {
        let sources = SourceParser.extractSources(from: sourceTextView.string)
        previewLabel.stringValue = sources.isEmpty
            ? L10n.string("source_preview_empty")
            : L10n.string("source_preview_count", sources.count)
    }

    private var currentSources: [String] {
        SourceParser.extractSources(from: sourceTextView.string)
    }

    private var hasHTTPSources: Bool {
        currentSources.contains { SourceParser.kind(for: $0) == .http }
    }

    private var hasSingleHTTPSource: Bool {
        currentSources.count == 1 && currentSources.first.map { SourceParser.kind(for: $0) == .http } == true
    }

    private var httpOptions: HTTPDownloadOptions? {
        guard hasHTTPSources else { return nil }
        let filename = HTTPResponseMetadata(suggestedFilename: filenameField.stringValue).suggestedFilename
        return HTTPDownloadOptions(
            segmentCountOverride: segmentStepper.integerValue,
            retryLimitOverride: retryStepper.integerValue,
            perTaskDownloadLimitBytes: selectedSpeedLimit,
            filenameOverride: hasSingleHTTPSource ? filename : nil,
            checksum: httpChecksum(preferredFilename: filename ?? suggestedFilename),
            additionalHeaders: HTTPDownloadOptions.headers(from: headersTextView.string)
        )
    }

    private var selectedSpeedLimit: Int64 {
        speedPopup.selectedItem?.representedObject as? Int64 ?? 0
    }

    private func httpChecksum(preferredFilename: String?) -> HTTPChecksum? {
        let algorithm = HTTPChecksumAlgorithm.allCases[safe: checksumPopup.indexOfSelectedItem] ?? .sha256
        return HTTPChecksum(algorithm: algorithm, expectedHexDigest: checksumField.stringValue)
            ?? HTTPChecksum(input: checksumField.stringValue, preferredFilename: preferredFilename)
    }

    @objc private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            saveDirectory = url
            updateDirectoryLabel()
        }
    }

    @objc private func chooseTorrentFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.map(\.path)
        guard !paths.isEmpty else { return }
        let separator = sourceTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n"
        sourceTextView.string += separator + paths.joined(separator: "\n")
        refreshPreviewSummary()
    }

    @objc private func optionChanged() {
        updateOptionLabels()
    }

    @objc private func cancel() {
        rejectNativeHandoffIfNeeded(reason: "userCancelled")
        closeSheetOrWindow()
    }

    @objc private func addTask() {
        guard !rejectExpiredNativeHandoffIfNeeded() else {
            closeSheetOrWindow()
            return
        }
        let tasks = coordinator.add(
            source: sourceTextView.string,
            saveDirectory: saveDirectory,
            suggestedFilename: filenameField.stringValue.isEmpty ? suggestedFilename : filenameField.stringValue,
            browserContext: draft?.browserContext,
            httpOptions: httpOptions
        )
        acknowledgeNativeHandoffIfNeeded(
            decision: NativeHandoffDecisionFactory.decision(
                queuedTaskCount: tasks.count,
                requiresUserConfirmation: draft?.requiresUserConfirmation == true
                    || draft?.isBrowserTakeover == true
            )
        )
        closeSheetOrWindow()
    }

    private func closeSheetOrWindow() {
        onComplete()
        if let sheetParent = window?.sheetParent, let window {
            sheetParent.endSheet(window)
        } else {
            close()
        }
    }

    private func rejectExpiredNativeHandoffIfNeeded() -> Bool {
        guard let resolution = PendingNativeHandoffPolicy.expirationResolution(draft: draft) else {
            return false
        }
        didResolveNativeHandoff = true
        PendingNativeHandoffPolicy.acknowledge(resolution)
        return true
    }

    private func rejectNativeHandoffIfNeeded(reason: String) {
        acknowledgeNativeHandoffIfNeeded(
            decision: .rejected(
                reason: reason,
                requiresUserConfirmation: draft?.requiresUserConfirmation == true
                    || draft?.isBrowserTakeover == true,
                message: "SwiftGetX download confirmation was cancelled"
            )
        )
    }

    private func acknowledgeNativeHandoffIfNeeded(decision: NativeHandoffAckDecision) {
        guard !didResolveNativeHandoff,
              draft?.canAcknowledgeNativeHandoff == true,
              let handoffAck = draft?.handoffAck
        else {
            return
        }

        didResolveNativeHandoff = true
        Task.detached {
            try? await NativeHandoffAckClient.acknowledge(decision, handoff: handoffAck)
        }
    }

    private var speedLimitChoices: [Int64] {
        [0, 500_000, 1_000_000, 5_000_000, 10_000_000, 20_000_000]
    }

    private func speedLabel(for value: Int64) -> String {
        guard value > 0 else { return L10n.string("speed_unlimited") }
        return ByteCountFormatter.downloadFormatter.string(fromByteCount: value) + "/s"
    }
}

extension NewTaskWindowController: NSWindowDelegate, NSTextViewDelegate {
    func windowWillClose(_ notification: Notification) {
        rejectNativeHandoffIfNeeded(reason: "userCancelled")
        onComplete()
    }

    func textDidChange(_ notification: Notification) {
        refreshPreviewSummary()
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settings: AppSettings
    private let coordinator: DownloadCoordinator
    private let updater: SoftwareUpdater
    private let modelContext: ModelContext
    private let diagnostics = NativeHostDiagnostics()
    private let tabView = NSTabView()

    init(
        settings: AppSettings,
        coordinator: DownloadCoordinator,
        updater: SoftwareUpdater,
        modelContext: ModelContext
    ) {
        self.settings = settings
        self.coordinator = coordinator
        self.updater = updater
        self.modelContext = modelContext
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.string("menu_settings_plain")
        window.center()
        super.init(window: window)
        configureContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if diagnostics.status == .unchecked {
            diagnostics.repair()
        }
        rebuildTabs()
    }

    private func configureContent() {
        tabView.translatesAutoresizingMaskIntoConstraints = false
        window?.contentView = NSView()
        window?.contentView?.addSubview(tabView)
        if let contentView = window?.contentView {
            NSLayoutConstraint.activate([
                tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
                tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
                tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
                tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
            ])
        }
        rebuildTabs()
    }

    private func rebuildTabs() {
        tabView.tabViewItems.removeAll()
        tabView.addTabViewItem(tab(title: L10n.string("settings_download_section"), view: downloadSettingsView()))
        tabView.addTabViewItem(tab(title: "BT", view: torrentSettingsView()))
        tabView.addTabViewItem(tab(title: L10n.string("settings_system_section"), view: systemSettingsView()))
        tabView.addTabViewItem(tab(title: L10n.string("browser_integration_section"), view: browserSettingsView()))
        tabView.addTabViewItem(tab(title: L10n.string("settings_updates_section"), view: updateSettingsView()))
    }

    private func tab(title: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = scrollable(view)
        return item
    }

    private func scrollable(_ content: NSView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = content
        content.translatesAutoresizingMaskIntoConstraints = false
        content.widthAnchor.constraint(equalToConstant: 500).isActive = true
        return scroll
    }

    private func downloadSettingsView() -> NSView {
        let stack = settingsStack()
        addPathRow(stack, title: L10n.string("default_download_directory"), value: settings.defaultDownloadDirectory.path, action: #selector(chooseDefaultDirectory))
        addStepperRow(stack, title: L10n.string("settings_concurrent_tasks", settings.concurrentTaskLimit), value: settings.concurrentTaskLimit, min: 1, max: 12, action: #selector(concurrentTasksChanged(_:)))
        addCheckbox(stack, title: L10n.string("settings_enable_http_multithreading"), state: settings.httpMultithreadingEnabled, action: #selector(httpMultithreadingChanged(_:)))
        addStepperRow(stack, title: L10n.string("settings_http_thread_count", settings.httpSegmentCount), value: settings.httpSegmentCount, min: 1, max: 32, action: #selector(httpSegmentCountChanged(_:)))
        addCheckbox(stack, title: L10n.string("settings_hide_http_temp_files"), state: settings.hideHTTPTemporaryFiles, action: #selector(hideTempFilesChanged(_:)))
        addStepperRow(stack, title: L10n.string("settings_retry_count", settings.retryLimit), value: settings.retryLimit, min: 0, max: 10, action: #selector(retryLimitChanged(_:)))
        addSpeedPopup(stack, title: L10n.string("download_speed_limit"), current: settings.globalDownloadLimitBytes, values: [0, 1_000_000, 5_000_000, 10_000_000, 20_000_000], action: #selector(downloadLimitChanged(_:)))
        addMultilineText(stack, title: L10n.string("download_rules_section"), text: settings.downloadRulesText, action: #selector(downloadRulesChanged(_:)))
        return stack
    }

    private func torrentSettingsView() -> NSView {
        let stack = settingsStack()
        addPopup(stack, title: L10n.string("torrent_engine"), options: TorrentEngineKind.allCases.map(\.title), selected: TorrentEngineKind.allCases.firstIndex(of: settings.torrentEngine) ?? 0, action: #selector(torrentEngineChanged(_:)))
        addCheckbox(stack, title: L10n.string("torrent_enable_dht"), state: settings.torrentDHTEnabled, action: #selector(torrentDHTChanged(_:)))
        addCheckbox(stack, title: L10n.string("torrent_enable_pex"), state: settings.torrentPEXEnabled, action: #selector(torrentPEXChanged(_:)))
        addCheckbox(stack, title: L10n.string("torrent_enable_lsd"), state: settings.torrentLSDEnabled, action: #selector(torrentLSDChanged(_:)))
        addCheckbox(stack, title: L10n.string("torrent_enable_sequential_default"), state: settings.torrentSequentialDownloadEnabled, action: #selector(torrentSequentialChanged(_:)))
        addStepperRow(stack, title: L10n.string("torrent_magnet_timeout_seconds", settings.torrentMagnetMetadataTimeoutSeconds), value: settings.torrentMagnetMetadataTimeoutSeconds, min: 3, max: 120, action: #selector(torrentTimeoutChanged(_:)))
        addStepperRow(stack, title: L10n.string("torrent_max_connections", settings.torrentMaxConnections), value: settings.torrentMaxConnections, min: 2, max: 1000, action: #selector(torrentConnectionsChanged(_:)))
        addStepperRow(stack, title: L10n.string("torrent_max_upload_slots", settings.torrentMaxUploadSlots), value: settings.torrentMaxUploadSlots, min: -1, max: 128, action: #selector(torrentUploadSlotsChanged(_:)))
        addSpeedPopup(stack, title: L10n.string("upload_speed_limit"), current: settings.globalUploadLimitBytes, values: [0, 256_000, 512_000, 1_000_000, 5_000_000], action: #selector(uploadLimitChanged(_:)))
        addMultilineText(stack, title: L10n.string("torrent_dht_bootstrap_nodes"), text: settings.torrentDHTBootstrapNodes.joined(separator: "\n"), action: #selector(torrentBootstrapChanged(_:)))
        return stack
    }

    private func systemSettingsView() -> NSView {
        let stack = settingsStack()
        addPopup(stack, title: L10n.string("settings_system_language"), options: AppLanguage.allCases.map(\.title), selected: AppLanguage.allCases.firstIndex(of: settings.language) ?? 0, action: #selector(languageChanged(_:)))
        addPopup(stack, title: L10n.string("diagnostic_log_level"), options: DiagnosticLogLevel.allCases.map(\.title), selected: DiagnosticLogLevel.allCases.firstIndex(of: settings.diagnosticLogLevel) ?? 0, action: #selector(logLevelChanged(_:)))
        addCheckbox(stack, title: L10n.string("completion_notifications"), state: settings.completionNotificationsEnabled, action: #selector(completionNotificationsChanged(_:)))
        addCheckbox(stack, title: L10n.string("clipboard_link_detection"), state: settings.clipboardDetectionEnabled, action: #selector(clipboardDetectionChanged(_:)))
        addCheckbox(stack, title: L10n.string("launch_at_login"), state: settings.launchAtLoginEnabled, action: #selector(launchAtLoginChanged(_:)))
        addCheckbox(stack, title: L10n.string("keep_running_in_menu_bar"), state: settings.keepRunningInMenuBar, action: #selector(keepRunningChanged(_:)))
        addCheckbox(stack, title: L10n.string("prevent_sleep_during_downloads"), state: settings.preventSleepDuringDownloads, action: #selector(preventSleepChanged(_:)))
        addCheckbox(stack, title: L10n.string("prompt_before_quitting_active"), state: settings.promptBeforeQuittingWithActiveTasks, action: #selector(promptBeforeQuitChanged(_:)))
        addTextField(stack, title: L10n.string("completion_script_placeholder"), value: settings.completionScriptPath, action: #selector(scriptPathChanged(_:)))
        return stack
    }

    private func browserSettingsView() -> NSView {
        let stack = settingsStack()
        addCheckbox(stack, title: L10n.string("confirm_browser_takeover_downloads"), state: settings.confirmBrowserTakeoverDownloads, action: #selector(confirmBrowserTakeoverChanged(_:)))
        addMultilineText(stack, title: L10n.string("browser_takeover_allowed_hosts"), text: settings.browserTakeoverAllowedHostsText, action: #selector(allowedHostsChanged(_:)))
        addMultilineText(stack, title: L10n.string("browser_takeover_blocked_hosts"), text: settings.browserTakeoverBlockedHostsText, action: #selector(blockedHostsChanged(_:)))
        let status = NSTextField(labelWithString: "\(L10n.string("browser_native_host")): \(diagnostics.statusMessage)")
        stack.addArrangedSubview(status)
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.addArrangedSubview(NSButton(title: L10n.string("action_check"), target: self, action: #selector(checkDiagnostics)))
        buttons.addArrangedSubview(NSButton(title: L10n.string("action_try_repair"), target: self, action: #selector(repairDiagnostics)))
        buttons.addArrangedSubview(NSButton(title: L10n.string("help_reveal_manifest"), target: self, action: #selector(revealManifest)))
        buttons.addArrangedSubview(NSButton(title: L10n.string("support_diagnostics_copy"), target: self, action: #selector(copyDiagnostics)))
        stack.addArrangedSubview(buttons)
        return stack
    }

    private func updateSettingsView() -> NSView {
        let stack = settingsStack()
        stack.addArrangedSubview(NSTextField(labelWithString: L10n.string("updates_current_version", updater.currentVersion)))
        stack.addArrangedSubview(NSTextField(labelWithString: updater.manualCheckStatusText))
        if let feedURL = updater.feedURL {
            stack.addArrangedSubview(NSTextField(labelWithString: L10n.string("updates_feed_url", feedURL.absoluteString)))
        }
        stack.addArrangedSubview(NSButton(title: L10n.string("command_check_for_updates"), target: self, action: #selector(checkForUpdates)))
        addCheckbox(stack, title: L10n.string("updates_automatic_checks"), state: updater.automaticallyChecksForUpdates, action: #selector(automaticChecksChanged(_:)))
        addCheckbox(stack, title: L10n.string("updates_automatic_downloads"), state: updater.automaticallyDownloadsUpdates, action: #selector(automaticDownloadsChanged(_:)))
        return stack
    }

    private func settingsStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        return stack
    }

    private func addPathRow(_ stack: NSStackView, title: String, value: String, action: Selector) {
        let label = NSTextField(labelWithString: "\(title): \(value)")
        label.lineBreakMode = .byTruncatingMiddle
        let button = NSButton(title: L10n.string("action_choose"), target: self, action: action)
        let row = NSStackView(views: [label, button])
        row.orientation = .horizontal
        row.spacing = 8
        stack.addArrangedSubview(row)
    }

    private func addStepperRow(_ stack: NSStackView, title: String, value: Int, min: Int, max: Int, action: Selector) {
        let label = NSTextField(labelWithString: title)
        let stepper = NSStepper()
        stepper.minValue = Double(min)
        stepper.maxValue = Double(max)
        stepper.integerValue = value
        stepper.target = self
        stepper.action = action
        let row = NSStackView(views: [label, stepper])
        row.orientation = .horizontal
        row.spacing = 8
        stack.addArrangedSubview(row)
    }

    private func addCheckbox(_ stack: NSStackView, title: String, state: Bool, action: Selector) {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.state = state ? .on : .off
        stack.addArrangedSubview(button)
    }

    private func addSpeedPopup(_ stack: NSStackView, title: String, current: Int64, values: [Int64], action: Selector) {
        let popup = NSPopUpButton()
        for value in values {
            popup.addItem(withTitle: speedLabel(value))
            popup.lastItem?.representedObject = value
        }
        popup.selectItem(at: values.firstIndex(of: current) ?? 0)
        popup.target = self
        popup.action = action
        stack.addArrangedSubview(labeled(title, popup))
    }

    private func addPopup(_ stack: NSStackView, title: String, options: [String], selected: Int, action: Selector) {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: options)
        popup.selectItem(at: selected)
        popup.target = self
        popup.action = action
        stack.addArrangedSubview(labeled(title, popup))
    }

    private func addTextField(_ stack: NSStackView, title: String, value: String, action: Selector) {
        let field = NSTextField(string: value)
        field.placeholderString = title
        field.target = self
        field.action = action
        field.widthAnchor.constraint(equalToConstant: 420).isActive = true
        stack.addArrangedSubview(labeled(title, field))
    }

    private func addMultilineText(_ stack: NSStackView, title: String, text: String, action: Selector) {
        let textView = SettingsTextView()
        textView.string = text
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.onEndEditing = { [weak self, weak textView] in
            guard let self, let textView else { return }
            self.perform(action, with: textView)
        }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = textView
        scroll.widthAnchor.constraint(equalToConstant: 430).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 72).isActive = true
        stack.addArrangedSubview(labeled(title, scroll))
    }

    private func labeled(_ title: String, _ view: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label, view])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    private func speedLabel(_ value: Int64) -> String {
        value > 0 ? ByteCountFormatter.downloadFormatter.string(fromByteCount: value) + "/s" : L10n.string("speed_unlimited")
    }

    private func persistSettings() {
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
            coordinator.reloadSettings(settings)
        } catch {
            assertionFailure("Failed to persist settings: \(error)")
        }
    }

    @objc private func chooseDefaultDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.defaultDownloadDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.defaultDownloadDirectory = url
            persistSettings()
            rebuildTabs()
        }
    }

    @objc private func concurrentTasksChanged(_ sender: NSStepper) { settings.concurrentTaskLimit = sender.integerValue; persistSettings(); rebuildTabs() }
    @objc private func httpMultithreadingChanged(_ sender: NSButton) { settings.httpMultithreadingEnabled = sender.state == .on; persistSettings(); rebuildTabs() }
    @objc private func httpSegmentCountChanged(_ sender: NSStepper) { settings.httpSegmentCount = sender.integerValue; persistSettings(); rebuildTabs() }
    @objc private func hideTempFilesChanged(_ sender: NSButton) { settings.hideHTTPTemporaryFiles = sender.state == .on; persistSettings() }
    @objc private func retryLimitChanged(_ sender: NSStepper) { settings.retryLimit = sender.integerValue; persistSettings(); rebuildTabs() }
    @objc private func downloadLimitChanged(_ sender: NSPopUpButton) { settings.globalDownloadLimitBytes = sender.selectedItem?.representedObject as? Int64 ?? 0; persistSettings() }
    @objc private func uploadLimitChanged(_ sender: NSPopUpButton) { settings.globalUploadLimitBytes = sender.selectedItem?.representedObject as? Int64 ?? 0; persistSettings() }
    @objc private func downloadRulesChanged(_ sender: SettingsTextView) { settings.downloadRulesText = sender.string; persistSettings() }
    @objc private func torrentEngineChanged(_ sender: NSPopUpButton) { settings.torrentEngine = TorrentEngineKind.allCases[safe: sender.indexOfSelectedItem] ?? .swift; persistSettings() }
    @objc private func torrentDHTChanged(_ sender: NSButton) { settings.torrentDHTEnabled = sender.state == .on; persistSettings() }
    @objc private func torrentPEXChanged(_ sender: NSButton) { settings.torrentPEXEnabled = sender.state == .on; persistSettings() }
    @objc private func torrentLSDChanged(_ sender: NSButton) { settings.torrentLSDEnabled = sender.state == .on; persistSettings() }
    @objc private func torrentSequentialChanged(_ sender: NSButton) { settings.torrentSequentialDownloadEnabled = sender.state == .on; persistSettings() }
    @objc private func torrentTimeoutChanged(_ sender: NSStepper) { settings.torrentMagnetMetadataTimeoutSeconds = sender.integerValue; persistSettings(); rebuildTabs() }
    @objc private func torrentConnectionsChanged(_ sender: NSStepper) { settings.torrentMaxConnections = sender.integerValue; persistSettings(); rebuildTabs() }
    @objc private func torrentUploadSlotsChanged(_ sender: NSStepper) { settings.torrentMaxUploadSlots = sender.integerValue; persistSettings(); rebuildTabs() }
    @objc private func torrentBootstrapChanged(_ sender: SettingsTextView) { settings.torrentDHTBootstrapNodes = sender.string.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }; persistSettings() }
    @objc private func languageChanged(_ sender: NSPopUpButton) { settings.language = AppLanguage.allCases[safe: sender.indexOfSelectedItem] ?? .system; persistSettings(); rebuildTabs() }
    @objc private func logLevelChanged(_ sender: NSPopUpButton) { settings.diagnosticLogLevel = DiagnosticLogLevel.allCases[safe: sender.indexOfSelectedItem] ?? .normal; persistSettings() }
    @objc private func completionNotificationsChanged(_ sender: NSButton) { settings.completionNotificationsEnabled = sender.state == .on; persistSettings() }
    @objc private func clipboardDetectionChanged(_ sender: NSButton) { settings.clipboardDetectionEnabled = sender.state == .on; persistSettings() }
    @objc private func launchAtLoginChanged(_ sender: NSButton) { settings.launchAtLoginEnabled = sender.state == .on; persistSettings() }
    @objc private func keepRunningChanged(_ sender: NSButton) { settings.keepRunningInMenuBar = sender.state == .on; persistSettings() }
    @objc private func preventSleepChanged(_ sender: NSButton) { settings.preventSleepDuringDownloads = sender.state == .on; persistSettings() }
    @objc private func promptBeforeQuitChanged(_ sender: NSButton) { settings.promptBeforeQuittingWithActiveTasks = sender.state == .on; persistSettings() }
    @objc private func scriptPathChanged(_ sender: NSTextField) { settings.completionScriptPath = sender.stringValue; persistSettings() }
    @objc private func confirmBrowserTakeoverChanged(_ sender: NSButton) { settings.confirmBrowserTakeoverDownloads = sender.state == .on; persistSettings() }
    @objc private func allowedHostsChanged(_ sender: SettingsTextView) { settings.browserTakeoverAllowedHostsText = sender.string; persistSettings() }
    @objc private func blockedHostsChanged(_ sender: SettingsTextView) { settings.browserTakeoverBlockedHostsText = sender.string; persistSettings() }
    @objc private func checkDiagnostics() { diagnostics.check(); rebuildTabs() }
    @objc private func repairDiagnostics() { diagnostics.repair(); rebuildTabs() }
    @objc private func revealManifest() { diagnostics.revealManifest() }
    @objc private func copyDiagnostics() { coordinator.copyDiagnostics(nativeHostDiagnostics: diagnostics) }
    @objc private func checkForUpdates() { updater.checkForUpdates(); rebuildTabs() }
    @objc private func automaticChecksChanged(_ sender: NSButton) { updater.setAutomaticUpdateChecksEnabled(sender.state == .on); rebuildTabs() }
    @objc private func automaticDownloadsChanged(_ sender: NSButton) { updater.setAutomaticDownloadsEnabled(sender.state == .on); rebuildTabs() }
}

private final class SettingsTextView: NSTextView {
    var onEndEditing: (() -> Void)?

    override func didChangeText() {
        super.didChangeText()
        onEndEditing?()
    }
}

@MainActor
final class StartupRecoveryWindowController: NSWindowController {
    private let issue: StartupRecoveryIssue
    private let onRetry: () -> Void
    private let onUseTemporaryStore: () -> Void
    private let onBackupAndReset: () -> Void
    private let statusLabel = NSTextField(labelWithString: "")

    init(
        issue: StartupRecoveryIssue,
        onRetry: @escaping () -> Void,
        onUseTemporaryStore: @escaping () -> Void,
        onBackupAndReset: @escaping () -> Void
    ) {
        self.issue = issue
        self.onRetry = onRetry
        self.onUseTemporaryStore = onUseTemporaryStore
        self.onBackupAndReset = onBackupAndReset
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.string("startup_recovery_title")
        window.center()
        super.init(window: window)
        configureContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureContent() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)

        let title = NSTextField(labelWithString: L10n.string("startup_recovery_title"))
        title.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(title)
        addWrappedText(L10n.string("startup_recovery_message"), to: stack)
        addDetail(L10n.string("startup_recovery_store_path"), issue.redactedStorePath, to: stack)
        addDetail(L10n.string("startup_recovery_schema_version"), issue.schemaVersion, to: stack)
        addDetail(L10n.string("startup_recovery_error"), issue.errorDescription, to: stack)
        stack.addArrangedSubview(statusLabel)

        let firstRow = NSStackView()
        firstRow.orientation = .horizontal
        firstRow.spacing = 8
        firstRow.addArrangedSubview(NSButton(title: L10n.string("startup_recovery_retry"), target: self, action: #selector(retry)))
        firstRow.addArrangedSubview(NSButton(title: L10n.string("startup_recovery_copy_diagnostics"), target: self, action: #selector(copyDiagnostics)))
        firstRow.addArrangedSubview(NSButton(title: L10n.string("startup_recovery_reveal_store"), target: self, action: #selector(revealStore)))
        stack.addArrangedSubview(firstRow)

        let secondRow = NSStackView()
        secondRow.orientation = .horizontal
        secondRow.spacing = 8
        secondRow.addArrangedSubview(NSButton(title: L10n.string("startup_recovery_use_temporary"), target: self, action: #selector(useTemporary)))
        let reset = NSButton(title: L10n.string("startup_recovery_backup_reset"), target: self, action: #selector(backupAndReset))
        reset.isEnabled = issue.canRebuildPersistentStore
        secondRow.addArrangedSubview(reset)
        stack.addArrangedSubview(secondRow)

        window?.contentView = stack
    }

    private func addWrappedText(_ text: String, to stack: NSStackView) {
        let field = NSTextField(labelWithString: text)
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.widthAnchor.constraint(equalToConstant: 620).isActive = true
        stack.addArrangedSubview(field)
    }

    private func addDetail(_ title: String, _ value: String, to stack: NSStackView) {
        let field = NSTextField(labelWithString: "\(title)\n\(value)")
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.maximumNumberOfLines = 0
        field.widthAnchor.constraint(equalToConstant: 620).isActive = true
        stack.addArrangedSubview(field)
    }

    @objc private func retry() { onRetry() }
    @objc private func useTemporary() { onUseTemporaryStore() }
    @objc private func backupAndReset() { onBackupAndReset() }

    @objc private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(StartupRecoveryService.diagnosticsText(for: issue), forType: .string)
        statusLabel.stringValue = L10n.string("startup_recovery_diagnostics_copied")
    }

    @objc private func revealStore() {
        NSWorkspace.shared.activateFileViewerSelecting([issue.storeURL.deletingLastPathComponent()])
        statusLabel.stringValue = L10n.string("startup_recovery_store_revealed")
    }
}

private final class SpeedLimitToolbarView: NSStackView {
    private weak var coordinator: DownloadCoordinator?
    private let label = NSTextField(labelWithString: "")

    init(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 26))
        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        addArrangedSubview(NSImageView(image: NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil) ?? NSImage()))
        addArrangedSubview(label)
        update()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func update() {
        guard let coordinator else { return }
        let speed = coordinator.allTasks()
            .filter { $0.status == .running || $0.status == .fetchingMetadata || $0.status == .fetchingPeers || $0.status == .connectingPeers }
            .reduce(Int64(0)) { $0 + $1.speedBytesPerSecond }
        label.stringValue = speed > 0 ? ByteCountFormatter.downloadFormatter.string(fromByteCount: speed) + "/s" : "0 KB/s"
    }
}

private extension L10n {
    static func string(_ key: String, fallback: String) -> String {
        let value = string(key)
        return value == key ? fallback : value
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
