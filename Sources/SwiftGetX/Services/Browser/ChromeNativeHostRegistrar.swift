import Foundation

struct ChromeNativeHostRegistrar {
    static let defaultHostName = "com.swiftgetx.native"

    let hostName: String
    let manifestDirectory: URL
    let extensionDiscovery: ChromeExtensionDiscovery
    let nativeHostSearchPaths: [URL]
    let fileManager: FileManager

    var manifestURL: URL {
        manifestDirectory.appendingPathComponent("\(hostName).json")
    }

    init(
        hostName: String = ChromeNativeHostRegistrar.defaultHostName,
        manifestDirectory: URL = ChromeNativeHostRegistrar.defaultManifestDirectory(),
        extensionDiscovery: ChromeExtensionDiscovery = ChromeExtensionDiscovery(),
        nativeHostSearchPaths: [URL]? = nil,
        fileManager: FileManager = .default
    ) {
        self.hostName = hostName
        self.manifestDirectory = manifestDirectory
        self.extensionDiscovery = extensionDiscovery
        self.nativeHostSearchPaths = nativeHostSearchPaths
            ?? ChromeNativeHostRegistrar.defaultNativeHostSearchPaths(fileManager: fileManager)
        self.fileManager = fileManager
    }

    static func defaultManifestDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
    }

    static func defaultNativeHostSearchPaths(fileManager: FileManager = .default) -> [URL] {
        let binaryName = "SwiftGetXNativeHost"
        var paths: [URL] = []

        if let bundlePath = Bundle.main.executableURL?.deletingLastPathComponent() {
            paths.append(bundlePath.appendingPathComponent(binaryName))
        }

        paths.append(URL(fileURLWithPath: "/Applications/SwiftGetX.app/Contents/MacOS/\(binaryName)"))
        paths.append(
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/SwiftGetX.app/Contents/MacOS/\(binaryName)")
        )

        return paths
    }

    func diagnose() -> ChromeNativeHostRegistrationResult {
        guard fileManager.fileExists(atPath: manifestDirectory.path) else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: "Native Host 未安装",
                detailMessage: "缺少 Chrome Native Messaging 配置目录",
                isRepairable: true
            )
        }

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: "Native Host 未安装",
                detailMessage: "缺少 \(hostName).json 配置文件",
                isRepairable: true
            )
        }

        guard let manifest = readManifest() else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: "配置文件损坏",
                detailMessage: "无法解析 \(hostName).json",
                isRepairable: true
            )
        }

        guard fileManager.fileExists(atPath: manifest.path) else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: "可执行文件缺失",
                detailMessage: "路径不存在：\(manifest.path)",
                isRepairable: true
            )
        }

        guard fileManager.isExecutableFile(atPath: manifest.path) else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: "可执行文件权限错误",
                detailMessage: "文件不可执行：\(manifest.path)",
                isRepairable: true
            )
        }

        let origins = manifest.allowed_origins ?? []
        let validOrigins = ChromeNativeMessagingOrigin.sanitizedOrigins(from: origins)
        let hasPlaceholder = origins.contains(where: ChromeNativeMessagingOrigin.isPlaceholder)
        if hasPlaceholder {
            let discoveredIDs = extensionDiscovery.discoverExtensionIDs()
            let detail = discoveredIDs.isEmpty
                ? "allowed_origins 中包含占位符。安装 SwiftGetX Chrome 插件后会自动修复。"
                : "allowed_origins 中包含占位符，可自动写入已发现的 SwiftGetX Chrome 插件 ID。"
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "扩展 ID 待配置",
                detailMessage: detail,
                isRepairable: true
            )
        }

        if validOrigins.isEmpty {
            let discoveredIDs = extensionDiscovery.discoverExtensionIDs()
            let detail = discoveredIDs.isEmpty
                ? "未找到有效的 SwiftGetX Chrome 插件 ID。安装或启用插件后会自动修复。"
                : "未写入有效的 Chrome 扩展来源，可自动写入已发现的 SwiftGetX Chrome 插件 ID。"
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "扩展 ID 待配置",
                detailMessage: detail,
                isRepairable: true
            )
        }

        return ChromeNativeHostRegistrationResult(
            status: .ok,
            statusMessage: "一切正常",
            detailMessage: "Native Host 已安装，已允许 \(validOrigins.count) 个 Chrome 插件来源",
            isRepairable: false
        )
    }

    func register(setupHintExtensionID: String? = nil) -> ChromeNativeHostRegistrationResult {
        if let setupHintExtensionID,
           !ChromeNativeMessagingOrigin.isValidExtensionID(setupHintExtensionID) {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "插件 ID 无效",
                detailMessage: "浏览器传入的 Chrome 插件 ID 不合法，已忽略本次自动配置请求。",
                isRepairable: false
            )
        }

        guard let binaryPath = locateNativeHostBinary() else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: "修复失败",
                detailMessage: "找不到 SwiftGetXNativeHost 可执行文件。请确认 App 完整安装。",
                isRepairable: false
            )
        }

        let discoveredIDs = extensionDiscovery.discoverExtensionIDs()
        if let setupHintExtensionID, !discoveredIDs.contains(setupHintExtensionID) {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "未验证插件 ID",
                detailMessage: "Chrome profile 中未找到匹配的 SwiftGetX 插件，已忽略本次自动配置请求。",
                isRepairable: true
            )
        }

        let allowedOrigins = ChromeNativeMessagingOrigin.merge(
            existingOrigins: readManifest()?.allowed_origins ?? [],
            discoveredExtensionIDs: discoveredIDs
        )

        guard !allowedOrigins.isEmpty else {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "未发现插件 ID",
                detailMessage: "找不到已安装的 SwiftGetX Chrome 插件。安装或启用插件后会自动修复。",
                isRepairable: true
            )
        }

        do {
            try fileManager.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
            try writeManifest(
                ManifestContent(
                    name: hostName,
                    description: "SwiftGetX Native Messaging host",
                    path: binaryPath,
                    type: "stdio",
                    allowed_origins: allowedOrigins
                )
            )
        } catch {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: "修复失败",
                detailMessage: "无法写入配置文件：\(error.localizedDescription)",
                isRepairable: false
            )
        }

        let verifyResult = diagnose()
        guard verifyResult.status == .ok else {
            return verifyResult
        }

        return ChromeNativeHostRegistrationResult(
            status: .ok,
            statusMessage: "配置完成",
            detailMessage: "Native Host 已自动配置，并写入 \(allowedOrigins.count) 个 Chrome 插件来源",
            isRepairable: false
        )
    }

    func readManifest() -> ManifestContent? {
        guard let data = fileManager.contents(atPath: manifestURL.path) else { return nil }
        return try? JSONDecoder().decode(ManifestContent.self, from: data)
    }

    private func writeManifest(_ manifest: ManifestContent) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func locateNativeHostBinary() -> String? {
        nativeHostSearchPaths
            .map(\.path)
            .first(where: fileManager.isExecutableFile)
    }

    struct ManifestContent: Codable, Equatable {
        var name: String
        var description: String?
        var path: String
        var type: String
        var allowed_origins: [String]?
    }
}

struct ChromeNativeHostRegistrationResult: Equatable {
    var status: ChromeNativeHostRegistrationStatus
    var statusMessage: String
    var detailMessage: String
    var isRepairable: Bool
}

enum ChromeNativeHostRegistrationStatus: Equatable {
    case ok
    case warning
    case error
}
