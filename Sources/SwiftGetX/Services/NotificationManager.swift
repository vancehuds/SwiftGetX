import Foundation
import UserNotifications

enum NotificationManager {
    static var canUseUserNotifications: Bool {
        canUseUserNotifications(bundleURL: Bundle.main.bundleURL)
    }

    static func canUseUserNotifications(bundleURL: URL) -> Bool {
        bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    static func requestAuthorization() {
        guard canUseUserNotifications else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
        guard canUseUserNotifications else { return }
        UNUserNotificationCenter.current().delegate = delegate
    }

    static func notifyCompletion(for task: DownloadTask) {
        guard canUseUserNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.string("notification_download_complete")
        content.body = task.name
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: task.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func notifySeedingStopped(for task: DownloadTask) {
        guard canUseUserNotifications else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.string("notification_seeding_stopped")
        content.body = task.name
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(task.id.uuidString)-seeding-stopped",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
