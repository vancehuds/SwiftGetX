import AppKit
import SwiftData
import SwiftGetXCore
import UniformTypeIdentifiers
import UserNotifications

@main
enum SwiftGetXApp {
    @MainActor private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}

@MainActor
final class AppController: NSObject, NSMenuItemValidation {
    private weak var appDelegate: AppDelegate?
    private let chromeNativeHostRegistrar = ChromeNativeHostRegistrar()
    private let softwareUpdater = SoftwareUpdater()
    private let coordinator = DownloadCoordinator()
    private let browserBridge = BrowserBridge()
    private let clipboardMonitor = ClipboardMonitor()
    private let appSettings = AppSettings()

    private var startupState: StartupModelContainerState
    private var modelContainer: ModelContainer?
    private var mainWindowController: MainWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var newTaskWindowController: NewTaskWindowController?
    private var startupRecoveryWindowController: StartupRecoveryWindowController?
    private var observers = [NSObjectProtocol]()

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        startupState = StartupRecoveryService.openPersistentContainer()
        super.init()
    }

    func start() {
        NotificationManager.requestAuthorization()
        buildMainMenu()
        installNotificationObservers()

        switch startupState {
        case .ready(let container):
            configureApp(with: container)
            showMainWindow()
        case .failed(let issue):
            showStartupRecovery(issue)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed() -> Bool {
        appSettings.keepRunningInMenuBar == false
    }

    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        guard appSettings.promptBeforeQuittingWithActiveTasks,
              coordinator.hasActiveDownloadsForSystemPolicy
        else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = L10n.string("quit_active_downloads_title")
        alert.informativeText = L10n.string("quit_active_downloads_message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("quit_pause_and_quit"))
        alert.addButton(withTitle: L10n.string("quit_keep_running"))
        alert.addButton(withTitle: L10n.string("quit_confirm_quit"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            coordinator.pauseActiveTasksForQuit()
            return .terminateNow
        case .alertSecondButtonReturn:
            return .terminateCancel
        default:
            return .terminateNow
        }
    }

    func handle(open urls: [URL]) {
        NSApp.activate(ignoringOtherApps: true)
        if urls.count > 1, let draft = DownloadInputSourceCollector.draft(urls: urls) {
            handleDownloadDraft(draft)
            return
        }

        for url in urls {
            handleOpenURL(url)
        }
    }

    func addDownloadFromService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let draft = DownloadInputSourceCollector.draft(from: pasteboard) else {
            error.pointee = L10n.string("service_no_downloadable_input") as NSString
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        handleDownloadDraft(draft)
    }

    func focusTaskFromNotification(identifier: String) {
        NSApp.activate(ignoringOtherApps: true)
        guard let id = UUID(uuidString: identifier) else { return }
        coordinator.selectedTaskID = id
        coordinator.selectedTaskIDs = [id]
        showMainWindow()
        mainWindowController?.reload()
        mainWindowController?.focusSelectedTask()
    }

    // MARK: - Menu

    private func buildMainMenu() {
        let mainMenu = NSMenu(title: "SwiftGetX")

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "SwiftGetX")
        appMenu.addItem(withTitle: L10n.string("command_check_for_updates"), action: #selector(checkForUpdates), keyEquivalent: "")
            .target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: L10n.string("menu_settings_plain"), action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: L10n.string("menu_quit_app"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        addMenuItem(fileMenu, title: L10n.string("command_new_download"), action: #selector(showNewTask), key: "n")
        addMenuItem(fileMenu, title: L10n.string("command_add_magnet"), action: #selector(showMagnetTask), key: "m", modifiers: [.command, .option])
        addMenuItem(fileMenu, title: L10n.string("command_open_torrent_file"), action: #selector(openTorrentFiles), key: "t", modifiers: [.command, .option])
        addMenuItem(fileMenu, title: L10n.string("command_paste_source"), action: #selector(pasteSourceDraft), key: "v", modifiers: [.command, .option])
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let taskMenuItem = NSMenuItem()
        let taskMenu = NSMenu(title: L10n.string("sidebar_tasks"))
        addMenuItem(taskMenu, title: L10n.string("command_pause_all"), action: #selector(pauseAll), key: "p", modifiers: [.command, .shift])
        addMenuItem(taskMenu, title: L10n.string("command_resume_all"), action: #selector(resumeAll), key: "r", modifiers: [.command, .shift])
        taskMenu.addItem(NSMenuItem.separator())
        addMenuItem(taskMenu, title: L10n.string("command_toggle_selected"), action: #selector(toggleSelected), key: "\r")
        addMenuItem(taskMenu, title: L10n.string("command_retry_selected"), action: #selector(retrySelected), key: "r", modifiers: [.command, .option])
        addMenuItem(taskMenu, title: L10n.string("command_recheck_selected"), action: #selector(recheckSelected), key: "k", modifiers: [.command, .option])
        addMenuItem(taskMenu, title: L10n.string("command_reveal_selected"), action: #selector(revealSelected), key: "o", modifiers: [.command, .option])
        addMenuItem(taskMenu, title: L10n.string("command_delete_selected"), action: #selector(confirmSelectedTaskRemoval), key: "\u{8}", modifiers: [])
        taskMenu.addItem(NSMenuItem.separator())
        addMenuItem(taskMenu, title: L10n.string("command_focus_search"), action: #selector(focusSearch), key: "f")
        taskMenuItem.submenu = taskMenu
        mainMenu.addItem(taskMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: L10n.string("menu_open_app"), action: #selector(showMainWindowFromMenu), keyEquivalent: "0")
            .target = self
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func addMenuItem(
        _ menu: NSMenu,
        title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(checkForUpdates):
            return softwareUpdater.canCheckForUpdates
        case #selector(toggleSelected), #selector(retrySelected), #selector(recheckSelected),
             #selector(revealSelected), #selector(confirmSelectedTaskRemoval):
            return !coordinator.selectedTasks.isEmpty
        case #selector(pauseAll):
            return coordinator.hasActiveDownloadsForSystemPolicy
        default:
            return true
        }
    }

    @objc private func showMainWindowFromMenu() {
        showMainWindow()
    }

    @objc private func checkForUpdates() {
        softwareUpdater.checkForUpdates()
    }

    @objc private func showNewTask() {
        presentNewTask(draft: nil)
    }

    @objc private func showMagnetTask() {
        presentNewTask(draft: DownloadDraft(source: "", sourceCount: 0, prefersTorrentInput: true))
    }

    @objc private func openTorrentFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent") ?? .data]
        guard panel.runModal() == .OK else { return }
        let paths = panel.urls.map(\.path)
        guard !paths.isEmpty else { return }
        presentNewTask(
            draft: DownloadDraft(
                source: paths.joined(separator: "\n"),
                sourceCount: paths.count,
                prefersTorrentInput: true
            )
        )
    }

    @objc private func pasteSourceDraft() {
        guard let source = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty
        else {
            presentNewTask(draft: nil)
            return
        }

        presentNewTask(
            draft: DownloadDraft(
                source: source,
                sourceCount: SourceParser.extractSources(from: source).count,
                prefersTorrentInput: Self.looksLikeTorrentSource(source)
            )
        )
    }

    @objc private func pauseAll() {
        coordinator.pauseAll()
        mainWindowController?.reload()
    }

    @objc private func resumeAll() {
        coordinator.resumeAll()
        mainWindowController?.reload()
    }

    @objc private func toggleSelected() {
        if coordinator.selectedTasks.contains(where: { $0.usesActiveDownloadSlot || $0.status == .seeding }) {
            coordinator.pauseSelected()
        } else {
            coordinator.resumeSelected()
        }
        mainWindowController?.reload()
    }

    @objc private func retrySelected() {
        coordinator.retrySelected()
        mainWindowController?.reload()
    }

    @objc private func recheckSelected() {
        coordinator.recheckSelected()
        mainWindowController?.reload()
    }

    @objc private func revealSelected() {
        coordinator.revealSelectedInFinder()
    }

    @objc private func confirmSelectedTaskRemoval() {
        mainWindowController?.confirmSelectedTaskRemoval()
    }

    @objc private func focusSearch() {
        showMainWindow()
        mainWindowController?.focusSearch()
    }

    @objc private func showSettings() {
        presentSettings()
    }

    // MARK: - Windows

    private func showMainWindow() {
        guard case .ready = startupState else { return }
        if mainWindowController == nil {
            mainWindowController = MainWindowController(
                coordinator: coordinator,
                settings: appSettings,
                clipboardMonitor: clipboardMonitor,
                onNewTask: { [weak self] draft in self?.presentNewTask(draft: draft) },
                onSettings: { [weak self] in self?.presentSettings() }
            )
        }
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showStartupRecovery(_ issue: StartupRecoveryIssue) {
        startupRecoveryWindowController = StartupRecoveryWindowController(
            issue: issue,
            onRetry: { [weak self] in self?.retryStartup() },
            onUseTemporaryStore: { [weak self] in self?.useTemporaryStore() },
            onBackupAndReset: { [weak self] in self?.backupAndResetPersistentStore() }
        )
        startupRecoveryWindowController?.showWindow(nil)
        startupRecoveryWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func presentSettings() {
        guard let modelContainer else { return }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: appSettings,
                coordinator: coordinator,
                updater: softwareUpdater,
                modelContext: modelContainer.mainContext
            )
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentNewTask(draft: DownloadDraft?) {
        guard case .ready = startupState else {
            if let draft {
                handleOpenURLWhenPersistenceUnavailable(URL(string: draft.source) ?? URL(fileURLWithPath: draft.source))
            }
            return
        }

        PendingNativeHandoffPolicy.rejectIfReplaced(
            current: newTaskWindowController?.draft,
            incoming: draft
        )

        let controller = NewTaskWindowController(
            draft: draft,
            settings: appSettings,
            coordinator: coordinator,
            onComplete: { [weak self] in
                self?.newTaskWindowController = nil
                self?.mainWindowController?.reload()
            }
        )
        newTaskWindowController = controller

        if let mainWindow = mainWindowController?.window {
            mainWindow.beginSheet(controller.window!) { [weak self] _ in
                self?.newTaskWindowController = nil
                self?.mainWindowController?.reload()
            }
        } else {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Startup

    private func configureApp(with modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        loadSettings(modelContainer: modelContainer)
        coordinator.attach(modelContext: modelContainer.mainContext, settings: appSettings)
        appDelegate?.attachMenuBar(coordinator: coordinator, settings: appSettings)
        browserBridge.attach(coordinator: coordinator)
        clipboardMonitor.attach(coordinator: coordinator, settings: appSettings)
        coordinator.restoreIncompleteTasks()
        registerChromeNativeHost()
    }

    private func retryStartup() {
        startupState = StartupRecoveryService.openPersistentContainer()
        startupRecoveryWindowController?.close()
        startupRecoveryWindowController = nil

        switch startupState {
        case .ready(let container):
            configureApp(with: container)
            showMainWindow()
        case .failed(let issue):
            showStartupRecovery(issue)
        }
    }

    private func useTemporaryStore() {
        do {
            startupState = .ready(try StartupRecoveryService.makeTemporaryContainer())
            startupRecoveryWindowController?.close()
            startupRecoveryWindowController = nil
            if case .ready(let container) = startupState {
                configureApp(with: container)
            }
            showMainWindow()
        } catch {
            startupState = .failed(StartupRecoveryService.issue(for: error))
            if case .failed(let issue) = startupState {
                showStartupRecovery(issue)
            }
        }
    }

    private func backupAndResetPersistentStore() {
        do {
            _ = try StartupRecoveryService.backupAndResetPersistentStore()
            retryStartup()
        } catch {
            startupState = .failed(StartupRecoveryService.issue(for: error))
            if case .failed(let issue) = startupState {
                showStartupRecovery(issue)
            }
        }
    }

    // MARK: - Notifications

    private func installNotificationObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .showNewTaskSheet, object: nil, queue: .main) { [weak self] notification in
            let draft = notification.object as? DownloadDraft
            Task { @MainActor in self?.presentNewTask(draft: draft) }
        })
        observers.append(center.addObserver(forName: .pauseAllDownloads, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pauseAll() }
        })
        observers.append(center.addObserver(forName: .resumeAllDownloads, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeAll() }
        })
        observers.append(center.addObserver(forName: .openSwiftGetXSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.presentSettings() }
        })
        observers.append(center.addObserver(forName: .focusTaskSearch, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.focusSearch() }
        })
        observers.append(center.addObserver(forName: .confirmSelectedTaskRemoval, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.confirmSelectedTaskRemoval() }
        })
        observers.append(center.addObserver(forName: .focusTaskFromNotification, object: nil, queue: .main) { [weak self] notification in
            guard let identifier = notification.object as? String else { return }
            Task { @MainActor in self?.focusTaskFromNotification(identifier: identifier) }
        })
    }

    // MARK: - URL handling

    private func handleOpenURL(_ url: URL) {
        switch startupState {
        case .failed:
            handleOpenURLWhenPersistenceUnavailable(url)
        case .ready:
            if let draft = DeepLinkParser.downloadDraft(from: url) {
                handleDownloadDraft(draft)
            } else if DeepLinkParser.isDownloadURL(url) {
                return
            } else if let setupRequest = DeepLinkParser.browserSetupRequest(from: url) {
                handleBrowserSetupRequest(setupRequest)
            } else if DeepLinkParser.isBrowserSetupURL(url) {
                return
            } else if let draft = DownloadInputSourceCollector.draft(urls: [url]) {
                handleDownloadDraft(draft)
            } else {
                coordinator.add(source: url.absoluteString)
                mainWindowController?.reload()
            }
        }
    }

    private func handleOpenURLWhenPersistenceUnavailable(_ url: URL) {
        guard let draft = DeepLinkParser.downloadDraft(from: url) else { return }
        acknowledgeNativeHandoff(
            draft,
            decision: .rejected(
                reason: "persistenceUnavailable",
                requiresUserConfirmation: draft.requiresUserConfirmation || draft.isBrowserTakeover,
                message: "SwiftGetX could not open its download database"
            )
        )
    }

    private func handleDownloadDraft(_ draft: DownloadDraft) {
        if let resolution = PendingNativeHandoffPolicy.expirationResolution(draft: draft) {
            PendingNativeHandoffPolicy.acknowledge(resolution)
            return
        }

        if draft.isTrustedNativeHandoff, let handoffAck = draft.handoffAck {
            Task {
                do {
                    var enrichedDraft = draft
                    let context = try await NativeHandoffPayloadClient.fetchContext(handoff: handoffAck)
                    enrichedDraft.browserContext = context
                    let didApplyPayloadSource = applyPayloadSource(from: context, to: &enrichedDraft)
                    if enrichedDraft.requiresNativePayloadSource && !didApplyPayloadSource {
                        acknowledgeNativeHandoff(
                            draft,
                            decision: .rejected(
                                reason: "payloadUnavailable",
                                requiresUserConfirmation: draft.requiresUserConfirmation || draft.isBrowserTakeover,
                                message: "SwiftGetX could not fetch the native handoff payload"
                            )
                        )
                        return
                    }
                    handleDownloadDraftWithContext(enrichedDraft)
                } catch {
                    if draft.requiresNativePayloadSource {
                        acknowledgeNativeHandoff(
                            draft,
                            decision: .rejected(
                                reason: "payloadUnavailable",
                                requiresUserConfirmation: draft.requiresUserConfirmation || draft.isBrowserTakeover,
                                message: "SwiftGetX could not fetch the native handoff payload"
                            )
                        )
                        return
                    }
                    handleDownloadDraftWithContext(draft.publicLinkFallback)
                }
            }
            return
        }

        handleDownloadDraftWithContext(draft)
    }

    private func handleDownloadDraftWithContext(_ draft: DownloadDraft) {
        if let resolution = PendingNativeHandoffPolicy.expirationResolution(draft: draft) {
            PendingNativeHandoffPolicy.acknowledge(resolution)
            return
        }

        if let decision = browserTakeoverPolicyRejection(for: draft) {
            acknowledgeNativeHandoff(draft, decision: decision)
            return
        }

        if let decision = BrowserDownloadRecoveryPolicy.nativeHandoffRejection(for: draft) {
            acknowledgeNativeHandoff(draft, decision: decision)
            return
        }

        if draft.requiresUserConfirmation
            || (draft.isTrustedNativeHandoff && draft.isBrowserTakeover && appSettings.confirmBrowserTakeoverDownloads)
        {
            presentNewTask(draft: draft)
        } else {
            let tasks = coordinator.add(
                source: draft.source,
                suggestedFilename: draft.suggestedFilename,
                browserContext: draft.browserContext
            )
            acknowledgeNativeHandoff(
                draft,
                decision: NativeHandoffDecisionFactory.decision(
                    queuedTaskCount: tasks.count,
                    requiresUserConfirmation: false
                )
            )
            mainWindowController?.reload()
        }
    }

    private func browserTakeoverPolicyRejection(for draft: DownloadDraft) -> NativeHandoffAckDecision? {
        guard draft.isTrustedNativeHandoff, draft.isBrowserTakeover else { return nil }
        let sources = SourceParser.extractSources(from: draft.source)
        for source in sources where SourceParser.kind(for: source) == .http {
            switch BrowserTakeoverPolicy.decision(
                for: source,
                allowedHosts: appSettings.browserTakeoverAllowedHosts,
                blockedHosts: appSettings.browserTakeoverBlockedHosts
            ) {
            case .allowed:
                continue
            case .rejected(let reason):
                return .rejected(
                    reason: reason,
                    requiresUserConfirmation: draft.requiresUserConfirmation || draft.isBrowserTakeover,
                    message: "SwiftGetX rejected the browser takeover by host policy"
                )
            }
        }
        return nil
    }

    private func acknowledgeNativeHandoff(_ draft: DownloadDraft, decision: NativeHandoffAckDecision) {
        guard let handoffAck = draft.handoffAck else { return }
        Task.detached {
            try? await NativeHandoffAckClient.acknowledge(decision, handoff: handoffAck)
        }
    }

    private func applyPayloadSource(from context: BrowserDownloadContext, to draft: inout DownloadDraft) -> Bool {
        let source: String?
        if draft.requiresNativePayloadSource {
            source = context.handoffSourceText
        } else {
            source = context.handoffSourceText ?? context.originalURL ?? context.finalURL
        }
        guard let source else { return false }

        guard let validation = DownloadDeepLinkPolicy.validationForTrustedPayloadSource(source) else {
            return false
        }

        draft.source = source
        draft.sourceCount = validation.sourceCount
        draft.requiresNativePayloadSource = false
        return true
    }

    private func handleBrowserSetupRequest(_ request: BrowserSetupRequest) {
        guard chromeNativeHostRegistrar.isSupportedBrowserName(request.browser) else { return }
        let compatibility = BrowserIntegrationCompatibility.extensionCompatibility(
            extensionVersion: request.version,
            minimumNativeHostVersion: request.minimumNativeHostVersion,
            protocolVersion: request.protocolVersion,
            requiresExplicitVersion: true
        )
        guard compatibility.compatible else {
            showBrowserCompatibilityRejectedAlert(
                message: compatibility.message ?? L10n.string("alert_browser_pairing_incompatible_message")
            )
            return
        }

        if chromeNativeHostRegistrar.isPairedExtensionID(request.extensionID) {
            _ = chromeNativeHostRegistrar.register()
            return
        }

        guard chromeNativeHostRegistrar.canPairExtensionID(request.extensionID) else {
            showChromePairingRejectedAlert(extensionID: request.extensionID)
            return
        }

        guard confirmChromePairing(request) else { return }
        _ = chromeNativeHostRegistrar.pairAndRegister(extensionID: request.extensionID)
    }

    private func registerChromeNativeHost() {
        _ = chromeNativeHostRegistrar.register()
    }

    private func loadSettings(modelContainer: ModelContainer) {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<AppSettingsRecord>(
            predicate: #Predicate { $0.id == "default" }
        )
        if let record = try? context.fetch(descriptor).first {
            appSettings.apply(record)
        } else {
            let record = appSettings.makeRecord()
            context.insert(record)
            try? context.save()
        }
    }

    private func confirmChromePairing(_ request: BrowserSetupRequest) -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.string("alert_allow_browser_pairing_title", request.browser)
        alert.informativeText = L10n.string("alert_allow_browser_pairing_message", request.browser, request.extensionID)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("action_allow_pairing"))
        alert.addButton(withTitle: L10n.string("action_reject"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showChromePairingRejectedAlert(extensionID: String) {
        let alert = NSAlert()
        alert.messageText = L10n.string("alert_browser_pairing_rejected_title")
        alert.informativeText = L10n.string("alert_browser_pairing_rejected_message", extensionID)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("action_ok"))
        alert.runModal()
    }

    private func showBrowserCompatibilityRejectedAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.string("alert_browser_pairing_incompatible_title")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("action_ok"))
        alert.runModal()
    }

    private static func looksLikeTorrentSource(_ source: String) -> Bool {
        SourceParser.extractSources(from: source).contains { candidate in
            let kind = SourceParser.kind(for: candidate)
            return kind == .torrentMagnet || kind == .torrentFile
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    private var appController: AppController?
    private var menuBarController: MenuBarController?
    private var coordinator: DownloadCoordinator?
    private var settings: AppSettings?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.setDelegate(self)
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        let controller = AppController(appDelegate: self)
        appController = controller
        controller.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Native Messaging host registration also happens during app setup and
        // browser pairing. Keeping this event quiet avoids duplicate repair work.
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        appController?.handle(open: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        appController?.applicationShouldTerminateAfterLastWindowClosed() ?? true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        appController?.applicationShouldTerminate() ?? .terminateNow
    }

    @objc(addDownloadFromService:userData:error:)
    func addDownloadFromService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        appController?.addDownloadFromService(pasteboard, userData: userData, error: error)
    }

    func attachMenuBar(coordinator: DownloadCoordinator, settings: AppSettings) {
        self.coordinator = coordinator
        self.settings = settings
        if menuBarController == nil {
            menuBarController = MenuBarController()
        }
        menuBarController?.attach(coordinator: coordinator, settings: settings)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        await MainActor.run {
            appController?.focusTaskFromNotification(identifier: identifier)
        }
    }
}

enum NativeHandoffDecisionFactory {
    static func decision(
        queuedTaskCount: Int,
        requiresUserConfirmation: Bool
    ) -> NativeHandoffAckDecision {
        guard queuedTaskCount > 0 else {
            return .rejected(
                reason: "noDownloadableSources",
                requiresUserConfirmation: requiresUserConfirmation,
                message: "SwiftGetX received the request but no downloadable sources were found"
            )
        }

        let confirmationText = requiresUserConfirmation ? "confirmed " : ""
        return .accepted(
            queued: true,
            requiresUserConfirmation: requiresUserConfirmation,
            message: "SwiftGetX queued \(queuedTaskCount) \(confirmationText)download task(s)"
        )
    }
}

enum DeepLinkParser {
    static func downloadDraft(from url: URL) -> DownloadDraft? {
        guard url.scheme == "swiftgetx", url.host == "download",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        guard components.queryItems?.filter({ $0.name == "url" }).count == 1 else {
            return nil
        }

        guard let source = queryValue("url", in: components), !source.isEmpty else {
            return nil
        }

        let handoffAck = handoffAck(in: components)
        let handoffSource = queryValue("source", in: components)
        guard let validation = DownloadDeepLinkPolicy.validation(
            for: url,
            components: components,
            source: source,
            handoffSource: handoffSource,
            handoffAck: handoffAck
        ) else {
            return nil
        }

        let isTrustedNativeHandoff = validation.linkTrust == .trustedNativeHandoff
        let hasExpiredNativeHandoff = DownloadDeepLinkPolicy.isNativeHandoffSource(handoffSource)
            && handoffAck?.expiresAt != nil
            && handoffAck?.isExpired() == true
        let shouldKeepNativeHandoff = isTrustedNativeHandoff || hasExpiredNativeHandoff
        let browserContext: BrowserDownloadContext?
        if isTrustedNativeHandoff {
            browserContext = BrowserDownloadContext(
                referrer: queryValue("sourcePageUrl", in: components),
                originalURL: source,
                suggestedFilename: queryValue("filename", in: components),
                sourcePageTitle: queryValue("sourcePageTitle", in: components),
                sourcePageURL: queryValue("sourcePageUrl", in: components),
                handoffSource: handoffSource
            )
        } else {
            browserContext = nil
        }

        return DownloadDraft(
            source: source,
            suggestedFilename: queryValue("filename", in: components),
            browser: queryValue("browser", in: components),
            handoffSource: shouldKeepNativeHandoff ? handoffSource : nil,
            sourcePageTitle: isTrustedNativeHandoff ? queryValue("sourcePageTitle", in: components) : nil,
            sourcePageUrl: isTrustedNativeHandoff ? queryValue("sourcePageUrl", in: components) : nil,
            handoffAck: shouldKeepNativeHandoff ? handoffAck : nil,
            browserContext: browserContext,
            linkTrust: validation.linkTrust,
            sourceCount: validation.sourceCount,
            requiresNativePayloadSource: isTrustedNativeHandoff
                && queryValue("payloadSource", in: components) == "1"
        )
    }

    static func browserSetupRequest(from url: URL) -> BrowserSetupRequest? {
        guard url.scheme == "swiftgetx", url.host == "browser-setup",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let browser = queryValue("browser", in: components),
              let extensionID = queryValue("extensionID", in: components),
              ChromeNativeMessagingOrigin.isValidExtensionID(extensionID)
        else {
            return nil
        }

        return BrowserSetupRequest(
            browser: browser,
            extensionID: extensionID,
            version: queryValue("version", in: components),
            protocolVersion: queryValue("protocolVersion", in: components).flatMap(Int.init),
            minimumNativeHostVersion: queryValue("minimumNativeHostVersion", in: components)
        )
    }

    static func isBrowserSetupURL(_ url: URL) -> Bool {
        url.scheme == "swiftgetx" && url.host == "browser-setup"
    }

    static func isDownloadURL(_ url: URL) -> Bool {
        url.scheme == "swiftgetx" && url.host == "download"
    }

    private static func queryValue(_ name: String, in components: URLComponents) -> String? {
        components.queryItems?.first(where: { $0.name == name })?.value
    }

    private static func handoffAck(in components: URLComponents) -> NativeHandoffAck? {
        guard let requestID = queryValue("ackRequestID", in: components),
              let token = queryValue("ackToken", in: components),
              let portString = queryValue("ackPort", in: components),
              let port = UInt16(portString),
              !requestID.isEmpty,
              !token.isEmpty
        else {
            return nil
        }

        return NativeHandoffAck(
            requestID: requestID,
            token: token,
            port: port,
            expiresAt: ackExpiresAt(in: components)
        )
    }

    private static func ackExpiresAt(in components: URLComponents) -> Date? {
        guard let value = queryValue("ackExpiresAt", in: components) else { return nil }
        guard let timestamp = TimeInterval(value), timestamp > 0 else { return Date(timeIntervalSince1970: 0) }

        return Date(timeIntervalSince1970: timestamp)
    }
}

struct BrowserSetupRequest: Equatable {
    var browser: String
    var extensionID: String
    var version: String?
    var protocolVersion: Int?
    var minimumNativeHostVersion: String?
}

extension Notification.Name {
    static let showNewTaskSheet = Notification.Name("SwiftGetX.showNewTaskSheet")
    static let focusTaskFromNotification = Notification.Name("SwiftGetX.focusTaskFromNotification")
    static let focusTaskSearch = Notification.Name("SwiftGetX.focusTaskSearch")
    static let confirmSelectedTaskRemoval = Notification.Name("SwiftGetX.confirmSelectedTaskRemoval")
}
