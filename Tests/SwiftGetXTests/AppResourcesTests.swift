import Foundation
import Testing
@testable import SwiftGetX

@Suite("AppResources", .serialized)
@MainActor
struct AppResourcesTests {
    @Test("resolves localized strings from the app resource bundle")
    func resolvesLocalizedStrings() {
        let languageBundle = AppResources.localizationBundle(for: AppLanguage.en.rawValue, in: AppResources.bundle)

        #expect(NSLocalizedString("status_ready", bundle: languageBundle, comment: "") == "Ready")
    }

    @Test("resolves copied resource directories from the app resource bundle")
    func resolvesCopiedResourceDirectories() throws {
        let extensionDirectory = try #require(AppResources.url(forResource: "ChromeExtension"))

        #expect(FileManager.default.fileExists(
            atPath: extensionDirectory.appendingPathComponent("manifest.json").path
        ))
    }

    @Test("AppInfo declares torrent files and Services input")
    func appInfoDeclaresTorrentFilesAndServicesInput() throws {
        let appInfoURL = try #require(AppResources.url(forResource: "AppInfo", withExtension: "plist"))
        let data = try Data(contentsOf: appInfoURL)
        let plist = try #require(PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any])

        let documentTypes = try #require(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let torrentType = try #require(documentTypes.first)
        #expect((torrentType["CFBundleTypeExtensions"] as? [String])?.contains("torrent") == true)
        #expect((torrentType["LSItemContentTypes"] as? [String])?.contains("org.bittorrent.torrent") == true)

        let importedTypes = try #require(plist["UTImportedTypeDeclarations"] as? [[String: Any]])
        #expect(importedTypes.contains { declaration in
            declaration["UTTypeIdentifier"] as? String == "org.bittorrent.torrent"
        })

        let services = try #require(plist["NSServices"] as? [[String: Any]])
        let service = try #require(services.first)
        #expect(service["NSMessage"] as? String == "addDownloadFromService")
        let sendTypes = try #require(service["NSSendTypes"] as? [String])
        #expect(sendTypes.contains("public.url"))
        #expect(sendTypes.contains("public.file-url"))
        #expect(sendTypes.contains("public.utf8-plain-text"))
        #expect(sendTypes.contains("NSFilenamesPboardType"))
    }

    @Test("dynamically updates localization bundle when language settings change")
    func dynamicLanguageSwitching() {
        let chineseBundle = AppResources.localizationBundle(for: AppLanguage.zhHans.rawValue, in: AppResources.bundle)
        let englishBundle = AppResources.localizationBundle(for: AppLanguage.en.rawValue, in: AppResources.bundle)

        #expect(NSLocalizedString("status_ready", bundle: chineseBundle, comment: "") == "就绪")
        #expect(NSLocalizedString("status_ready", bundle: englishBundle, comment: "") == "Ready")
    }

    @Test("resolves lowercase SwiftPM localization directory names")
    func resolvesLowercaseSwiftPMLocalizationDirectoryNames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleURL = root.appendingPathComponent("Test.bundle", isDirectory: true)
        let englishURL = bundleURL.appendingPathComponent("en.lproj", isDirectory: true)
        let chineseURL = bundleURL.appendingPathComponent("zh-hans.lproj", isDirectory: true)

        try FileManager.default.createDirectory(at: englishURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chineseURL, withIntermediateDirectories: true)
        try """
        "status_ready" = "Ready";
        """.write(
            to: englishURL.appendingPathComponent("Localizable.strings"),
            atomically: true,
            encoding: .utf8
        )
        try """
        "status_ready" = "就绪";
        """.write(
            to: chineseURL.appendingPathComponent("Localizable.strings"),
            atomically: true,
            encoding: .utf8
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let baseBundle = try #require(Bundle(url: bundleURL))
        let languageBundle = AppResources.localizationBundle(for: AppLanguage.zhHans.rawValue, in: baseBundle)

        #expect(NSLocalizedString("status_ready", bundle: languageBundle, comment: "") == "就绪")
    }

    @Test("AppSettings starts with persisted language preference")
    func appSettingsStartsWithPersistedLanguagePreference() {
        let userDefaults = Self.makeIsolatedUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: Self.userDefaultsSuiteName(userDefaults)) }
        userDefaults.set(AppLanguage.zhHans.rawValue, forKey: AppSettings.languageUserDefaultsKey)
        let settings = AppSettings(userDefaults: userDefaults)

        #expect(settings.language == .zhHans)
    }

    @Test("UserDefaults language wins over stale settings record")
    func userDefaultsLanguageWinsOverStaleSettingsRecord() {
        let userDefaults = Self.makeIsolatedUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: Self.userDefaultsSuiteName(userDefaults)) }
        userDefaults.set(AppLanguage.zhHans.rawValue, forKey: AppSettings.languageUserDefaultsKey)
        let settings = AppSettings(userDefaults: userDefaults)
        let record = AppSettingsRecord(
            defaultDownloadDirectoryPath: "/tmp",
            languageRawValue: AppLanguage.system.rawValue
        )

        settings.apply(record)

        #expect(settings.language == .zhHans)
    }

    private static func makeIsolatedUserDefaults() -> UserDefaults {
        let suiteName = "SwiftGetXTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.set(suiteName, forKey: "suiteName")
        return userDefaults
    }

    private static func userDefaultsSuiteName(_ userDefaults: UserDefaults) -> String {
        userDefaults.string(forKey: "suiteName")!
    }
}
