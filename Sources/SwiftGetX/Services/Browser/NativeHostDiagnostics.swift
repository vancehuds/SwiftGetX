import AppKit
import Foundation

@MainActor
@Observable
final class NativeHostDiagnostics {
    private(set) var status: DiagnosticStatus = .unchecked
    private(set) var statusMessage: String = "未检查"
    private(set) var detailMessage: String = ""
    private(set) var isRepairable: Bool = false
    private(set) var isChecking: Bool = false

    private let hostName = "com.swiftgetx.native"
    private let extensionDiscovery = ChromeExtensionDiscovery()

    private var manifestDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
    }

    private var manifestURL: URL {
        manifestDirectory.appendingPathComponent("\(hostName).json")
    }

    enum DiagnosticStatus: Equatable {
        case unchecked
        case checking
        case ok
        case warning
        case error
    }

    struct ManifestContent: Codable {
        var name: String
        var description: String?
        var path: String
        var type: String
        var allowed_origins: [String]?
    }

    // MARK: - Diagnose

    func check() {
        isChecking = true
        status = .checking
        statusMessage = "检查中…"
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
    }

    private func runDiagnostics() -> DiagnosticResult {
        // 1. Check if Chrome NativeMessagingHosts directory exists
        let fm = FileManager.default
        guard fm.fileExists(atPath: manifestDirectory.path) else {
            return DiagnosticResult(
                status: .error,
                statusMessage: "Chrome 未安装",
                detailMessage: "未找到 Chrome Native Messaging 目录",
                isRepairable: true
            )
        }

        // 2. Check if manifest file exists
        guard fm.fileExists(atPath: manifestURL.path) else {
            return DiagnosticResult(
                status: .error,
                statusMessage: "Native Host 未安装",
                detailMessage: "缺少 \(hostName).json 配置文件",
                isRepairable: true
            )
        }

        // 3. Read and parse manifest
        guard let data = fm.contents(atPath: manifestURL.path),
              let manifest = try? JSONDecoder().decode(ManifestContent.self, from: data) else {
            return DiagnosticResult(
                status: .error,
                statusMessage: "配置文件损坏",
                detailMessage: "无法解析 \(hostName).json",
                isRepairable: true
            )
        }

        // 4. Check binary path
        let binaryPath = manifest.path
        guard fm.fileExists(atPath: binaryPath) else {
            return DiagnosticResult(
                status: .error,
                statusMessage: "可执行文件缺失",
                detailMessage: "路径不存在：\(binaryPath)",
                isRepairable: true
            )
        }

        guard fm.isExecutableFile(atPath: binaryPath) else {
            return DiagnosticResult(
                status: .error,
                statusMessage: "可执行文件权限错误",
                detailMessage: "文件不可执行：\(binaryPath)",
                isRepairable: true
            )
        }

        // 5. Check allowed_origins
        let origins = manifest.allowed_origins ?? []
        let validOrigins = ChromeNativeMessagingOrigin.sanitizedOrigins(from: origins)
        let hasPlaceholder = origins.contains(where: ChromeNativeMessagingOrigin.isPlaceholder)
        if hasPlaceholder {
            let discoveredIDs = extensionDiscovery.discoverExtensionIDs()
            let detail = discoveredIDs.isEmpty
                ? "allowed_origins 中包含占位符。请先安装或启用 SwiftGetX Chrome 插件，然后点“尝试修复”。"
                : "allowed_origins 中包含占位符，可自动写入已发现的 SwiftGetX Chrome 插件 ID。"
            return DiagnosticResult(
                status: .warning,
                statusMessage: "扩展 ID 待配置",
                detailMessage: detail,
                isRepairable: true
            )
        }

        if validOrigins.isEmpty {
            let discoveredIDs = extensionDiscovery.discoverExtensionIDs()
            let detail = discoveredIDs.isEmpty
                ? "未找到有效的 SwiftGetX Chrome 插件 ID。请先安装或启用插件，然后点“尝试修复”。"
                : "未写入有效的 Chrome 扩展来源，可自动写入已发现的 SwiftGetX Chrome 插件 ID。"
            return DiagnosticResult(
                status: .warning,
                statusMessage: "扩展 ID 待配置",
                detailMessage: detail,
                isRepairable: true
            )
        }

        // All checks passed
        return DiagnosticResult(
            status: .ok,
            statusMessage: "一切正常",
            detailMessage: "Native Host 已安装，已允许 \(validOrigins.count) 个 Chrome 插件来源",
            isRepairable: false
        )
    }

    // MARK: - Repair

    func repair() {
        isChecking = true
        status = .checking
        statusMessage = "修复中…"
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
        let fm = FileManager.default

        // Locate the native host binary. Try these locations in order:
        // 1. Inside the running app bundle: .app/Contents/MacOS/SwiftGetXNativeHost
        // 2. /Applications/SwiftGetX.app/Contents/MacOS/SwiftGetXNativeHost
        let bundleBinaryPath = locateNativeHostBinary()

        guard let binaryPath = bundleBinaryPath else {
            return DiagnosticResult(
                status: .error,
                statusMessage: "修复失败",
                detailMessage: "找不到 SwiftGetXNativeHost 可执行文件。请确认 App 完整安装。",
                isRepairable: false
            )
        }

        // Create NativeMessagingHosts directory if needed
        do {
            try fm.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        } catch {
            return DiagnosticResult(
                status: .error,
                statusMessage: "修复失败",
                detailMessage: "无法创建目录：\(error.localizedDescription)",
                isRepairable: false
            )
        }

        // Read existing allowed_origins if manifest already exists (preserve extension ID)
        var existingOrigins: [String] = []
        if let existingData = fm.contents(atPath: manifestURL.path),
           let existingManifest = try? JSONDecoder().decode(ManifestContent.self, from: existingData),
           let origins = existingManifest.allowed_origins, !origins.isEmpty {
            existingOrigins = origins
        }

        let discoveredIDs = extensionDiscovery.discoverExtensionIDs()
        let allowedOrigins = ChromeNativeMessagingOrigin.merge(
            existingOrigins: existingOrigins,
            discoveredExtensionIDs: discoveredIDs
        )

        guard !allowedOrigins.isEmpty else {
            return DiagnosticResult(
                status: .warning,
                statusMessage: "未发现插件 ID",
                detailMessage: "找不到已安装的 SwiftGetX Chrome 插件。请先在 Chrome 中安装或启用插件，然后再次尝试修复。",
                isRepairable: true
            )
        }

        // Write manifest
        let manifest = ManifestContent(
            name: hostName,
            description: "SwiftGetX Native Messaging host",
            path: binaryPath,
            type: "stdio",
            allowed_origins: allowedOrigins
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            return DiagnosticResult(
                status: .error,
                statusMessage: "修复失败",
                detailMessage: "无法写入配置文件：\(error.localizedDescription)",
                isRepairable: false
            )
        }

        // Verify the fix
        let verifyResult = runDiagnostics()

        if verifyResult.status == .ok {
            return DiagnosticResult(
                status: .ok,
                statusMessage: "修复成功",
                detailMessage: "Native Host 已重新安装，并写入 \(allowedOrigins.count) 个 Chrome 插件来源",
                isRepairable: false
            )
        }

        if verifyResult.status == .warning {
            return DiagnosticResult(
                status: .warning,
                statusMessage: "部分修复",
                detailMessage: "配置文件已写入，但\(verifyResult.detailMessage)",
                isRepairable: false
            )
        }

        return verifyResult
    }

    private func locateNativeHostBinary() -> String? {
        let fm = FileManager.default
        let binaryName = "SwiftGetXNativeHost"

        // 1. In the currently running app bundle
        if let bundlePath = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent(binaryName).path,
           fm.isExecutableFile(atPath: bundlePath) {
            return bundlePath
        }

        // 2. In /Applications/SwiftGetX.app
        let applicationsPath = "/Applications/SwiftGetX.app/Contents/MacOS/\(binaryName)"
        if fm.isExecutableFile(atPath: applicationsPath) {
            return applicationsPath
        }

        // 3. In ~/Applications/SwiftGetX.app
        let userApplicationsPath = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/SwiftGetX.app/Contents/MacOS/\(binaryName)").path
        if fm.isExecutableFile(atPath: userApplicationsPath) {
            return userApplicationsPath
        }

        return nil
    }

    // MARK: - Open manifest in Finder

    func revealManifest() {
        let fm = FileManager.default
        if fm.fileExists(atPath: manifestURL.path) {
            NSWorkspace.shared.selectFile(manifestURL.path, inFileViewerRootedAtPath: manifestDirectory.path)
        } else if fm.fileExists(atPath: manifestDirectory.path) {
            NSWorkspace.shared.open(manifestDirectory)
        }
    }
}
