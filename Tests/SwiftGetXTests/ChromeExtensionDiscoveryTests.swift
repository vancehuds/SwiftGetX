import Foundation
import Testing
@testable import SwiftGetX

@Suite("ChromeExtensionDiscovery")
struct ChromeExtensionDiscoveryTests {
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
        let settings = extensions.mapValues { extensionManifest in
            ["manifest": extensionManifest]
        }
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

    private func manifest(name: String, permissions: [String]) -> [String: Any] {
        [
            "name": name,
            "permissions": permissions
        ]
    }
}
