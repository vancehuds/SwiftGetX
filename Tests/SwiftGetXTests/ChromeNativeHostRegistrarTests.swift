import Foundation
import Testing
@testable import SwiftGetX

@Suite("ChromeNativeHostRegistrar")
struct ChromeNativeHostRegistrarTests {
    @Test("creates manifest when SwiftGetX extension is discovered")
    func createsManifestWhenExtensionIsDiscovered() throws {
        let fixture = try makeFixture(
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        defer { try? fixture.remove() }

        let result = fixture.registrar.register()

        #expect(result.status == .ok)
        let written = try #require(fixture.registrar.readManifest())
        #expect(written.path == fixture.nativeHost.path)
        #expect(written.type == "stdio")
        #expect(written.allowed_origins == [
            "chrome-extension://bcdefghijklmnopabcdefghijklmnopa/"
        ])
    }

    @Test("repairs stale native host path")
    func repairsStaleNativeHostPath() throws {
        let fixture = try makeFixture(
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        defer { try? fixture.remove() }

        try fixture.writeManifest(
            path: "/Applications/OldSwiftGetX.app/Contents/MacOS/SwiftGetXNativeHost",
            origins: ["chrome-extension://bcdefghijklmnopabcdefghijklmnopa/"]
        )

        let result = fixture.registrar.register()

        #expect(result.status == .ok)
        let written = try #require(fixture.registrar.readManifest())
        #expect(written.path == fixture.nativeHost.path)
    }

    @Test("removes placeholders and invalid origins")
    func removesPlaceholdersAndInvalidOrigins() throws {
        let fixture = try makeFixture(
            extensions: [
                "cdefghijklmnopabcdefghijklmnopab": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        defer { try? fixture.remove() }

        try fixture.writeManifest(
            path: fixture.nativeHost.path,
            origins: [
                "chrome-extension://REPLACE_WITH_CHROME_EXTENSION_ID/",
                "chrome-extension://not-valid/",
                "chrome-extension://cdefghijklmnopabcdefghijklmnopab/"
            ]
        )

        let result = fixture.registrar.register()

        #expect(result.status == .ok)
        let written = try #require(fixture.registrar.readManifest())
        #expect(written.allowed_origins == [
            "chrome-extension://cdefghijklmnopabcdefghijklmnopab/"
        ])
    }

    @Test("preserves valid origins and appends newly discovered IDs")
    func preservesValidOriginsAndAppendsDiscoveredIDs() throws {
        let fixture = try makeFixture(
            extensions: [
                "cdefghijklmnopabcdefghijklmnopab": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        defer { try? fixture.remove() }

        try fixture.writeManifest(
            path: fixture.nativeHost.path,
            origins: ["chrome-extension://bcdefghijklmnopabcdefghijklmnopa/"]
        )

        let result = fixture.registrar.register()

        #expect(result.status == .ok)
        let written = try #require(fixture.registrar.readManifest())
        #expect(written.allowed_origins == [
            "chrome-extension://bcdefghijklmnopabcdefghijklmnopa/",
            "chrome-extension://cdefghijklmnopabcdefghijklmnopab/"
        ])
    }

    @Test("does not write unverified setup hint")
    func doesNotWriteUnverifiedSetupHint() throws {
        let fixture = try makeFixture(
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        defer { try? fixture.remove() }

        let result = fixture.registrar.register(setupHintExtensionID: "cdefghijklmnopabcdefghijklmnopab")

        #expect(result.status == .warning)
        #expect(fixture.registrar.readManifest() == nil)
    }

    private func makeFixture(
        extensions: [String: [String: Any]]
    ) throws -> RegistrarFixture {
        let root = try makeTemporaryDirectory()
        let chromeProfile = root.appendingPathComponent("Chrome")
        let manifestDirectory = root.appendingPathComponent("NativeMessagingHosts")
        let nativeHost = root.appendingPathComponent("SwiftGetXNativeHost")

        try writePreferences(
            to: chromeProfile.appendingPathComponent("Default/Secure Preferences"),
            extensions: extensions
        )
        try Data("#!/bin/sh\n".utf8).write(to: nativeHost)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: nativeHost.path
        )

        let discovery = ChromeExtensionDiscovery(userDataDirectory: chromeProfile)
        let registrar = ChromeNativeHostRegistrar(
            manifestDirectory: manifestDirectory,
            extensionDiscovery: discovery,
            nativeHostSearchPaths: [nativeHost]
        )

        return RegistrarFixture(root: root, nativeHost: nativeHost, registrar: registrar)
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

private struct RegistrarFixture {
    var root: URL
    var nativeHost: URL
    var registrar: ChromeNativeHostRegistrar

    func writeManifest(path: String, origins: [String]) throws {
        try FileManager.default.createDirectory(
            at: registrar.manifestDirectory,
            withIntermediateDirectories: true
        )

        let manifest = ChromeNativeHostRegistrar.ManifestContent(
            name: ChromeNativeHostRegistrar.defaultHostName,
            description: "SwiftGetX Native Messaging host",
            path: path,
            type: "stdio",
            allowed_origins: origins
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: registrar.manifestURL)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: root)
    }
}
