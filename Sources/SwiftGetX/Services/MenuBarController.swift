import AppKit

@MainActor
final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init() {
        statusItem.button?.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "SwiftGetX")
        statusItem.button?.imagePosition = .imageLeading
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(
            withTitle: "新建下载任务",
            action: #selector(showNewTask),
            keyEquivalent: "n"
        ).target = self

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: "暂停全部",
            action: #selector(pauseAll),
            keyEquivalent: ""
        ).target = self

        menu.addItem(
            withTitle: "恢复全部",
            action: #selector(resumeAll),
            keyEquivalent: ""
        ).target = self

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            withTitle: "打开 SwiftGetX",
            action: #selector(openApp),
            keyEquivalent: ""
        ).target = self

        return menu
    }

    @objc private func showNewTask() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .showNewTaskSheet, object: nil)
    }

    @objc private func pauseAll() {
        NotificationCenter.default.post(name: .pauseAllDownloads, object: nil)
    }

    @objc private func resumeAll() {
        NotificationCenter.default.post(name: .resumeAllDownloads, object: nil)
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    static let pauseAllDownloads = Notification.Name("SwiftGetX.pauseAllDownloads")
    static let resumeAllDownloads = Notification.Name("SwiftGetX.resumeAllDownloads")
}
