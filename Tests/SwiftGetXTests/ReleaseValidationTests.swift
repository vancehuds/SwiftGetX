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

    @Test("release validator covers strict secrets, Sparkle, signing, notarization, and appcast")
    func releaseValidatorCoversReleaseGates() throws {
        let script = try readText("Scripts/validate-release.sh")

        #expect(script.contains("Scripts/validate-release.sh environment"))
        #expect(script.contains("Scripts/validate-release.sh sparkle"))
        #expect(script.contains("Scripts/validate-release.sh app <SwiftGetX.app>"))
        #expect(script.contains("Scripts/validate-release.sh dmg <SwiftGetX.dmg>"))
        #expect(script.contains("Scripts/validate-release.sh appcast <appcast.xml>"))
        #expect(script.contains("SWIFTGETX_RELEASE_STRICT=1"))
        #expect(script.contains("APPLE_DEVELOPER_ID_CERTIFICATE_BASE64"))
        #expect(script.contains("APPLE_DEVELOPER_ID_APPLICATION_IDENTITY"))
        #expect(script.contains("APPLE_NOTARY_KEY_ID"))
        #expect(script.contains("SPARKLE_EDDSA_PRIVATE_KEY"))
        #expect(script.contains("CHROME_EXTENSION_KEY_BASE64"))
        #expect(script.contains("SUPublicEDKey is still the placeholder"))
        #expect(script.contains("Sparkle.framework"))
        #expect(script.contains("SwiftGetXNativeHost"))
        #expect(script.contains("xcrun stapler validate"))
        #expect(script.contains("sparkle:releaseNotesLink"))
        #expect(script.contains("sparkle:edSignature"))
    }

    @Test("release workflow fails early and verifies signed artifacts")
    func releaseWorkflowFailsEarlyAndVerifiesArtifacts() throws {
        let workflow = try readText(".github/workflows/release.yml")

        #expect(workflow.contains("Validate release secrets and Sparkle configuration"))
        #expect(workflow.contains("Scripts/validate-release.sh environment"))
        #expect(workflow.contains("Import Developer ID certificate"))
        #expect(workflow.contains("SWIFTGETX_RELEASE_STRICT: \"1\""))
        #expect(workflow.contains("SWIFTGETX_CODESIGN_IDENTITY"))
        #expect(workflow.contains("APPLE_NOTARY_KEY_ID"))
        #expect(workflow.contains("Scripts/package-dmg.sh release dist --dmg"))
        #expect(workflow.contains("Verify signed and notarized artifacts"))
        #expect(workflow.contains("Scripts/validate-release.sh app dist/SwiftGetX.app"))
        #expect(workflow.contains("Scripts/validate-release.sh dmg dist/SwiftGetX.dmg"))
        #expect(workflow.contains("SWIFTGETX_RELEASE_NOTES_URL"))
        #expect(workflow.contains("SPARKLE_EDDSA_PRIVATE_KEY"))
    }

    @Test("build workflow keeps local-safe Sparkle validation")
    func buildWorkflowKeepsLocalSafeSparkleValidation() throws {
        let workflow = try readText(".github/workflows/build.yml")

        #expect(workflow.contains("Validate Sparkle configuration"))
        #expect(workflow.contains("Scripts/validate-release.sh sparkle"))
        #expect(!workflow.contains("Scripts/validate-release.sh environment"))
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
    }

    private func readText(_ relativePath: String) throws -> String {
        let url = rootURL.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
