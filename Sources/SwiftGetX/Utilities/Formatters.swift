import Foundation

extension ByteCountFormatter {
    @MainActor
    static let downloadFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter
    }()
}

enum TimeFormatter {
    static func eta(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return "\(hours)时 \(minutes)分"
        }
        if minutes > 0 {
            return "\(minutes)分 \(seconds)秒"
        }
        return "\(seconds)秒"
    }
}

enum AppDefaults {
    static var downloadDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }
}

extension FileManager {
    func uniqueFileURL(for proposedURL: URL) -> URL {
        guard fileExists(atPath: proposedURL.path) else { return proposedURL }

        let directory = proposedURL.deletingLastPathComponent()
        let baseName = proposedURL.deletingPathExtension().lastPathComponent
        let pathExtension = proposedURL.pathExtension

        var index = 2
        while true {
            let filename = pathExtension.isEmpty
                ? "\(baseName) \(index)"
                : "\(baseName) \(index).\(pathExtension)"
            let candidate = directory.appendingPathComponent(filename)
            if !fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
