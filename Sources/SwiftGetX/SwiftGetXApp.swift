import AppKit
import SwiftData
import SwiftUI
import SwiftGetXCore
import UserNotifications

@main
struct SwiftGetXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var softwareUpdater = SoftwareUpdater()

    private let modelContainer: ModelContainer
    private let chromeNativeHostRegistrar = ChromeNativeHostRegistrar()
    @State private var coordinator = DownloadCoordinator()
    @State private var browserBridge = BrowserBridge()
    @State private var clipboardMonitor = ClipboardMonitor()
    @State private var appSettings = AppSettings()

    init() {
        do {
            modelContainer = try SwiftGetXPersistence.makeModelContainer()
        } catch {
            fatalError("Unable to create SwiftData container: \(error)")
        }

        NotificationManager.requestAuthorization()
        WindowConfigurator.configureDefaultAppearance()
    }

    var body: some Scene {
        Window("SwiftGetX", id: "main") {
            ContentView()
                .environment(coordinator)
                .environment(browserBridge)
                .environment(clipboardMonitor)
                .environment(appSettings)
                .modelContainer(modelContainer)
                .task {
                    loadSettings()
                    coordinator.attach(modelContext: modelContainer.mainContext, settings: appSettings)
                    appDelegate.attachMenuBar(coordinator: coordinator, settings: appSettings)
                    browserBridge.attach(coordinator: coordinator)
                    clipboardMonitor.attach(coordinator: coordinator, settings: appSettings)
                    coordinator.restoreIncompleteTasks()
                    registerChromeNativeHost()
                }
                .onOpenURL { url in
                    NSApp.activate(ignoringOtherApps: true)
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
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands(
                language: appSettings.language,
                coordinator: coordinator,
                updater: softwareUpdater
            )
        }

        Settings {
            SettingsView(updater: softwareUpdater)
                .environment(appSettings)
                .environment(coordinator)
                .modelContainer(modelContainer)
                .frame(minWidth: 420, idealWidth: 520, minHeight: 390, idealHeight: 480)
                .id(appSettings.language)
        }
    }

    @MainActor
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

    @MainActor
    private func handleDownloadDraftWithContext(_ draft: DownloadDraft) {
        if let resolution = PendingNativeHandoffPolicy.expirationResolution(draft: draft) {
            PendingNativeHandoffPolicy.acknowledge(resolution)
            return
        }

        if let decision = browserTakeoverPolicyRejection(for: draft) {
            acknowledgeNativeHandoff(draft, decision: decision)
            return
        }

        if draft.requiresUserConfirmation
            || (draft.isTrustedNativeHandoff && draft.isBrowserTakeover && appSettings.confirmBrowserTakeoverDownloads)
        {
            NotificationCenter.default.post(name: .showNewTaskSheet, object: draft)
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

    @MainActor
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

    @MainActor
    private func registerChromeNativeHost() {
        _ = chromeNativeHostRegistrar.register()
    }

    @MainActor
    private func loadSettings() {
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

    @MainActor
    private func confirmChromePairing(_ request: BrowserSetupRequest) -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.string("alert_allow_browser_pairing_title", request.browser)
        alert.informativeText = L10n.string("alert_allow_browser_pairing_message", request.browser, request.extensionID)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("action_allow_pairing"))
        alert.addButton(withTitle: L10n.string("action_reject"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private func showChromePairingRejectedAlert(extensionID: String) {
        let alert = NSAlert()
        alert.messageText = L10n.string("alert_browser_pairing_rejected_title")
        alert.informativeText = L10n.string("alert_browser_pairing_rejected_message", extensionID)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("action_ok"))
        alert.runModal()
    }

    @MainActor
    private func showBrowserCompatibilityRejectedAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.string("alert_browser_pairing_incompatible_title")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.string("action_ok"))
        alert.runModal()
    }
}

struct AppCommands: Commands {
    let language: AppLanguage
    let coordinator: DownloadCoordinator
    let updater: SoftwareUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesView(updater: updater)
                .id(language)
        }
        CommandGroup(after: .newItem) {
            Button(L10n.string("command_new_download")) {
                NotificationCenter.default.post(name: .showNewTaskSheet, object: nil)
            }
            .keyboardShortcut("n")

            Button(L10n.string("command_pause_all")) {
                coordinator.pauseAll()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button(L10n.string("command_resume_all")) {
                coordinator.resumeAll()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button(L10n.string("command_toggle_selected")) {
                if coordinator.selectedTasks.contains(where: { $0.usesActiveDownloadSlot || $0.status == .seeding }) {
                    coordinator.pauseSelected()
                } else {
                    coordinator.resumeSelected()
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])

            Button(L10n.string("command_retry_selected")) {
                coordinator.retrySelected()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])

            Button(L10n.string("command_recheck_selected")) {
                coordinator.recheckSelected()
            }
            .keyboardShortcut("k", modifiers: [.command, .option])

            Button(L10n.string("command_reveal_selected")) {
                coordinator.revealSelectedInFinder()
            }
            .keyboardShortcut("o", modifiers: [.command, .option])

            Button(L10n.string("command_delete_selected")) {
                NotificationCenter.default.post(name: .confirmSelectedTaskRemoval, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: [])

            Button(L10n.string("command_focus_search")) {
                NotificationCenter.default.post(name: .focusTaskSearch, object: nil)
            }
            .keyboardShortcut("f")
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

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var menuBarController: MenuBarController?
    private let chromeNativeHostRegistrar = ChromeNativeHostRegistrar()
    private var coordinator: DownloadCoordinator?
    private var settings: AppSettings?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.setDelegate(self)
        menuBarController = MenuBarController()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        registerChromeNativeHost()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        registerChromeNativeHost()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let draft = DownloadInputSourceCollector.draft(urls: urls) else { return }
        postDownloadDraft(draft)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        settings?.keepRunningInMenuBar == false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard settings?.promptBeforeQuittingWithActiveTasks ?? true,
              let coordinator,
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

    @objc(addDownloadFromService:userData:error:)
    func addDownloadFromService(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let draft = DownloadInputSourceCollector.draft(from: pasteboard) else {
            error.pointee = L10n.string("service_no_downloadable_input") as NSString
            return
        }
        postDownloadDraft(draft)
    }

    @MainActor
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
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(
                name: .focusTaskFromNotification,
                object: identifier
            )
        }
    }

    private func registerChromeNativeHost() {
        _ = chromeNativeHostRegistrar.register()
    }

    private func postDownloadDraft(_ draft: DownloadDraft) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .showNewTaskSheet, object: draft)
        }
    }
}

extension Notification.Name {
    static let showNewTaskSheet = Notification.Name("SwiftGetX.showNewTaskSheet")
    static let focusTaskFromNotification = Notification.Name("SwiftGetX.focusTaskFromNotification")
    static let focusTaskSearch = Notification.Name("SwiftGetX.focusTaskSearch")
}
