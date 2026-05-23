import Foundation
import Testing
@testable import SwiftGetX

@Suite("ReleaseValidation")
struct ReleaseValidationTests {
    private let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    @Test("validates Sparkle public key format and rejects placeholders")
    func validatesSparklePublicKeyFormat() {
        #expect(ReleaseValidation.isValidSparklePublicKey("HcyPOd1A9bPy5IVujns0AXTxbzwXTobtNFjesFWNwTY="))
        #expect(!ReleaseValidation.isValidSparklePublicKey("REPLACE_WITH_YOUR_EDDSA_PUBLIC_KEY"))
        #expect(!ReleaseValidation.isValidSparklePublicKey("TODO"))
        #expect(!ReleaseValidation.isValidSparklePublicKey("not-base64"))
        #expect(!ReleaseValidation.isValidSparklePublicKey(Data(repeating: 1, count: 31).base64EncodedString()))
    }

    @Test("AppInfo has release-safe Sparkle configuration")
    func appInfoHasReleaseSafeSparkleConfiguration() throws {
        let appInfoURL = try #require(AppResources.url(forResource: "AppInfo", withExtension: "plist"))
        let data = try Data(contentsOf: appInfoURL)
        let plist = try #require(PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any])

        let publicKey = try #require(plist["SUPublicEDKey"] as? String)
        let feedURL = try #require(plist["SUFeedURL"] as? String)

        #expect(ReleaseValidation.isValidSparklePublicKey(publicKey))
        #expect(feedURL.hasPrefix("https://"))
        #expect(feedURL.hasSuffix("appcast.xml"))
    }

    @Test("release notes URL normalizes tag versions")
    func releaseNotesURLNormalizesTagVersions() throws {
        let url = try #require(ReleaseValidation.defaultReleaseNotesURL(version: "v1.2.3"))

        #expect(url.absoluteString == "https://github.com/vancehuds/SwiftGetX/releases/tag/v1.2.3")
    }

    @Test("release validator covers optional signing, Sparkle, notarization, and appcast")
    func releaseValidatorCoversReleaseGates() throws {
        let script = try readText("Scripts/validate-release.sh")

        #expect(script.contains("Scripts/validate-release.sh environment"))
        #expect(script.contains("Scripts/validate-release.sh sparkle"))
        #expect(script.contains("Scripts/validate-release.sh app <SwiftGetX.app>"))
        #expect(script.contains("Scripts/validate-release.sh dmg <SwiftGetX.dmg>"))
        #expect(script.contains("Scripts/validate-release.sh appcast <appcast.xml>"))
        #expect(script.contains("Developer ID signing and notarization validation skipped"))
        #expect(script.contains("SWIFTGETX_RELEASE_STRICT must be 0 or 1"))
        #expect(script.contains("APPLE_DEVELOPER_ID_CERTIFICATE_BASE64"))
        #expect(script.contains("APPLE_DEVELOPER_ID_APPLICATION_IDENTITY"))
        #expect(script.contains("APPLE_NOTARY_KEY_ID"))
        #expect(script.contains("SPARKLE_EDDSA_PRIVATE_KEY"))
        #expect(script.contains("CHROME_EXTENSION_KEY_BASE64"))
        #expect(script.contains("CHROME_EXTENSION_ID"))
        #expect(script.contains("SUPublicEDKey is still the placeholder"))
        #expect(script.contains("Sparkle.framework"))
        #expect(script.contains("SwiftGetXNativeHost"))
        #expect(script.contains("xcrun stapler validate"))
        #expect(script.contains("sparkle:releaseNotesLink"))
        #expect(script.contains("sparkle:edSignature"))
    }

    @Test("release workflow supports unsigned fallback and verifies artifacts")
    func releaseWorkflowFailsEarlyAndVerifiesArtifacts() throws {
        let workflow = try readText(".github/workflows/release.yml")

        #expect(workflow.contains("Configure release signing mode"))
        #expect(workflow.contains("SWIFTGETX_RELEASE_STRICT=0"))
        #expect(workflow.contains("SWIFTGETX_RELEASE_STRICT=1"))
        #expect(workflow.contains("SWIFTGETX_IMPORT_DEVELOPER_ID_CERTIFICATE=0"))
        #expect(workflow.contains("Incomplete Apple signing secrets"))
        #expect(workflow.contains("ad-hoc signed app bundle and unsigned, unnotarized DMG"))
        #expect(workflow.contains("Validate release configuration"))
        #expect(workflow.contains("Scripts/validate-release.sh environment"))
        #expect(workflow.contains("Import Developer ID certificate"))
        #expect(workflow.contains("Skipping Developer ID certificate import for unsigned release"))
        #expect(workflow.contains("SWIFTGETX_CODESIGN_IDENTITY"))
        #expect(workflow.contains("APPLE_NOTARY_KEY_ID"))
        #expect(workflow.contains("Scripts/package-dmg.sh release dist --dmg"))
        #expect(workflow.contains("Verify release artifacts"))
        #expect(workflow.contains("Scripts/validate-release.sh app dist/SwiftGetX.app"))
        #expect(workflow.contains("Scripts/validate-release.sh dmg dist/SwiftGetX.dmg"))
        #expect(workflow.contains("SWIFTGETX_RELEASE_NOTES_URL"))
        #expect(workflow.contains("SPARKLE_EDDSA_PRIVATE_KEY"))
        #expect(workflow.contains("SWIFTGETX_EXPECTED_CHROME_EXTENSION_ID"))
        #expect(workflow.contains("secrets.CHROME_EXTENSION_ID"))
        #expect(workflow.contains("SwiftGetX-Chrome.release.json"))
        #expect(!workflow.contains("Install native packaging dependencies"))
    }

    @Test("build workflow keeps local-safe Sparkle validation")
    func buildWorkflowKeepsLocalSafeSparkleValidation() throws {
        let workflow = try readText(".github/workflows/build.yml")

        #expect(workflow.contains("Validate Sparkle configuration"))
        #expect(workflow.contains("Scripts/validate-release.sh sparkle"))
        #expect(!workflow.contains("Scripts/validate-release.sh environment"))
        #expect(!workflow.contains("Install native packaging dependencies"))
        #expect(workflow.contains("SwiftGetX-Chrome.release.json"))
    }

    @Test("appcast generation wires release notes")
    func appcastGenerationWiresReleaseNotes() throws {
        let script = try readText("Scripts/generate-appcast.sh")

        #expect(script.contains("SWIFTGETX_RELEASE_NOTES_URL"))
        #expect(script.contains("SWIFTGETX_RELEASE_NOTES_TEXT"))
        #expect(script.contains("<sparkle:releaseNotesLink>"))
        #expect(script.contains("<description>"))
        #expect(script.contains("Sparkle sign_update returned an empty EdDSA signature"))
    }

    @Test("package script supports strict signing and notarization gates")
    func packageScriptSupportsStrictSigningAndNotarizationGates() throws {
        let script = try readText("Scripts/package-dmg.sh")

        #expect(script.contains("SWIFTGETX_RELEASE_STRICT"))
        #expect(script.contains("SWIFTGETX_CODESIGN_IDENTITY"))
        #expect(script.contains("--options runtime --timestamp"))
        #expect(script.contains("xcrun notarytool submit"))
        #expect(script.contains("xcrun stapler staple"))
        #expect(script.contains("Scripts/validate-release.sh app"))
        #expect(script.contains("Scripts/validate-release.sh dmg"))
        #expect(script.contains("codesign --force --deep --sign -"))
        #expect(script.contains("Acknowledgements.md"))
        #expect(script.contains("SWIFTGETX_ENABLE_LIBTORRENT"))
        #expect(!script.contains("if [[ \"${SWIFTGETX_DISABLE_LIBTORRENT:-}\" != \"1\" ]]; then"))
    }

    @Test("Chrome extension packaging enforces fixed release ID")
    func chromeExtensionPackagingEnforcesFixedReleaseID() throws {
        let packageScript = try readText("Scripts/package-chrome-extension.sh")
        let crxScript = try readText("Scripts/make-crx.mjs")

        #expect(packageScript.contains("SWIFTGETX_RELEASE_STRICT"))
        #expect(packageScript.contains("SWIFTGETX_EXPECTED_CHROME_EXTENSION_ID"))
        #expect(packageScript.contains("CHROME_EXTENSION_ID"))
        #expect(packageScript.contains("SwiftGetX-Chrome.release.json"))
        #expect(packageScript.contains("SWIFTGETX_CHROME_EXTENSION_ID_FILE"))
        #expect(crxScript.contains("CRX ID mismatch"))
        #expect(crxScript.contains("SWIFTGETX_EXPECTED_CHROME_EXTENSION_ID"))
        let mismatchIndex = try #require(crxScript.range(of: "CRX ID mismatch")?.lowerBound)
        let crxWriteIndex = try #require(crxScript.range(of: "writeFileSync(crxPath")?.lowerBound)
        #expect(mismatchIndex < crxWriteIndex)
    }

    @Test("extension distribution docs cover Web Store fixed ID compatibility and acknowledgements")
    func extensionDistributionDocsCoverReleaseRequirements() throws {
        let distribution = try readText("Docs/ChromeExtensionDistribution.md")
        let acknowledgements = try readText("Docs/Acknowledgements.md")
        let browser = try readText("Docs/BrowserIntegration.md")
        let torrent = try readText("Docs/TorrentEngine.md")
        let readme = try readText("README.md")
        let englishReadme = try readText("README.en.md")

        #expect(distribution.contains("Chrome Web Store"))
        #expect(distribution.contains("CHROME_EXTENSION_ID"))
        #expect(distribution.contains("Compatibility Matrix"))
        #expect(distribution.contains("Native Host 0.2.0"))
        #expect(browser.contains("extensionVersion"))
        #expect(browser.contains("minimumNativeHostVersion"))
        #expect(acknowledgements.contains("Sparkle"))
        #expect(acknowledgements.contains("libtorrent"))
        #expect(acknowledgements.contains("Boost"))
        #expect(acknowledgements.contains("OpenSSL"))
        #expect(torrent.contains("optional development/reference path"))
        #expect(readme.contains("HTTP%20%2F%20SwiftTorrent"))
        #expect(readme.contains("可选 libtorrent 参考实现依赖"))
        #expect(englishReadme.contains("HTTP%20%2F%20SwiftTorrent"))
        #expect(englishReadme.contains("Optional libtorrent reference dependencies"))
        #expect(englishReadme.contains("SwiftGetX-Chrome.release.json"))
    }

    private func readText(_ relativePath: String) throws -> String {
        let url = rootURL.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
