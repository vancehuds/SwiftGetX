import Foundation
import Observation
import SwiftGetXCore

@MainActor
@Observable
final class BrowserBridge {
    private weak var coordinator: DownloadCoordinator?
    private(set) var lastMessage: String = "浏览器接管待连接"

    func attach(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator
    }

    func handleNativeMessage(_ message: BrowserDownloadMessage) {
        guard message.action == "download" else {
            lastMessage = "忽略未知浏览器消息：\(message.action)"
            return
        }

        coordinator?.add(source: message.url)
        lastMessage = "已从 \(message.browser) 接收下载任务"
    }
}
