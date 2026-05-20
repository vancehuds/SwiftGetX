import Foundation

struct ChromeExtensionDiscovery {
    static let defaultExtensionName = "SwiftGetX"
    static let defaultExtensionDescriptionPrefix = "Send links, pages, media, and detected downloads to SwiftGetX."
    static let defaultExtensionPopupPath = "popup.html"

    let userDataDirectory: URL
    let extensionName: String
    let fileManager: FileManager
    let developmentExtensionDirectory: URL?

    init(
        userDataDirectory: URL = ChromeExtensionDiscovery.defaultChromeUserDataDirectory(),
        extensionName: String = ChromeExtensionDiscovery.defaultExtensionName,
        developmentExtensionDirectory: URL? = ChromeExtensionDiscovery.defaultDevelopmentExtensionDirectory(),
        fileManager: FileManager = .default
    ) {
        self.userDataDirectory = userDataDirectory
        self.extensionName = extensionName
        self.developmentExtensionDirectory = developmentExtensionDirectory?.standardizedFileURL
        self.fileManager = fileManager
    }

    static func defaultChromeUserDataDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Google/Chrome")
    }

    static func defaultDevelopmentExtensionDirectory(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "ChromeExtension", withExtension: nil)
    }

    func discoverExtensionIDs() -> [String] {
        var discoveredIDs = Set<String>()

        for preferenceFile in preferenceFiles() {
            discoverExtensionIDs(in: preferenceFile).forEach { discoveredIDs.insert($0) }
        }

        return discoveredIDs.sorted()
    }

    func discoverExtensionIDs(in preferenceFile: URL) -> [String] {
        guard let data = try? Data(contentsOf: preferenceFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let extensions = root["extensions"] as? [String: Any],
              let settings = extensions["settings"] as? [String: Any] else {
            return []
        }

        return settings.compactMap { extensionID, rawSettings in
            guard ChromeNativeMessagingOrigin.isValidExtensionID(extensionID),
                  let settings = rawSettings as? [String: Any],
                  isTargetSettings(settings) else {
                return nil
            }
            return extensionID
        }
        .sorted()
    }

    private func preferenceFiles() -> [URL] {
        let filenames = ["Secure Preferences", "Preferences"]
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

    private func isTargetSettings(_ settings: [String: Any]) -> Bool {
        guard let manifest = settings["manifest"] as? [String: Any],
              hasNativeMessagingPermission(manifest) else {
            return false
        }

        if isTargetManifest(manifest) {
            return true
        }

        if let path = settings["path"] as? String,
           isDevelopmentExtensionPath(path),
           isSwiftGetXChromeExtensionShape(manifest) {
            return true
        }

        return false
    }

    private func isTargetManifest(_ manifest: [String: Any]) -> Bool {
        guard let name = manifest["name"] as? String,
              name.caseInsensitiveCompare(extensionName) == .orderedSame else {
            return false
        }

        return true
    }

    private func hasNativeMessagingPermission(_ manifest: [String: Any]) -> Bool {
        permissions(in: manifest).contains("nativeMessaging")
    }

    private func isSwiftGetXChromeExtensionShape(_ manifest: [String: Any]) -> Bool {
        let action = manifest["action"] as? [String: Any]
        let description = manifest["description"] as? String
        return action?["default_popup"] as? String == Self.defaultExtensionPopupPath
            && description == Self.defaultExtensionDescriptionPrefix
    }

    private func isDevelopmentExtensionPath(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }

        let extensionPath = URL(fileURLWithPath: path).standardizedFileURL
        if let developmentExtensionDirectory,
           extensionPath == developmentExtensionDirectory {
            return true
        }

        return fileManager.fileExists(atPath: extensionPath.appendingPathComponent("manifest.json").path)
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
