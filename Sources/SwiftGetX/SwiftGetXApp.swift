import AppKit
import SwiftData
import SwiftUI
import SwiftGetXCore
import UserNotifications

@main
struct SwiftGetXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
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
        WindowGroup {
            ContentView()
                .environment(coordinator)
                .environment(browserBridge)
                .environment(clipboardMonitor)
                .environment(appSettings)
                .modelContainer(modelContainer)
                .task {
                    loadSettings()
                    coordinator.attach(modelContext: modelContainer.mainContext, settings: appSettings)
                    browserBridge.attach(coordinator: coordinator)
                    clipboardMonitor.attach(coordinator: coordinator, settings: appSettings)
                    coordinator.restoreIncompleteTasks()
                }
                .onOpenURL { url in
                    if let source = DeepLinkParser.downloadSource(from: url) {
                        coordinator.add(source: source)
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
                .frame(width: 520, height: 480)
        }
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
}

enum DeepLinkParser {
    static func downloadSource(from url: URL) -> String? {
        guard url.scheme == "swiftgetx", url.host == "download",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        return components.queryItems?.first(where: { $0.name == "url" })?.value
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        menuBarController = MenuBarController()
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
}

extension Notification.Name {
    static let showNewTaskSheet = Notification.Name("SwiftGetX.showNewTaskSheet")
    static let focusTaskFromNotification = Notification.Name("SwiftGetX.focusTaskFromNotification")
}
