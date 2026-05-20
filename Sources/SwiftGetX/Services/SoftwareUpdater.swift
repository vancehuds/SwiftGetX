import SwiftUI
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController` for SwiftUI, publishing
/// `canCheckForUpdates` so menu items can reactively enable/disable.
@MainActor
final class SoftwareUpdater: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
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
