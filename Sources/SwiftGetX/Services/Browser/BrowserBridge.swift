import Foundation
import Observation
import SwiftGetXCore

@MainActor
@Observable
final class BrowserBridge {
    private weak var coordinator: DownloadCoordinator?
    private(set) var lastMessage: String = L10n.string("browser_bridge_waiting")

    func attach(coordinator: DownloadCoordinator) {
        self.coordinator = coordinator
    }

    func handleNativeMessage(_ message: BrowserDownloadMessage) {
        guard message.action == "download" else {
            lastMessage = L10n.string("browser_bridge_unknown_message", message.action)
            return
        }

        guard let url = message.url, !url.isEmpty else {
            lastMessage = L10n.string("browser_bridge_missing_url")
            return
        }

        coordinator?.add(
            source: url,
            suggestedFilename: message.suggestedFilename,
            browserContext: BrowserDownloadContext.context(from: message)
        )
        lastMessage = L10n.string(
            "browser_bridge_received_task",
            message.browser ?? L10n.string("browser_generic")
        )
    }
}
