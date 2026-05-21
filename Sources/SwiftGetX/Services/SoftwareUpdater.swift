import Combine
import SwiftUI
import Sparkle

enum SoftwareUpdateManualCheckStatus: Equatable {
    case ready
    case unavailable
    case requested(Date)
    case updateFound(String)
    case upToDate(Date)
    case failed(String)
}

/// Wraps Sparkle's `SPUStandardUpdaterController` for SwiftUI, publishing
/// updater state so menus and settings can reactively enable/disable controls.
@MainActor
final class SoftwareUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var updaterController: SPUStandardUpdaterController!

    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false
    @Published var automaticallyDownloadsUpdates = false
    @Published var allowsAutomaticUpdates = false
    @Published var lastUpdateCheckDate: Date?
    @Published var feedURL: URL?
    @Published private(set) var manualCheckStatus: SoftwareUpdateManualCheckStatus = .ready

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
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
        guard canCheckForUpdates else {
            manualCheckStatus = .unavailable
            refreshState()
            return
        }

        manualCheckStatus = .requested(Date())
        updaterController.updater.checkForUpdates()
        refreshState()
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

    var manualCheckStatusText: String {
        switch manualCheckStatus {
        case .ready:
            return L10n.string("updates_manual_check_ready")
        case .unavailable:
            return L10n.string("updates_manual_check_disabled")
        case .requested(let date):
            return L10n.string(
                "updates_manual_check_requested",
                DateFormatter.updateCheckFormatter.string(from: date)
            )
        case .updateFound(let version):
            return L10n.string("updates_manual_check_found", version)
        case .upToDate(let date):
            return L10n.string(
                "updates_manual_check_up_to_date",
                DateFormatter.updateCheckFormatter.string(from: date)
            )
        case .failed(let message):
            return L10n.string(
                "updates_manual_check_failed",
                PrivacyRedactor.redactedText(message)
            )
        }
    }

    private func refreshState() {
        let updater = updaterController.updater
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        feedURL = updater.feedURL

        switch manualCheckStatus {
        case .requested, .updateFound, .upToDate, .failed:
            return
        case .ready, .unavailable:
            manualCheckStatus = canCheckForUpdates ? .ready : .unavailable
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let displayVersion = item.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = displayVersion.isEmpty ? item.versionString : displayVersion
        manualCheckStatus = .updateFound(version)
        refreshState()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        manualCheckStatus = .upToDate(Date())
        refreshState()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        manualCheckStatus = .failed(error.localizedDescription)
        refreshState()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        defer { refreshState() }
        guard updateCheck == .updates else { return }

        if let error {
            switch manualCheckStatus {
            case .updateFound, .upToDate:
                return
            default:
                manualCheckStatus = .failed(error.localizedDescription)
            }
            return
        }

        if case .requested = manualCheckStatus {
            manualCheckStatus = .upToDate(Date())
        }
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
        .help(updater.manualCheckStatusText)
    }
}
