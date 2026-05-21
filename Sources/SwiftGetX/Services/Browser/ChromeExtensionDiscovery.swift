import Foundation

struct ChromiumBrowserConfiguration: Equatable {
    var name: String
    var userDataDirectory: URL
    var nativeMessagingHostDirectory: URL

    init(
        name: String,
        userDataDirectory: URL,
        nativeMessagingHostDirectory: URL? = nil
    ) {
        self.name = name
        self.userDataDirectory = userDataDirectory.standardizedFileURL
        self.nativeMessagingHostDirectory = (
            nativeMessagingHostDirectory
                ?? userDataDirectory.appendingPathComponent("NativeMessagingHosts")
        )
        .standardizedFileURL
    }
}

struct ChromeExtensionInstallation: Equatable {
    var extensionID: String
    var browserConfiguration: ChromiumBrowserConfiguration
}

struct ChromeExtensionDiscovery {
    static let defaultExtensionName = "SwiftGetX"
    static let defaultLocalizedExtensionNameToken = "__MSG_appName__"
    static let defaultExtensionDescriptionPrefix = "Send links, pages, media, and detected downloads to SwiftGetX."
    static let defaultChineseExtensionDescriptionPrefix = "发送链接、页面、媒体和检测到的下载到 SwiftGetX。"
    static let defaultLocalizedExtensionDescriptionToken = "__MSG_appDescription__"
    static let defaultExtensionPopupPath = "popup.html"

    let browserConfigurations: [ChromiumBrowserConfiguration]
    let extensionName: String
    let fileManager: FileManager
    let developmentExtensionDirectory: URL?

    init(
        userDataDirectory: URL? = nil,
        browserConfigurations: [ChromiumBrowserConfiguration]? = nil,
        extensionName: String = ChromeExtensionDiscovery.defaultExtensionName,
        developmentExtensionDirectory: URL? = ChromeExtensionDiscovery.defaultDevelopmentExtensionDirectory(),
        fileManager: FileManager = .default
    ) {
        if let browserConfigurations {
            self.browserConfigurations = browserConfigurations
        } else if let userDataDirectory {
            self.browserConfigurations = [
                ChromiumBrowserConfiguration(
                    name: "Chrome",
                    userDataDirectory: userDataDirectory
                )
            ]
        } else {
            self.browserConfigurations = ChromeExtensionDiscovery.defaultBrowserConfigurations()
        }
        self.extensionName = extensionName
        self.developmentExtensionDirectory = developmentExtensionDirectory?.standardizedFileURL
        self.fileManager = fileManager
    }

    static func defaultChromeUserDataDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Google/Chrome")
    }

    static func defaultChromeCanaryUserDataDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Google/Chrome Canary")
    }

    static func defaultChromiumUserDataDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Chromium")
    }

    static func defaultMicrosoftEdgeUserDataDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Microsoft Edge")
    }

    static func defaultBraveUserDataDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser")
    }

    static func defaultVivaldiUserDataDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Vivaldi")
    }

    static func defaultArcUserDataDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Arc/User Data")
    }

    static func defaultAtlasUserDataDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/com.openai.atlas/browser-data/host")
    }

    static func defaultAtlasNativeMessagingHostDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/OpenAI/ChatGPT Atlas/NativeMessagingHosts")
    }

    static func defaultBrowserConfigurations(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [ChromiumBrowserConfiguration] {
        [
            ChromiumBrowserConfiguration(
                name: "Chrome",
                userDataDirectory: defaultChromeUserDataDirectory(homeDirectory: homeDirectory)
            ),
            ChromiumBrowserConfiguration(
                name: "Chrome Canary",
                userDataDirectory: defaultChromeCanaryUserDataDirectory(homeDirectory: homeDirectory)
            ),
            ChromiumBrowserConfiguration(
                name: "Microsoft Edge",
                userDataDirectory: defaultMicrosoftEdgeUserDataDirectory(homeDirectory: homeDirectory)
            ),
            ChromiumBrowserConfiguration(
                name: "Brave",
                userDataDirectory: defaultBraveUserDataDirectory(homeDirectory: homeDirectory)
            ),
            ChromiumBrowserConfiguration(
                name: "Vivaldi",
                userDataDirectory: defaultVivaldiUserDataDirectory(homeDirectory: homeDirectory)
            ),
            ChromiumBrowserConfiguration(
                name: "Arc",
                userDataDirectory: defaultArcUserDataDirectory(homeDirectory: homeDirectory)
            ),
            ChromiumBrowserConfiguration(
                name: "Chromium",
                userDataDirectory: defaultChromiumUserDataDirectory(homeDirectory: homeDirectory)
            ),
            ChromiumBrowserConfiguration(
                name: "Atlas",
                userDataDirectory: defaultAtlasUserDataDirectory(homeDirectory: homeDirectory),
                nativeMessagingHostDirectory: defaultAtlasNativeMessagingHostDirectory(homeDirectory: homeDirectory)
            )
        ]
    }

    static func defaultDevelopmentExtensionDirectory(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "ChromeExtension", withExtension: nil)
            ?? AppResources.url(forResource: "ChromeExtension")
    }

    func discoverExtensionIDs() -> [String] {
        Array(Set(discoverExtensionInstallations().map(\.extensionID))).sorted()
    }

    func discoverExtensionInstallations() -> [ChromeExtensionInstallation] {
        var discoveredInstallations: [ChromeExtensionInstallation] = []
        var seen = Set<String>()

        for browserConfiguration in browserConfigurations {
            for preferenceFile in preferenceFiles(in: browserConfiguration) {
                for installation in discoverExtensionInstallations(
                    in: preferenceFile,
                    browserConfiguration: browserConfiguration
                ) {
                    let key = "\(installation.browserConfiguration.userDataDirectory.path)\u{0}\(installation.extensionID)"
                    guard !seen.contains(key) else { continue }
                    seen.insert(key)
                    discoveredInstallations.append(installation)
                }
            }
        }

        return discoveredInstallations.sorted { lhs, rhs in
            if lhs.extensionID == rhs.extensionID {
                return lhs.browserConfiguration.userDataDirectory.path
                    < rhs.browserConfiguration.userDataDirectory.path
            }
            return lhs.extensionID < rhs.extensionID
        }
    }

    func discoverExtensionIDs(in preferenceFile: URL) -> [String] {
        discoverExtensionInstallations(
            in: preferenceFile,
            browserConfiguration: browserConfiguration(for: preferenceFile)
        )
        .map(\.extensionID)
        .sorted()
    }

    private func discoverExtensionInstallations(
        in preferenceFile: URL,
        browserConfiguration: ChromiumBrowserConfiguration
    ) -> [ChromeExtensionInstallation] {
        guard let data = try? Data(contentsOf: preferenceFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let extensions = root["extensions"] as? [String: Any],
              let settings = extensions["settings"] as? [String: Any] else {
            return []
        }

        let profileDirectory = preferenceFile.deletingLastPathComponent()
        return settings.compactMap { extensionID, rawSettings in
            guard ChromeNativeMessagingOrigin.isValidExtensionID(extensionID),
                  let settings = rawSettings as? [String: Any],
                  isTargetSettings(
                    settings,
                    browserConfiguration: browserConfiguration,
                    profileDirectory: profileDirectory
                  ) else {
                return nil
            }
            return ChromeExtensionInstallation(
                extensionID: extensionID,
                browserConfiguration: browserConfiguration
            )
        }
        .sorted { $0.extensionID < $1.extensionID }
    }

    private func browserConfiguration(for preferenceFile: URL) -> ChromiumBrowserConfiguration {
        let standardizedFile = preferenceFile.standardizedFileURL.path
        return browserConfigurations.first { configuration in
            standardizedFile.hasPrefix(configuration.userDataDirectory.path + "/")
        } ?? ChromiumBrowserConfiguration(
            name: "Chrome",
            userDataDirectory: preferenceFile.deletingLastPathComponent()
        )
    }

    private func preferenceFiles(in browserConfiguration: ChromiumBrowserConfiguration) -> [URL] {
        let filenames = ["Secure Preferences", "Preferences"]
        let userDataDirectory = browserConfiguration.userDataDirectory
        var files = filenames.map { userDataDirectory.appendingPathComponent($0) }

        guard let profileDirectories = try? fileManager.contentsOfDirectory(
            at: userDataDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return existingFiles(from: files)
        }

        for profileDirectory in profileDirectories {
            let values = try? profileDirectory.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            files.append(contentsOf: filenames.map { profileDirectory.appendingPathComponent($0) })
        }

        return existingFiles(from: files)
    }

    private func existingFiles(from urls: [URL]) -> [URL] {
        urls.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func isTargetSettings(
        _ settings: [String: Any],
        browserConfiguration: ChromiumBrowserConfiguration,
        profileDirectory: URL
    ) -> Bool {
        guard let manifest = manifest(
                in: settings,
                browserConfiguration: browserConfiguration,
                profileDirectory: profileDirectory
              ),
              hasNativeMessagingPermission(manifest) else {
            return false
        }

        if isTargetManifest(manifest) {
            return true
        }

        if let path = settings["path"] as? String,
           isDevelopmentExtensionPath(
            path,
            browserConfiguration: browserConfiguration,
            profileDirectory: profileDirectory
           ),
           isSwiftGetXChromeExtensionShape(manifest) {
            return true
        }

        return false
    }

    private func manifest(
        in settings: [String: Any],
        browserConfiguration: ChromiumBrowserConfiguration,
        profileDirectory: URL
    ) -> [String: Any]? {
        if let manifest = settings["manifest"] as? [String: Any] {
            return manifest
        }

        guard let path = settings["path"] as? String,
              let extensionPath = extensionPath(
                for: path,
                browserConfiguration: browserConfiguration,
                profileDirectory: profileDirectory
              ) else {
            return nil
        }

        let manifestURL = extensionPath.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return manifest
    }

    private func isTargetManifest(_ manifest: [String: Any]) -> Bool {
        guard let name = manifest["name"] as? String else {
            return false
        }

        return name.caseInsensitiveCompare(extensionName) == .orderedSame
            || name == Self.defaultLocalizedExtensionNameToken
    }

    private func hasNativeMessagingPermission(_ manifest: [String: Any]) -> Bool {
        permissions(in: manifest).contains("nativeMessaging")
    }

    private func isSwiftGetXChromeExtensionShape(_ manifest: [String: Any]) -> Bool {
        let action = manifest["action"] as? [String: Any]
        let description = manifest["description"] as? String
        return action?["default_popup"] as? String == Self.defaultExtensionPopupPath
            && (
                description == Self.defaultExtensionDescriptionPrefix
                    || description == Self.defaultChineseExtensionDescriptionPrefix
                    || description == Self.defaultLocalizedExtensionDescriptionToken
            )
    }

    private func isDevelopmentExtensionPath(
        _ path: String,
        browserConfiguration: ChromiumBrowserConfiguration,
        profileDirectory: URL
    ) -> Bool {
        guard path.hasPrefix("/") else { return false }

        guard let extensionPath = extensionPath(
            for: path,
            browserConfiguration: browserConfiguration,
            profileDirectory: profileDirectory
        ) else {
            return false
        }

        if let developmentExtensionDirectory,
           extensionPath == developmentExtensionDirectory {
            return true
        }

        return fileManager.fileExists(atPath: extensionPath.appendingPathComponent("manifest.json").path)
    }

    private func extensionPath(
        for path: String,
        browserConfiguration: ChromiumBrowserConfiguration,
        profileDirectory: URL
    ) -> URL? {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }

        let candidates = [
            profileDirectory.appendingPathComponent("Extensions").appendingPathComponent(path),
            browserConfiguration.userDataDirectory.appendingPathComponent("Extensions").appendingPathComponent(path),
            browserConfiguration.userDataDirectory.appendingPathComponent(path)
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.path) }?
            .standardizedFileURL
            ?? candidates.first?.standardizedFileURL
    }

    private func permissions(in manifest: [String: Any]) -> [String] {
        stringArray(from: manifest["permissions"]) + stringArray(from: manifest["optional_permissions"])
    }

    private func stringArray(from value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String } ?? []
    }
}

enum ChromeNativeMessagingOrigin {
    private static let originPrefix = "chrome-extension://"
    private static let placeholderToken = "REPLACE_WITH"

    static func isPlaceholder(_ origin: String) -> Bool {
        origin.localizedCaseInsensitiveContains(placeholderToken)
    }

    static func isValidExtensionID(_ extensionID: String) -> Bool {
        extensionID.count == 32 && extensionID.allSatisfy { character in
            guard let scalar = character.unicodeScalars.first else { return false }
            return scalar.value >= Character("a").unicodeScalars.first!.value
                && scalar.value <= Character("p").unicodeScalars.first!.value
        }
    }

    static func origin(forExtensionID extensionID: String) -> String? {
        guard isValidExtensionID(extensionID) else { return nil }
        return "\(originPrefix)\(extensionID)/"
    }

    static func extensionID(from origin: String) -> String? {
        guard origin.hasPrefix(originPrefix), origin.hasSuffix("/") else { return nil }

        let idStart = origin.index(origin.startIndex, offsetBy: originPrefix.count)
        let idEnd = origin.index(before: origin.endIndex)
        let extensionID = String(origin[idStart..<idEnd])

        guard isValidExtensionID(extensionID) else { return nil }
        return extensionID
    }

    static func sanitizedOrigins(from origins: [String]) -> [String] {
        merge(existingOrigins: origins, discoveredExtensionIDs: [])
    }

    static func merge(existingOrigins: [String], discoveredExtensionIDs: [String]) -> [String] {
        var result: [String] = []
        var seenExtensionIDs = Set<String>()

        func append(extensionID: String) {
            guard let origin = origin(forExtensionID: extensionID),
                  !seenExtensionIDs.contains(extensionID) else {
                return
            }
            seenExtensionIDs.insert(extensionID)
            result.append(origin)
        }

        for origin in existingOrigins {
            guard !isPlaceholder(origin),
                  let extensionID = extensionID(from: origin) else {
                continue
            }
            append(extensionID: extensionID)
        }

        for extensionID in discoveredExtensionIDs {
            append(extensionID: extensionID)
        }

        return result
    }
}
