import Foundation

enum DiagnosticLogLevel: String, Codable, CaseIterable, Identifiable {
    case normal
    case verbose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal:
            L10n.string("diagnostic_log_level_normal")
        case .verbose:
            L10n.string("diagnostic_log_level_verbose")
        }
    }

    var includesDebugEntries: Bool {
        self == .verbose
    }
}
