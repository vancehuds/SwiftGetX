import AppKit
import SwiftData
import SwiftUI
import SwiftGetXCore
import UserNotifications

@main
struct SwiftGetXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    private let chromeNativeHostRegistrar = ChromeNativeHostRegistrar()
    @State private var coordinator = DownloadCoordinator()
    @State private var browserBridge = BrowserBridge()
    @State private var clipboardMonitor = ClipboardMonitor()
    @State private var appSettings = AppSettings()

    init() {
        do {
            modelContainer = try ModelContainer(for: DownloadTask.self, AppSettingsRecord.self)
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
                    } else if let setupRequest = DeepLinkParser.browserSetupRequest(from: url) {
                        handleBrowserSetupRequest(setupRequest)
                    } else if DeepLinkParser.isBrowserSetupURL(url) {
                        return
                    } else {
                        coordinator.add(source: url.absoluteString)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("新建下载任务") {
                    NotificationCenter.default.post(name: .showNewTaskSheet, object: nil)
                }
                .keyboardShortcut("n")

                Button("暂停全部") {
                    coordinator.pauseAll()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("恢复全部") {
                    coordinator.resumeAll()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(appSettings)
                .environment(coordinator)
                .modelContainer(modelContainer)
                .frame(minWidth: 420, idealWidth: 520, minHeight: 390, idealHeight: 480)
        }
    }

    @MainActor
    private func handleDownloadDraft(_ draft: DownloadDraft) {
        if draft.isBrowserTakeover, appSettings.confirmBrowserTakeoverDownloads {
            NotificationCenter.default.post(name: .showNewTaskSheet, object: draft)
        } else {
            coordinator.add(source: draft.source, suggestedFilename: draft.suggestedFilename)
        }
    }

    @MainActor
    private func handleBrowserSetupRequest(_ request: BrowserSetupRequest) {
        guard request.browser.caseInsensitiveCompare("Chrome") == .orderedSame else { return }

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
        alert.messageText = "允许 Chrome 插件连接 SwiftGetX？"
        alert.informativeText = """
        插件 ID：\(request.extensionID)

        允许后，SwiftGetX 会把这个插件加入 Native Messaging 白名单，并自动修复 com.swiftgetx.native.json。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "允许配对")
        alert.addButton(withTitle: "拒绝")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private func showChromePairingRejectedAlert(extensionID: String) {
        let alert = NSAlert()
        alert.messageText = "无法验证 Chrome 插件"
        alert.informativeText = """
        SwiftGetX 没有在 Chrome 配置中找到匹配的 SwiftGetX 插件，已拒绝配对。

        插件 ID：\(extensionID)
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

enum DeepLinkParser {
    static func downloadDraft(from url: URL) -> DownloadDraft? {
        guard url.scheme == "swiftgetx", url.host == "download",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        guard let source = queryValue("url", in: components), !source.isEmpty else {
            return nil
        }

        return DownloadDraft(
            source: source,
            suggestedFilename: queryValue("filename", in: components),
            browser: queryValue("browser", in: components),
            handoffSource: queryValue("source", in: components),
            sourcePageTitle: queryValue("sourcePageTitle", in: components),
            sourcePageUrl: queryValue("sourcePageUrl", in: components)
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
            version: queryValue("version", in: components)
        )
    }

    static func isBrowserSetupURL(_ url: URL) -> Bool {
        url.scheme == "swiftgetx" && url.host == "browser-setup"
    }

    private static func queryValue(_ name: String, in components: URLComponents) -> String? {
        components.queryItems?.first(where: { $0.name == name })?.value
    }
}

struct BrowserSetupRequest: Equatable {
    var browser: String
    var extensionID: String
    var version: String?
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var menuBarController: MenuBarController?
    private let chromeNativeHostRegistrar = ChromeNativeHostRegistrar()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.setDelegate(self)
        menuBarController = MenuBarController()
        registerChromeNativeHost()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        registerChromeNativeHost()
    }

    @MainActor
    func attachMenuBar(coordinator: DownloadCoordinator, settings: AppSettings) {
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
}

extension Notification.Name {
    static let showNewTaskSheet = Notification.Name("SwiftGetX.showNewTaskSheet")
    static let focusTaskFromNotification = Notification.Name("SwiftGetX.focusTaskFromNotification")
}
