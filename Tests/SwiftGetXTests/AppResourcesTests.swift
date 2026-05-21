import Foundation
import Testing
@testable import SwiftGetX

@Suite("AppResources")
struct AppResourcesTests {
    @Test("resolves localized strings from the app resource bundle")
    func resolvesLocalizedStrings() {
        #expect(L10n.string("status_ready") == "Ready")
    }

    @Test("resolves copied resource directories from the app resource bundle")
    func resolvesCopiedResourceDirectories() throws {
        let extensionDirectory = try #require(AppResources.url(forResource: "ChromeExtension"))

        #expect(FileManager.default.fileExists(
            atPath: extensionDirectory.appendingPathComponent("manifest.json").path
        ))
    }
}
