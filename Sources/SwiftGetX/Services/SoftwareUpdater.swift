import Combine
import SwiftUI
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController` for SwiftUI, publishing
/// updater state so menus and settings can reactively enable/disable controls.
@MainActor
final class SoftwareUpdater: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false
    @Published var automaticallyDownloadsUpdates = false
    @Published var allowsAutomaticUpdates = false
    @Published var lastUpdateCheckDate: Date?
    @Published var feedURL: URL?

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)
        updaterController.updater.publisher(for: \.automaticallyDownloadsUpdates)
            .assign(to: &$automaticallyDownloadsUpdates)
        updaterController.updater.publisher(for: \.allowsAutomaticUpdates)
            .assign(to: &$allowsAutomaticUpdates)
        updaterController.updater.publisher(for: \.lastUpdateCheckDate)
            .assign(to: &$lastUpdateCheckDate)
        updaterController.updater.publisher(for: \.feedURL)
            .assign(to: &$feedURL)

        refreshState()
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }

    func setAutomaticUpdateChecksEnabled(_ isEnabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = isEnabled
        refreshState()
    }

    func setAutomaticDownloadsEnabled(_ isEnabled: Bool) {
        updaterController.updater.automaticallyDownloadsUpdates = isEnabled
        refreshState()
    }

    var currentVersion: String {
        let infoDictionary = Bundle.main.infoDictionary ?? [:]
        return infoDictionary["CFBundleShortVersionString"] as? String
            ?? infoDictionary["CFBundleVersion"] as? String
            ?? "0.1.0-dev"
    }

    private func refreshState() {
        let updater = updaterController.updater
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        feedURL = updater.feedURL
    }
}

/// A SwiftUI view that triggers a user-initiated update check.
/// Intended for use inside a `CommandGroup`.
struct CheckForUpdatesView: View {
    @ObservedObject var updater: SoftwareUpdater

    var body: some View {
        Button(L10n.string("command_check_for_updates")) {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
