import Foundation
import Testing
@testable import SwiftGetX

@Suite("ChromeExtensionDiscovery")
struct ChromeExtensionDiscoveryTests {
    @Test("default browser configurations include supported Chromium variants")
    func defaultBrowserConfigurationsIncludeSupportedChromiumVariants() throws {
        let homeDirectory = URL(fileURLWithPath: "/Users/swiftgetx-test")

        let configurations = ChromeExtensionDiscovery.defaultBrowserConfigurations(
            homeDirectory: homeDirectory
        )
        let names = configurations.map(\.name)

        #expect(names == [
            "Chrome",
            "Chrome Canary",
            "Microsoft Edge",
            "Brave",
            "Vivaldi",
            "Arc",
            "Chromium",
            "Atlas"
        ])

        let byName = Dictionary(uniqueKeysWithValues: configurations.map { ($0.name, $0) })
        let edge = try #require(byName["Microsoft Edge"])
        let brave = try #require(byName["Brave"])
        let vivaldi = try #require(byName["Vivaldi"])
        let arc = try #require(byName["Arc"])
        let chromium = try #require(byName["Chromium"])
        let canary = try #require(byName["Chrome Canary"])
        let atlas = try #require(byName["Atlas"])

        #expect(edge.userDataDirectory.path == homeDirectory
            .appendingPathComponent("Library/Application Support/Microsoft Edge")
            .path)
        #expect(brave.userDataDirectory.path == homeDirectory
            .appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser")
            .path)
        #expect(vivaldi.userDataDirectory.path == homeDirectory
            .appendingPathComponent("Library/Application Support/Vivaldi")
            .path)
        #expect(arc.userDataDirectory.path == homeDirectory
            .appendingPathComponent("Library/Application Support/Arc/User Data")
            .path)
        #expect(chromium.userDataDirectory.path == homeDirectory
            .appendingPathComponent("Library/Application Support/Chromium")
            .path)
        #expect(canary.userDataDirectory.path == homeDirectory
            .appendingPathComponent("Library/Application Support/Google/Chrome Canary")
            .path)
        #expect(atlas.nativeMessagingHostDirectory.path == homeDirectory
            .appendingPathComponent("Library/Application Support/OpenAI/ChatGPT Atlas/NativeMessagingHosts")
            .path)
    }

    @Test("discovers SwiftGetX extension IDs from Secure Preferences")
    func discoversFromSecurePreferences() throws {
        let root = try makeChromeProfile(
            filename: "Secure Preferences",
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"]),
                "cdefghijklmnopabcdefghijklmnopab": manifest(name: "Other", permissions: ["nativeMessaging"])
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let discovery = ChromeExtensionDiscovery(userDataDirectory: root)

        #expect(discovery.discoverExtensionIDs() == ["bcdefghijklmnopabcdefghijklmnopa"])
    }

    @Test("discovers SwiftGetX extension IDs from injected Chromium variants")
    func discoversFromInjectedChromiumVariants() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let edgeProfile = root.appendingPathComponent("Microsoft Edge")
        let braveProfile = root.appendingPathComponent("BraveSoftware/Brave-Browser")

        try writePreferences(
            to: edgeProfile.appendingPathComponent("Default/Secure Preferences"),
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        try writePreferences(
            to: braveProfile.appendingPathComponent("Profile 1/Preferences"),
            extensions: [
                "cdefghijklmnopabcdefghijklmnopab": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )

        let edgeConfiguration = ChromiumBrowserConfiguration(
            name: "Microsoft Edge",
            userDataDirectory: edgeProfile
        )
        let braveConfiguration = ChromiumBrowserConfiguration(
            name: "Brave",
            userDataDirectory: braveProfile
        )
        let discovery = ChromeExtensionDiscovery(
            browserConfigurations: [edgeConfiguration, braveConfiguration]
        )

        #expect(discovery.discoverExtensionIDs() == [
            "bcdefghijklmnopabcdefghijklmnopa",
            "cdefghijklmnopabcdefghijklmnopab"
        ])
        #expect(discovery.discoverExtensionInstallations() == [
            ChromeExtensionInstallation(
                extensionID: "bcdefghijklmnopabcdefghijklmnopa",
                browserConfiguration: edgeConfiguration
            ),
            ChromeExtensionInstallation(
                extensionID: "cdefghijklmnopabcdefghijklmnopab",
                browserConfiguration: braveConfiguration
            )
        ])
    }

    @Test("deduplicates SwiftGetX extension IDs across profiles")
    func deduplicatesAcrossProfiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try writePreferences(
            to: root.appendingPathComponent("Default/Secure Preferences"),
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        try writePreferences(
            to: root.appendingPathComponent("Profile 1/Preferences"),
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"]),
                "cdefghijklmnopabcdefghijklmnopab": manifest(name: "SwiftGetX", permissions: ["storage", "nativeMessaging"])
            ]
        )

        let discovery = ChromeExtensionDiscovery(userDataDirectory: root)

        #expect(discovery.discoverExtensionIDs() == [
            "bcdefghijklmnopabcdefghijklmnopa",
            "cdefghijklmnopabcdefghijklmnopab"
        ])
    }

    @Test("ignores matching names without native messaging permission")
    func ignoresExtensionsWithoutNativeMessaging() throws {
        let root = try makeChromeProfile(
            filename: "Secure Preferences",
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["storage"])
            ]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let discovery = ChromeExtensionDiscovery(userDataDirectory: root)

        #expect(discovery.discoverExtensionIDs().isEmpty)
    }

    @Test("discovers unpacked development extension from local path and extension shape")
    func discoversUnpackedDevelopmentExtension() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let extensionDirectory = root
            .appendingPathComponent("Sources/SwiftGetX/Resources/ChromeExtension")
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: extensionDirectory.appendingPathComponent("manifest.json"))

        try writeSettings(
            to: root.appendingPathComponent("Default/Secure Preferences"),
            settings: [
                "bcdefghijklmnopabcdefghijklmnopa": [
                    "path": extensionDirectory.path,
                    "manifest": manifest(
                        name: "__MSG_extensionName__",
                        description: ChromeExtensionDiscovery.defaultExtensionDescriptionPrefix,
                        permissions: ["nativeMessaging"],
                        action: ["default_popup": ChromeExtensionDiscovery.defaultExtensionPopupPath]
                    )
                ]
            ]
        )

        let discovery = ChromeExtensionDiscovery(userDataDirectory: root)

        #expect(discovery.discoverExtensionIDs() == ["bcdefghijklmnopabcdefghijklmnopa"])
    }

    @Test("discovers Atlas unpacked extension from path manifest")
    func discoversAtlasUnpackedExtensionFromPathManifest() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let atlasDataDirectory = root.appendingPathComponent("Atlas")
        let profileDirectory = atlasDataDirectory.appendingPathComponent("user-123")
        let extensionDirectory = root.appendingPathComponent("Downloads/SwiftGetX-Chrome")
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest(name: "SwiftGetX", permissions: ["nativeMessaging"]),
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(to: extensionDirectory.appendingPathComponent("manifest.json"))

        try writeSettings(
            to: profileDirectory.appendingPathComponent("Secure Preferences"),
            settings: [
                "mcblddhfakekibmceoppdodhhfjdjjfc": [
                    "path": extensionDirectory.path
                ]
            ]
        )

        let atlasConfiguration = ChromiumBrowserConfiguration(
            name: "Atlas",
            userDataDirectory: atlasDataDirectory,
            nativeMessagingHostDirectory: root.appendingPathComponent("OpenAI/ChatGPT Atlas/NativeMessagingHosts")
        )
        let discovery = ChromeExtensionDiscovery(browserConfigurations: [atlasConfiguration])

        #expect(discovery.discoverExtensionIDs() == ["mcblddhfakekibmceoppdodhhfjdjjfc"])
        let installation = try #require(discovery.discoverExtensionInstallations().first)
        #expect(installation.extensionID == "mcblddhfakekibmceoppdodhhfjdjjfc")
        #expect(installation.browserConfiguration == atlasConfiguration)
    }

    @Test("merges existing valid origins and removes placeholders")
    func mergesExistingOrigins() {
        let origins = ChromeNativeMessagingOrigin.merge(
            existingOrigins: [
                "chrome-extension://bcdefghijklmnopabcdefghijklmnopa/",
                "chrome-extension://REPLACE_WITH_CHROME_EXTENSION_ID/",
                "chrome-extension://not-valid/",
                "chrome-extension://bcdefghijklmnopabcdefghijklmnopa/"
            ],
            discoveredExtensionIDs: [
                "cdefghijklmnopabcdefghijklmnopab",
                "bcdefghijklmnopabcdefghijklmnopa"
            ]
        )

        #expect(origins == [
            "chrome-extension://bcdefghijklmnopabcdefghijklmnopa/",
            "chrome-extension://cdefghijklmnopabcdefghijklmnopab/"
        ])
    }

    @Test("does not synthesize placeholder origins when nothing is discovered")
    func noPlaceholderWhenNothingDiscovered() {
        let origins = ChromeNativeMessagingOrigin.merge(
            existingOrigins: ["chrome-extension://REPLACE_WITH_CHROME_EXTENSION_ID/"],
            discoveredExtensionIDs: []
        )

        #expect(origins.isEmpty)
    }

    private func makeChromeProfile(
        filename: String,
        extensions: [String: [String: Any]]
    ) throws -> URL {
        let root = try makeTemporaryDirectory()
        try writePreferences(
            to: root.appendingPathComponent("Default/\(filename)"),
            extensions: extensions
        )
        return root
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writePreferences(
        to url: URL,
        extensions: [String: [String: Any]]
    ) throws {
        try writeSettings(
            to: url,
            settings: extensions.mapValues { extensionManifest in
            ["manifest": extensionManifest]
            }
        )
    }

    private func writeSettings(
        to url: URL,
        settings: [String: [String: Any]]
    ) throws {
        let root: [String: Any] = [
            "extensions": [
                "settings": settings
            ]
        ]

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func manifest(
        name: String,
        description: String? = nil,
        permissions: [String],
        action: [String: Any]? = nil
    ) -> [String: Any] {
        var manifest: [String: Any] = [
            "name": name,
            "permissions": permissions
        ]
        if let description {
            manifest["description"] = description
        }
        if let action {
            manifest["action"] = action
        }
        return manifest
    }
}
