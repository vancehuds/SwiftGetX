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
