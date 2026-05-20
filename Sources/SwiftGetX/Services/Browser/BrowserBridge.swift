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

        guard let url = message.url, !url.isEmpty else {
            lastMessage = "浏览器消息缺少下载地址"
            return
        }

        coordinator?.add(source: url)
        lastMessage = "已从 \(message.browser ?? "浏览器") 接收下载任务"
    }
}
