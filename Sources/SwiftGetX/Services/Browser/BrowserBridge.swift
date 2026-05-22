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

        let context = BrowserDownloadContext.context(from: message)
        let draft = DownloadDraft(
            source: url,
            suggestedFilename: message.suggestedFilename,
            browser: message.browser,
            browserContext: context,
            linkTrust: .publicLink,
            sourceCount: SourceParser.extractSources(from: url).count
        )
        if draft.containsTorrentSource {
            NotificationCenter.default.post(name: .showNewTaskSheet, object: draft)
        } else {
            coordinator?.add(
                source: url,
                suggestedFilename: message.suggestedFilename,
                browserContext: context
            )
        }
        lastMessage = L10n.string(
            "browser_bridge_received_task",
            message.browser ?? L10n.string("browser_generic")
        )
    }
}
