import Foundation
import UserNotifications

enum NotificationManager {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyCompletion(for task: DownloadTask) {
        let content = UNMutableNotificationContent()
        content.title = "下载完成"
        content.body = task.name
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: task.id.uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
