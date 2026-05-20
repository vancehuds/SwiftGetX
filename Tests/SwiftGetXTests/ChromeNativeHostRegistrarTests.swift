import Foundation
import Testing
@testable import SwiftGetX

@Suite("ChromeNativeHostRegistrar")
struct ChromeNativeHostRegistrarTests {
    @Test("does not create manifest before Chrome extension is paired")
    func doesNotCreateManifestBeforeChromeExtensionIsPaired() throws {
        let fixture = try makeFixture(
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        defer { try? fixture.remove() }

        let result = fixture.registrar.register()

        #expect(result.status == .warning)
        #expect(fixture.registrar.readManifest() == nil)
    }

    @Test("pairs verified extension and creates manifest")
    func pairsVerifiedExtensionAndCreatesManifest() throws {
        let fixture = try makeFixture(
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        defer { try? fixture.remove() }

        let result = fixture.registrar.pairAndRegister(extensionID: "bcdefghijklmnopabcdefghijklmnopa")

        #expect(result.status == .ok)
        #expect(fixture.registrar.isPairedExtensionID("bcdefghijklmnopabcdefghijklmnopa"))
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
        fixture.pairingStore.pair("bcdefghijklmnopabcdefghijklmnopa")

        let result = fixture.registrar.register()

        #expect(result.status == .ok)
        let written = try #require(fixture.registrar.readManifest())
        #expect(written.path == fixture.nativeHost.path)
    }

    @Test("diagnoses wrong manifest host name as repairable")
    func diagnosesWrongManifestHostNameAsRepairable() throws {
        let fixture = try makeFixture(
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        defer { try? fixture.remove() }

        try fixture.writeManifest(
            name: "com.example.other",
            path: fixture.nativeHost.path,
            type: "stdio",
            origins: ["chrome-extension://bcdefghijklmnopabcdefghijklmnopa/"]
        )
        fixture.pairingStore.pair("bcdefghijklmnopabcdefghijklmnopa")

        let diagnosis = fixture.registrar.diagnose()
        #expect(diagnosis.status == .error)
        #expect(diagnosis.isRepairable)

        let repair = fixture.registrar.register()
        #expect(repair.status == .ok)
        #expect(fixture.registrar.readManifest()?.name == ChromeNativeHostRegistrar.defaultHostName)
    }

    @Test("diagnoses wrong manifest type as repairable")
    func diagnosesWrongManifestTypeAsRepairable() throws {
        let fixture = try makeFixture(
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        defer { try? fixture.remove() }

        try fixture.writeManifest(
            path: fixture.nativeHost.path,
            type: "wrong",
            origins: ["chrome-extension://bcdefghijklmnopabcdefghijklmnopa/"]
        )
        fixture.pairingStore.pair("bcdefghijklmnopabcdefghijklmnopa")

        let diagnosis = fixture.registrar.diagnose()
        #expect(diagnosis.status == .error)
        #expect(diagnosis.isRepairable)

        let repair = fixture.registrar.register()
        #expect(repair.status == .ok)
        #expect(fixture.registrar.readManifest()?.type == "stdio")
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
        fixture.pairingStore.pair("cdefghijklmnopabcdefghijklmnopab")

        let result = fixture.registrar.register()

        #expect(result.status == .ok)
        let written = try #require(fixture.registrar.readManifest())
        #expect(written.allowed_origins == [
            "chrome-extension://cdefghijklmnopabcdefghijklmnopab/"
        ])
    }

    @Test("removes unpaired origins instead of preserving them")
    func removesUnpairedOriginsInsteadOfPreservingThem() throws {
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
        fixture.pairingStore.pair("cdefghijklmnopabcdefghijklmnopab")

        let result = fixture.registrar.register()

        #expect(result.status == .ok)
        let written = try #require(fixture.registrar.readManifest())
        #expect(written.allowed_origins == [
            "chrome-extension://cdefghijklmnopabcdefghijklmnopab/"
        ])
    }

    @Test("diagnoses missing paired origin as repairable")
    func diagnosesMissingPairedOriginAsRepairable() throws {
        let fixture = try makeFixture(
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"]),
                "cdefghijklmnopabcdefghijklmnopab": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        defer { try? fixture.remove() }

        fixture.pairingStore.pair("bcdefghijklmnopabcdefghijklmnopa")
        fixture.pairingStore.pair("cdefghijklmnopabcdefghijklmnopab")
        try fixture.writeManifest(
            path: fixture.nativeHost.path,
            origins: ["chrome-extension://bcdefghijklmnopabcdefghijklmnopa/"]
        )

        let diagnosis = fixture.registrar.diagnose()
        #expect(diagnosis.status == .warning)
        #expect(diagnosis.isRepairable)

        let repair = fixture.registrar.register()
        #expect(repair.status == .ok)
        #expect(fixture.registrar.readManifest()?.allowed_origins == [
            "chrome-extension://bcdefghijklmnopabcdefghijklmnopa/",
            "chrome-extension://cdefghijklmnopabcdefghijklmnopab/"
        ])
    }

    @Test("does not pair unverified extension ID")
    func doesNotPairUnverifiedExtensionID() throws {
        let fixture = try makeFixture(
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        defer { try? fixture.remove() }

        let result = fixture.registrar.pairAndRegister(extensionID: "cdefghijklmnopabcdefghijklmnopab")

        #expect(result.status == .warning)
        #expect(!fixture.registrar.isPairedExtensionID("cdefghijklmnopabcdefghijklmnopab"))
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
        let pairingStore = ChromeNativeHostPairingStore(pairedExtensionIDs: [])
        let registrar = ChromeNativeHostRegistrar(
            manifestDirectory: manifestDirectory,
            extensionDiscovery: discovery,
            pairingStore: pairingStore,
            nativeHostSearchPaths: [nativeHost]
        )

        return RegistrarFixture(
            root: root,
            nativeHost: nativeHost,
            pairingStore: pairingStore,
            registrar: registrar
        )
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
    var pairingStore: ChromeNativeHostPairingStore
    var registrar: ChromeNativeHostRegistrar

    func writeManifest(path: String, origins: [String]) throws {
        try writeManifestContent(
            name: ChromeNativeHostRegistrar.defaultHostName,
            path: path,
            type: "stdio",
            origins: origins
        )
    }

    func writeManifest(
        name: String,
        path: String,
        type: String,
        origins: [String]
    ) throws {
        try writeManifestContent(name: name, path: path, type: type, origins: origins)
    }

    func writeManifest(
        path: String,
        type: String,
        origins: [String]
    ) throws {
        try writeManifestContent(
            name: ChromeNativeHostRegistrar.defaultHostName,
            path: path,
            type: type,
            origins: origins
        )
    }

    private func writeManifestContent(
        name: String,
        path: String,
        type: String,
        origins: [String]
    ) throws {
        try FileManager.default.createDirectory(
            at: registrar.manifestDirectory,
            withIntermediateDirectories: true
        )

        let manifest = ChromeNativeHostRegistrar.ManifestContent(
            name: name,
            description: "SwiftGetX Native Messaging host",
            path: path,
            type: type,
            allowed_origins: origins
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: registrar.manifestURL)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: root)
    }
}
