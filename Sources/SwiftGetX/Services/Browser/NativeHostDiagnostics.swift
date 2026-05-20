import AppKit
import Foundation

@MainActor
@Observable
final class NativeHostDiagnostics {
    private(set) var status: DiagnosticStatus = .unchecked
    private(set) var statusMessage: String = L10n.string("diagnostics_unchecked")
    private(set) var detailMessage: String = ""
    private(set) var isRepairable: Bool = false
    private(set) var isChecking: Bool = false
    private(set) var browserDiagnostics: [ChromeNativeHostBrowserDiagnostic] = []

    private let registrar: ChromeNativeHostRegistrar

    init(registrar: ChromeNativeHostRegistrar = ChromeNativeHostRegistrar()) {
        self.registrar = registrar
    }

    enum DiagnosticStatus: Equatable {
        case unchecked
        case checking
        case ok
        case warning
        case error
    }

    var supportedBrowserCount: Int {
        browserDiagnostics.count
    }

    var detectedBrowserCount: Int {
        browserDiagnostics.filter(\.hasBrowserProfile).count
    }

    var configuredBrowserCount: Int {
        browserDiagnostics.filter(\.isConfigured).count
    }

    var discoveredExtensionCount: Int {
        Set(browserDiagnostics.flatMap(\.discoveredExtensionIDs)).count
    }

    var pairedExtensionCount: Int {
        Set(browserDiagnostics.flatMap(\.pairedExtensionIDs)).count
    }

    var sidebarStatusMessage: String {
        switch status {
        case .unchecked:
            L10n.string("diagnostics_unchecked")
        case .checking:
            L10n.string("diagnostics_checking")
        case .ok:
            configuredBrowserCount > 0
                ? L10n.string(
                    "browser_diagnostics_configured_summary",
                    configuredBrowserCount,
                    supportedBrowserCount
                )
                : statusMessage
        case .warning, .error:
            configuredBrowserCount > 0
                ? L10n.string(
                    "browser_diagnostics_configured_with_warning",
                    configuredBrowserCount,
                    supportedBrowserCount
                )
                : statusMessage
        }
    }

    // MARK: - Diagnose

    func check() {
        isChecking = true
        status = .checking
        statusMessage = L10n.string("diagnostics_checking")
        detailMessage = ""
        isRepairable = false

        let result = runDiagnostics()

        apply(result)
        isChecking = false
    }

    private struct DiagnosticResult {
        var status: DiagnosticStatus
        var statusMessage: String
        var detailMessage: String
        var isRepairable: Bool
        var browserDiagnostics: [ChromeNativeHostBrowserDiagnostic]

        init(
            status: DiagnosticStatus,
            statusMessage: String,
            detailMessage: String,
            isRepairable: Bool,
            browserDiagnostics: [ChromeNativeHostBrowserDiagnostic]
        ) {
            self.status = status
            self.statusMessage = statusMessage
            self.detailMessage = detailMessage
            self.isRepairable = isRepairable
            self.browserDiagnostics = browserDiagnostics
        }

        init(
            _ result: ChromeNativeHostRegistrationResult,
            browserDiagnostics: [ChromeNativeHostBrowserDiagnostic]
        ) {
            status = switch result.status {
            case .ok:
                .ok
            case .warning:
                .warning
            case .error:
                .error
            }
            statusMessage = result.statusMessage
            detailMessage = result.detailMessage
            isRepairable = result.isRepairable
            self.browserDiagnostics = browserDiagnostics
        }
    }

    private func runDiagnostics() -> DiagnosticResult {
        DiagnosticResult(
            registrar.diagnose(),
            browserDiagnostics: registrar.browserDiagnostics()
        )
    }

    private func apply(_ result: DiagnosticResult) {
        status = result.status
        statusMessage = result.statusMessage
        detailMessage = result.detailMessage
        isRepairable = result.isRepairable
        browserDiagnostics = result.browserDiagnostics
    }

    // MARK: - Repair

    func repair() {
        isChecking = true
        status = .checking
        statusMessage = L10n.string("diagnostics_repairing")
        detailMessage = ""
        isRepairable = false

        let repairResult = performRepair()

        apply(repairResult)
        isChecking = false
    }

    private func performRepair() -> DiagnosticResult {
        DiagnosticResult(
            registrar.register(),
            browserDiagnostics: registrar.browserDiagnostics()
        )
    }

    // MARK: - Open manifest in Finder

    func revealManifest() {
        let fm = FileManager.default
        let revealURL = preferredRevealURL()
        if fm.fileExists(atPath: revealURL.manifest.path) {
            NSWorkspace.shared.selectFile(
                revealURL.manifest.path,
                inFileViewerRootedAtPath: revealURL.directory.path
            )
        } else if fm.fileExists(atPath: revealURL.directory.path) {
            NSWorkspace.shared.open(revealURL.directory)
        }
    }

    private func preferredRevealURL() -> (manifest: URL, directory: URL) {
        if let problematic = browserDiagnostics.first(where: { $0.isRepairable || $0.status != .ok }) {
            return (problematic.manifestURL, problematic.manifestDirectory)
        }

        if let configured = browserDiagnostics.first(where: \.isConfigured) {
            return (configured.manifestURL, configured.manifestDirectory)
        }

        if let first = browserDiagnostics.first {
            return (first.manifestURL, first.manifestDirectory)
        }

        return (registrar.manifestURL, registrar.manifestDirectory)
    }
}
