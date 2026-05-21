import Foundation
import Testing
@testable import SwiftGetX

@Suite("AppResources", .serialized)
@MainActor
struct AppResourcesTests {
    @Test("resolves localized strings from the app resource bundle")
    func resolvesLocalizedStrings() {
        let originalLanguage = UserDefaults.standard.string(forKey: AppSettings.languageUserDefaultsKey)
        UserDefaults.standard.set("en", forKey: AppSettings.languageUserDefaultsKey)
        defer {
            UserDefaults.standard.set(originalLanguage, forKey: AppSettings.languageUserDefaultsKey)
        }
        #expect(L10n.string("status_ready") == "Ready")
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
        let originalLanguage = UserDefaults.standard.string(forKey: AppSettings.languageUserDefaultsKey)
        defer {
            UserDefaults.standard.set(originalLanguage, forKey: AppSettings.languageUserDefaultsKey)
        }

        UserDefaults.standard.set("zh-Hans", forKey: AppSettings.languageUserDefaultsKey)
        #expect(L10n.string("status_ready") == "就绪")

        UserDefaults.standard.set("en", forKey: AppSettings.languageUserDefaultsKey)
        #expect(L10n.string("status_ready") == "Ready")

        UserDefaults.standard.set("system", forKey: AppSettings.languageUserDefaultsKey)
    }

    @Test("AppSettings starts with persisted language preference")
    func appSettingsStartsWithPersistedLanguagePreference() {
        let originalLanguage = UserDefaults.standard.string(forKey: AppSettings.languageUserDefaultsKey)
        defer {
            UserDefaults.standard.set(originalLanguage, forKey: AppSettings.languageUserDefaultsKey)
        }

        UserDefaults.standard.set(AppLanguage.zhHans.rawValue, forKey: AppSettings.languageUserDefaultsKey)
        let settings = AppSettings()

        #expect(settings.language == .zhHans)
    }

    @Test("UserDefaults language wins over stale settings record")
    func userDefaultsLanguageWinsOverStaleSettingsRecord() {
        let originalLanguage = UserDefaults.standard.string(forKey: AppSettings.languageUserDefaultsKey)
        defer {
            UserDefaults.standard.set(originalLanguage, forKey: AppSettings.languageUserDefaultsKey)
        }

        UserDefaults.standard.set(AppLanguage.zhHans.rawValue, forKey: AppSettings.languageUserDefaultsKey)
        let settings = AppSettings()
        let record = AppSettingsRecord(
            defaultDownloadDirectoryPath: "/tmp",
            languageRawValue: AppLanguage.system.rawValue
        )

        settings.apply(record)

        #expect(settings.language == .zhHans)
    }
}
