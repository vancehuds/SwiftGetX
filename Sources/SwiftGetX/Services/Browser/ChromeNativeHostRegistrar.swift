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
                statusMessage: L10n.string("native_host_chrome_extension_unpaired"),
                detailMessage: L10n.string("native_host_pair_from_extension_detail"),
                isRepairable: false
            )
        }

        let manifestTargets = registrationManifestTargets(for: pairedExtensionIDs)
        guard !manifestTargets.isEmpty else {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: L10n.string("native_host_repairing_required"),
                detailMessage: L10n.string("native_host_no_supported_profile_detail"),
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
            statusMessage: L10n.string("native_host_all_good"),
            detailMessage: L10n.string("native_host_installed_profile_count", okCount),
            isRepairable: false
        )
    }

    private func diagnose(target: NativeHostManifestTarget) -> ChromeNativeHostRegistrationResult {
        guard fileManager.fileExists(atPath: target.manifestDirectory.path) else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: L10n.string("native_host_not_installed"),
                detailMessage: L10n.string(
                    "native_host_missing_config_directory",
                    target.browserConfiguration.name
                ),
                isRepairable: true
            )
        }

        let manifestURL = target.manifestURL(hostName: hostName)

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: L10n.string("native_host_not_installed"),
                detailMessage: L10n.string("native_host_missing_manifest", hostName),
                isRepairable: true
            )
        }

        guard let manifest = readManifest(at: manifestURL) else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: L10n.string("native_host_manifest_corrupt"),
                detailMessage: L10n.string("native_host_manifest_unreadable", hostName),
                isRepairable: true
            )
        }

        guard manifest.name == hostName else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: L10n.string("native_host_name_wrong"),
                detailMessage: L10n.string("native_host_name_wrong_detail", hostName, manifest.name),
                isRepairable: true
            )
        }

        guard manifest.type == "stdio" else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: L10n.string("native_host_type_wrong"),
                detailMessage: L10n.string("native_host_type_wrong_detail", manifest.type),
                isRepairable: true
            )
        }

        guard fileManager.fileExists(atPath: manifest.path) else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: L10n.string("native_host_executable_missing"),
                detailMessage: L10n.string("native_host_path_missing", manifest.path),
                isRepairable: true
            )
        }

        guard fileManager.isExecutableFile(atPath: manifest.path) else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: L10n.string("native_host_executable_permission_wrong"),
                detailMessage: L10n.string("native_host_file_not_executable", manifest.path),
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
                statusMessage: L10n.string("native_host_origins_need_cleanup"),
                detailMessage: L10n.string("native_host_origins_placeholder_detail"),
                isRepairable: true
            )
        }

        if hasInvalidOrigins {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: L10n.string("native_host_origins_need_cleanup"),
                detailMessage: L10n.string("native_host_origins_invalid_detail"),
                isRepairable: true
            )
        }

        if validOrigins.isEmpty {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: L10n.string("native_host_origins_missing"),
                detailMessage: L10n.string("native_host_origins_empty_detail"),
                isRepairable: true
            )
        }

        let missingOrigins = pairedOrigins.filter { !validOrigins.contains($0) }
        if !missingOrigins.isEmpty {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: L10n.string("native_host_origins_missing"),
                detailMessage: L10n.string("native_host_origins_missing_detail"),
                isRepairable: true
            )
        }

        let unpairedOrigins = validOrigins.filter { !pairedOrigins.contains($0) }
        if !unpairedOrigins.isEmpty {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: L10n.string("native_host_unpaired_origins_found"),
                detailMessage: L10n.string("native_host_unpaired_origins_detail"),
                isRepairable: true
            )
        }

        return ChromeNativeHostRegistrationResult(
            status: .ok,
            statusMessage: L10n.string("native_host_all_good"),
            detailMessage: L10n.string(
                "native_host_browser_installed_origin_count",
                target.browserConfiguration.name,
                validOrigins.count
            ),
            isRepairable: false
        )
    }

    func register() -> ChromeNativeHostRegistrationResult {
        let pairedExtensionIDs = pairingStore.pairedExtensionIDs()
        guard !pairedExtensionIDs.isEmpty else {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: L10n.string("native_host_manual_pairing_required"),
                detailMessage: L10n.string("native_host_pair_from_extension_detail"),
                isRepairable: false
            )
        }

        let manifestTargets = registrationManifestTargets(for: pairedExtensionIDs)
        guard !manifestTargets.isEmpty else {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: L10n.string("native_host_repairing_required"),
                detailMessage: L10n.string("native_host_no_supported_profile_detail"),
                isRepairable: false
            )
        }

        guard let binaryPath = locateNativeHostBinary() else {
            return ChromeNativeHostRegistrationResult(
                status: .error,
                statusMessage: L10n.string("native_host_repair_failed"),
                detailMessage: L10n.string("native_host_binary_missing_detail"),
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
            statusMessage: L10n.string("native_host_configured"),
            detailMessage: L10n.string(
                "native_host_configured_profile_origin_count",
                manifestTargets.count,
                allowedOriginCount
            ),
            isRepairable: false
        )
    }

    func pairAndRegister(extensionID: String) -> ChromeNativeHostRegistrationResult {
        guard ChromeNativeMessagingOrigin.isValidExtensionID(extensionID) else {
            return ChromeNativeHostRegistrationResult(
                status: .warning,
                statusMessage: L10n.string("native_host_extension_id_invalid"),
                detailMessage: L10n.string("native_host_extension_id_invalid_detail"),
                isRepairable: false
            )
        }

        if !pairingStore.isPaired(extensionID) {
            let discoveredIDs = extensionDiscovery.discoverExtensionIDs()
            guard discoveredIDs.contains(extensionID) else {
                return ChromeNativeHostRegistrationResult(
                    status: .warning,
                    statusMessage: L10n.string("native_host_extension_id_unverified"),
                    detailMessage: L10n.string("native_host_extension_id_unverified_detail"),
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
                statusMessage: L10n.string("native_host_manual_pairing_required"),
                detailMessage: L10n.string("native_host_no_paired_ids_detail"),
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
                statusMessage: L10n.string("native_host_repair_failed"),
                detailMessage: L10n.string("native_host_write_failed", error.localizedDescription),
                isRepairable: false
            )
        }

        let verifyResult = diagnose(target: target)
        guard verifyResult.status == .ok else {
            return verifyResult
        }

        return ChromeNativeHostRegistrationResult(
            status: .ok,
            statusMessage: L10n.string("native_host_configured"),
            detailMessage: L10n.string(
                "native_host_browser_configured_origin_count",
                target.browserConfiguration.name,
                allowedOrigins.count
            ),
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
