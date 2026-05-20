import Foundation

struct ChromeNativeHostRegistrar {
    static let defaultHostName = "com.swiftgetx.native"

    let hostName: String
    let manifestDirectory: URL
    let usesDefaultManifestDirectory: Bool
    let extensionDiscovery: ChromeExtensionDiscovery
    let pairingStore: ChromeNativeHostPairingStore
    let nativeHostSearchPaths: [URL]
    let fileManager: FileManager

    var manifestURL: URL {
        manifestDirectory.appendingPathComponent("\(hostName).json")
    }

    init(
        hostName: String = ChromeNativeHostRegistrar.defaultHostName,
        manifestDirectory: URL = ChromeNativeHostRegistrar.defaultManifestDirectory(),
        extensionDiscovery: ChromeExtensionDiscovery = ChromeExtensionDiscovery(),
        pairingStore: ChromeNativeHostPairingStore = ChromeNativeHostPairingStore(),
        nativeHostSearchPaths: [URL]? = nil,
        fileManager: FileManager = .default
    ) {
        self.hostName = hostName
        self.manifestDirectory = manifestDirectory
        usesDefaultManifestDirectory = manifestDirectory.standardizedFileURL
            == ChromeNativeHostRegistrar.defaultManifestDirectory().standardizedFileURL
        self.extensionDiscovery = extensionDiscovery
        self.pairingStore = pairingStore
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
        let pairedExtensionIDs = pairingStore.pairedExtensionIDs()
        guard !pairedExtensionIDs.isEmpty else {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "Chrome 插件未配对",
                detailMessage: "请从 SwiftGetX Chrome 插件发起连接检查，并在 SwiftGetX 中手动允许配对。",
                isRepairable: false
            )
        }

        let manifestTargets = registrationManifestTargets(for: pairedExtensionIDs)
        guard !manifestTargets.isEmpty else {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "需要重新配对",
                detailMessage: "没有在已支持的 Chromium 浏览器配置中找到已配对的 SwiftGetX 插件。",
                isRepairable: false
            )
        }

        let diagnoses = manifestTargets.map { diagnose(target: $0) }
        if let blockingDiagnosis = diagnoses.first(where: { $0.status != .ok }) {
            return blockingDiagnosis
        }

        let okCount = diagnoses.count
        return ChromeNativeHostRegistrationResult(
            status: .ok,
            statusMessage: "一切正常",
            detailMessage: "Native Host 已安装，已配置 \(okCount) 个浏览器配置",
            isRepairable: false
        )
    }

    private func diagnose(target: NativeHostManifestTarget) -> ChromeNativeHostRegistrationResult {
        guard fileManager.fileExists(atPath: target.manifestDirectory.path) else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: "Native Host 未安装",
                detailMessage: "缺少 \(target.browserConfiguration.name) Native Messaging 配置目录",
                isRepairable: true
            )
        }

        let manifestURL = target.manifestURL(hostName: hostName)

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: "Native Host 未安装",
                detailMessage: "缺少 \(hostName).json 配置文件",
                isRepairable: true
            )
        }

        guard let manifest = readManifest(at: manifestURL) else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: "配置文件损坏",
                detailMessage: "无法解析 \(hostName).json",
                isRepairable: true
            )
        }

        guard manifest.name == hostName else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: "Host 名称错误",
                detailMessage: "配置文件 name 应为 \(hostName)，当前为 \(manifest.name)。",
                isRepairable: true
            )
        }

        guard manifest.type == "stdio" else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: "Host 类型错误",
                detailMessage: "配置文件 type 应为 stdio，当前为 \(manifest.type)。",
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
        let pairedOrigins = target.extensionIDs.compactMap(ChromeNativeMessagingOrigin.origin)
        let hasPlaceholder = origins.contains(where: ChromeNativeMessagingOrigin.isPlaceholder)
        let hasInvalidOrigins = origins.contains { origin in
            !ChromeNativeMessagingOrigin.isPlaceholder(origin)
                && ChromeNativeMessagingOrigin.extensionID(from: origin) == nil
        }
        if hasPlaceholder {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "扩展来源待清理",
                detailMessage: "allowed_origins 中包含占位符，可自动改写为已配对的 Chrome 插件 ID。",
                isRepairable: true
            )
        }

        if hasInvalidOrigins {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "扩展来源待清理",
                detailMessage: "allowed_origins 中包含无效来源，可自动改写为已配对的 Chrome 插件 ID。",
                isRepairable: true
            )
        }

        if validOrigins.isEmpty {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "扩展来源缺失",
                detailMessage: "未写入已配对的 Chrome 插件来源，可自动补写 allowed_origins。",
                isRepairable: true
            )
        }

        let missingOrigins = pairedOrigins.filter { !validOrigins.contains($0) }
        if !missingOrigins.isEmpty {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "扩展来源缺失",
                detailMessage: "配置文件未允许已配对的 SwiftGetX Chrome 插件，可自动补写 allowed_origins。",
                isRepairable: true
            )
        }

        let unpairedOrigins = validOrigins.filter { !pairedOrigins.contains($0) }
        if !unpairedOrigins.isEmpty {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "发现未配对来源",
                detailMessage: "配置文件允许了未手动配对的 Chrome 插件来源，可自动移除。",
                isRepairable: true
            )
        }

        return ChromeNativeHostRegistrationResult(
            status: .ok,
            statusMessage: "一切正常",
            detailMessage: "\(target.browserConfiguration.name) Native Host 已安装，已允许 \(validOrigins.count) 个插件来源",
            isRepairable: false
        )
    }

    func register() -> ChromeNativeHostRegistrationResult {
        let pairedExtensionIDs = pairingStore.pairedExtensionIDs()
        guard !pairedExtensionIDs.isEmpty else {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "需要手动配对",
                detailMessage: "请先从 SwiftGetX Chrome 插件发起连接检查，并在 SwiftGetX 中允许该插件配对。",
                isRepairable: false
            )
        }

        let manifestTargets = registrationManifestTargets(for: pairedExtensionIDs)
        guard !manifestTargets.isEmpty else {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "需要重新配对",
                detailMessage: "没有在已支持的 Chromium 浏览器配置中找到已配对的 SwiftGetX 插件。",
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

        let results = manifestTargets.map { target in
            writeAndVerifyManifest(binaryPath: binaryPath, target: target)
        }
        if let blockingResult = results.first(where: { $0.status != .ok }) {
            return blockingResult
        }

        let allowedOriginCount = manifestTargets.reduce(0) { partialResult, target in
            partialResult + target.extensionIDs.count
        }
        return ChromeNativeHostRegistrationResult(
            status: .ok,
            statusMessage: "配置完成",
            detailMessage: "Native Host 已自动配置 \(manifestTargets.count) 个浏览器配置，并写入 \(allowedOriginCount) 个插件来源",
            isRepairable: false
        )
    }

    func pairAndRegister(extensionID: String) -> ChromeNativeHostRegistrationResult {
        guard ChromeNativeMessagingOrigin.isValidExtensionID(extensionID) else {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "插件 ID 无效",
                detailMessage: "浏览器传入的 Chrome 插件 ID 不合法，已忽略本次配对请求。",
                isRepairable: false
            )
        }

        if !pairingStore.isPaired(extensionID) {
            let discoveredIDs = extensionDiscovery.discoverExtensionIDs()
            guard discoveredIDs.contains(extensionID) else {
                return ChromeNativeHostRegistrationResult(
                    status: .warning,
                    statusMessage: "未验证插件 ID",
                    detailMessage: "Chrome profile 中未找到匹配的 SwiftGetX 插件，已忽略本次配对请求。",
                    isRepairable: false
                )
            }
            pairingStore.pair(extensionID)
        }

        return register()
    }

    func isPairedExtensionID(_ extensionID: String) -> Bool {
        pairingStore.isPaired(extensionID)
    }

    func canPairExtensionID(_ extensionID: String) -> Bool {
        ChromeNativeMessagingOrigin.isValidExtensionID(extensionID)
            && extensionDiscovery.discoverExtensionIDs().contains(extensionID)
    }

    func readManifest() -> ManifestContent? {
        readManifest(at: manifestURL)
    }

    private func readManifest(at url: URL) -> ManifestContent? {
        guard let data = fileManager.contents(atPath: url.path) else { return nil }
        return try? JSONDecoder().decode(ManifestContent.self, from: data)
    }

    private func writeAndVerifyManifest(
        binaryPath: String,
        target: NativeHostManifestTarget
    ) -> ChromeNativeHostRegistrationResult {
        let allowedOrigins = ChromeNativeMessagingOrigin.merge(
            existingOrigins: [],
            discoveredExtensionIDs: target.extensionIDs
        )

        guard !allowedOrigins.isEmpty else {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: "需要手动配对",
                detailMessage: "没有可写入的已配对 Chrome 插件 ID。",
                isRepairable: false
            )
        }

        do {
            try fileManager.createDirectory(at: target.manifestDirectory, withIntermediateDirectories: true)
            try writeManifest(
                ManifestContent(
                    name: hostName,
                    description: "SwiftGetX Native Messaging host",
                    path: binaryPath,
                    type: "stdio",
                    allowed_origins: allowedOrigins
                ),
                to: target.manifestURL(hostName: hostName)
            )
        } catch {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: "修复失败",
                detailMessage: "无法写入配置文件：\(error.localizedDescription)",
                isRepairable: false
            )
        }

        let verifyResult = diagnose(target: target)
        guard verifyResult.status == .ok else {
            return verifyResult
        }

        return ChromeNativeHostRegistrationResult(
            status: .ok,
            statusMessage: "配置完成",
            detailMessage: "\(target.browserConfiguration.name) Native Host 已自动配置，并写入 \(allowedOrigins.count) 个插件来源",
            isRepairable: false
        )
    }

    private func writeManifest(_ manifest: ManifestContent, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    private func locateNativeHostBinary() -> String? {
        nativeHostSearchPaths
            .map(\.path)
            .first(where: fileManager.isExecutableFile)
    }

    private func registrationManifestTargets(for pairedExtensionIDs: [String]) -> [NativeHostManifestTarget] {
        guard usesDefaultManifestDirectory else {
            return [
                NativeHostManifestTarget(
                    browserConfiguration: ChromiumBrowserConfiguration(
                        name: "Chrome",
                        userDataDirectory: manifestDirectory.deletingLastPathComponent(),
                        nativeMessagingHostDirectory: manifestDirectory
                    ),
                    extensionIDs: pairedExtensionIDs
                )
            ]
        }

        let discoveredByID = Dictionary(
            grouping: extensionDiscovery.discoverExtensionInstallations(),
            by: \.extensionID
        )
        var targetsByPath: [String: NativeHostManifestTarget] = [:]

        for extensionID in pairedExtensionIDs {
            guard let installations = discoveredByID[extensionID] else { continue }
            for installation in installations {
                let configuration = installation.browserConfiguration
                let key = configuration.nativeMessagingHostDirectory.path
                var target = targetsByPath[key] ?? NativeHostManifestTarget(
                    browserConfiguration: configuration,
                    extensionIDs: []
                )
                if !target.extensionIDs.contains(extensionID) {
                    target.extensionIDs.append(extensionID)
                }
                targetsByPath[key] = target
            }
        }

        return targetsByPath.values.sorted { lhs, rhs in
            lhs.browserConfiguration.nativeMessagingHostDirectory.path
                < rhs.browserConfiguration.nativeMessagingHostDirectory.path
        }
    }

    private struct NativeHostManifestTarget {
        var browserConfiguration: ChromiumBrowserConfiguration
        var extensionIDs: [String]

        var manifestDirectory: URL {
            browserConfiguration.nativeMessagingHostDirectory
        }

        func manifestURL(hostName: String) -> URL {
            manifestDirectory.appendingPathComponent("\(hostName).json")
        }
    }

    struct ManifestContent: Codable, Equatable {
        var name: String
        var description: String?
        var path: String
        var type: String
        var allowed_origins: [String]?
    }
}

final class ChromeNativeHostPairingStore {
    static let defaultKey = "ChromeNativeHostPairedExtensionIDs"

    private let defaults: UserDefaults?
    private let key: String
    private var inMemoryExtensionIDs: [String]?

    init(
        defaults: UserDefaults = .standard,
        key: String = ChromeNativeHostPairingStore.defaultKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    init(pairedExtensionIDs: [String]) {
        defaults = nil
        key = ChromeNativeHostPairingStore.defaultKey
        inMemoryExtensionIDs = ChromeNativeHostPairingStore.sanitizedExtensionIDs(pairedExtensionIDs)
    }

    func pairedExtensionIDs() -> [String] {
        ChromeNativeHostPairingStore.sanitizedExtensionIDs(
            defaults?.stringArray(forKey: key) ?? inMemoryExtensionIDs ?? []
        )
    }

    func isPaired(_ extensionID: String) -> Bool {
        pairedExtensionIDs().contains(extensionID)
    }

    func pair(_ extensionID: String) {
        guard ChromeNativeMessagingOrigin.isValidExtensionID(extensionID) else { return }

        var extensionIDs = pairedExtensionIDs()
        guard !extensionIDs.contains(extensionID) else { return }

        extensionIDs.append(extensionID)
        save(extensionIDs)
    }

    private func save(_ extensionIDs: [String]) {
        let sanitizedExtensionIDs = ChromeNativeHostPairingStore.sanitizedExtensionIDs(extensionIDs)
        if let defaults {
            defaults.set(sanitizedExtensionIDs, forKey: key)
        } else {
            inMemoryExtensionIDs = sanitizedExtensionIDs
        }
    }

    private static func sanitizedExtensionIDs(_ extensionIDs: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        for extensionID in extensionIDs {
            guard ChromeNativeMessagingOrigin.isValidExtensionID(extensionID),
                  !seen.contains(extensionID) else {
                continue
            }
            seen.insert(extensionID)
            result.append(extensionID)
        }

        return result
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
