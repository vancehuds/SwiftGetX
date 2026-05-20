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

    // MARK: - Diagnose

    func check() {
        isChecking = true
        status = .checking
        statusMessage = L10n.string("diagnostics_checking")
        detailMessage = ""
        isRepairable = false

        let result = runDiagnostics()

        status = result.status
        statusMessage = result.statusMessage
        detailMessage = result.detailMessage
        isRepairable = result.isRepairable
        isChecking = false
    }

    private struct DiagnosticResult {
        var status: DiagnosticStatus
        var statusMessage: String
        var detailMessage: String
        var isRepairable: Bool

        init(
            status: DiagnosticStatus,
            statusMessage: String,
            detailMessage: String,
            isRepairable: Bool
        ) {
            self.status = status
            self.statusMessage = statusMessage
            self.detailMessage = detailMessage
            self.isRepairable = isRepairable
        }

        init(_ result: ChromeNativeHostRegistrationResult) {
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
        }
    }

    private func runDiagnostics() -> DiagnosticResult {
        DiagnosticResult(registrar.diagnose())
    }

    // MARK: - Repair

    func repair() {
        isChecking = true
        status = .checking
        statusMessage = L10n.string("diagnostics_repairing")
        detailMessage = ""
        isRepairable = false

        let repairResult = performRepair()

        status = repairResult.status
        statusMessage = repairResult.statusMessage
        detailMessage = repairResult.detailMessage
        isRepairable = repairResult.isRepairable
        isChecking = false
    }

    private func performRepair() -> DiagnosticResult {
        DiagnosticResult(registrar.register())
    }

    // MARK: - Open manifest in Finder

    func revealManifest() {
        let fm = FileManager.default
        if fm.fileExists(atPath: registrar.manifestURL.path) {
            NSWorkspace.shared.selectFile(
                registrar.manifestURL.path,
                inFileViewerRootedAtPath: registrar.manifestDirectory.path
            )
        } else if fm.fileExists(atPath: registrar.manifestDirectory.path) {
            NSWorkspace.shared.open(registrar.manifestDirectory)
        }
    }
}
