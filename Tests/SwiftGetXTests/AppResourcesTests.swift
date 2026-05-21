import Foundation
import Testing
@testable import SwiftGetX

@Suite("AppResources", .serialized)
struct AppResourcesTests {
    @Test("resolves localized strings from the app resource bundle")
    func resolvesLocalizedStrings() {
        let originalLanguage = UserDefaults.standard.string(forKey: "app_language")
        UserDefaults.standard.set("en", forKey: "app_language")
        defer {
            UserDefaults.standard.set(originalLanguage, forKey: "app_language")
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
        let originalLanguage = UserDefaults.standard.string(forKey: "app_language")
        defer {
            UserDefaults.standard.set(originalLanguage, forKey: "app_language")
        }

        UserDefaults.standard.set("zh-Hans", forKey: "app_language")
        #expect(L10n.string("status_ready") == "就绪")

        UserDefaults.standard.set("en", forKey: "app_language")
        #expect(L10n.string("status_ready") == "Ready")

        UserDefaults.standard.set("system", forKey: "app_language")
    }
}
