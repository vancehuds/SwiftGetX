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

    @Test("reports browser diagnostics for each configured browser")
    func reportsBrowserDiagnosticsForEachConfiguredBrowser() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let chromeProfile = root.appendingPathComponent("Chrome")
        let edgeProfile = root.appendingPathComponent("Edge")
        let braveProfile = root.appendingPathComponent("Brave")
        let chromeManifestDirectory = root.appendingPathComponent("Chrome/NativeMessagingHosts")
        let edgeManifestDirectory = root.appendingPathComponent("Edge/NativeMessagingHosts")
        let braveManifestDirectory = root.appendingPathComponent("Brave/NativeMessagingHosts")
        let nativeHost = root.appendingPathComponent("SwiftGetXNativeHost")

        try writePreferences(
            to: chromeProfile.appendingPathComponent("Default/Secure Preferences"),
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        try writePreferences(
            to: edgeProfile.appendingPathComponent("Default/Secure Preferences"),
            extensions: [
                "cdefghijklmnopabcdefghijklmnopab": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        try Data("#!/bin/sh\n".utf8).write(to: nativeHost)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: nativeHost.path
        )

        let discovery = ChromeExtensionDiscovery(
            browserConfigurations: [
                ChromiumBrowserConfiguration(
                    name: "Chrome",
                    userDataDirectory: chromeProfile,
                    nativeMessagingHostDirectory: chromeManifestDirectory
                ),
                ChromiumBrowserConfiguration(
                    name: "Microsoft Edge",
                    userDataDirectory: edgeProfile,
                    nativeMessagingHostDirectory: edgeManifestDirectory
                ),
                ChromiumBrowserConfiguration(
                    name: "Brave",
                    userDataDirectory: braveProfile,
                    nativeMessagingHostDirectory: braveManifestDirectory
                )
            ]
        )
        let registrar = ChromeNativeHostRegistrar(
            manifestDirectory: ChromeNativeHostRegistrar.defaultManifestDirectory(),
            extensionDiscovery: discovery,
            pairingStore: ChromeNativeHostPairingStore(
                pairedExtensionIDs: [
                    "bcdefghijklmnopabcdefghijklmnopa",
                    "cdefghijklmnopabcdefghijklmnopab"
                ]
            ),
            nativeHostSearchPaths: [nativeHost]
        )

        let result = registrar.register()
        let diagnostics = registrar.browserDiagnostics()
        let byBrowser = Dictionary(uniqueKeysWithValues: diagnostics.map { ($0.browserName, $0) })
        let chrome = try #require(byBrowser["Chrome"])
        let edge = try #require(byBrowser["Microsoft Edge"])
        let brave = try #require(byBrowser["Brave"])

        #expect(result.status == .ok)
        #expect(diagnostics.count == 3)
        #expect(chrome.status == .ok)
        #expect(chrome.isConfigured)
        #expect(chrome.discoveredExtensionIDs == ["bcdefghijklmnopabcdefghijklmnopa"])
        #expect(chrome.pairedExtensionIDs == ["bcdefghijklmnopabcdefghijklmnopa"])
        #expect(chrome.manifestURL.path == chromeManifestDirectory
            .appendingPathComponent("com.swiftgetx.native.json")
            .path)
        #expect(chrome.nativeHostPath == nativeHost.path)
        #expect(chrome.allowedOriginCount == 1)
        #expect(chrome.hasBrowserProfile)

        #expect(edge.status == .ok)
        #expect(edge.isConfigured)
        #expect(edge.discoveredExtensionIDs == ["cdefghijklmnopabcdefghijklmnopab"])
        #expect(edge.pairedExtensionIDs == ["cdefghijklmnopabcdefghijklmnopab"])
        #expect(edge.manifestURL.path == edgeManifestDirectory
            .appendingPathComponent("com.swiftgetx.native.json")
            .path)
        #expect(edge.nativeHostPath == nativeHost.path)
        #expect(edge.allowedOriginCount == 1)

        #expect(brave.status == .warning)
        #expect(!brave.isConfigured)
        #expect(!brave.hasBrowserProfile)
        #expect(brave.discoveredExtensionIDs.isEmpty)
        #expect(brave.pairedExtensionIDs.isEmpty)
        #expect(brave.manifestURL.path == braveManifestDirectory
            .appendingPathComponent("com.swiftgetx.native.json")
            .path)
        #expect(registrar.isSupportedBrowserName("Microsoft Edge"))
        #expect(registrar.isSupportedBrowserName("brave"))
        #expect(!registrar.isSupportedBrowserName("Firefox"))
    }

    @Test("writes manifests for multiple Chromium browser configurations")
    func writesManifestsForMultipleChromiumBrowserConfigurations() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let chromeProfile = root.appendingPathComponent("Chrome")
        let vivaldiProfile = root.appendingPathComponent("Vivaldi")
        let chromeManifestDirectory = root.appendingPathComponent("Chrome/NativeMessagingHosts")
        let vivaldiManifestDirectory = root.appendingPathComponent("Vivaldi/NativeMessagingHosts")
        let nativeHost = root.appendingPathComponent("SwiftGetXNativeHost")

        try writePreferences(
            to: chromeProfile.appendingPathComponent("Default/Secure Preferences"),
            extensions: [
                "bcdefghijklmnopabcdefghijklmnopa": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        try writePreferences(
            to: vivaldiProfile.appendingPathComponent("Default/Preferences"),
            extensions: [
                "cdefghijklmnopabcdefghijklmnopab": manifest(name: "SwiftGetX", permissions: ["nativeMessaging"])
            ]
        )
        try Data("#!/bin/sh\n".utf8).write(to: nativeHost)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: nativeHost.path
        )

        let discovery = ChromeExtensionDiscovery(
            browserConfigurations: [
                ChromiumBrowserConfiguration(
                    name: "Chrome",
                    userDataDirectory: chromeProfile,
                    nativeMessagingHostDirectory: chromeManifestDirectory
                ),
                ChromiumBrowserConfiguration(
                    name: "Vivaldi",
                    userDataDirectory: vivaldiProfile,
                    nativeMessagingHostDirectory: vivaldiManifestDirectory
                )
            ]
        )
        let registrar = ChromeNativeHostRegistrar(
            manifestDirectory: ChromeNativeHostRegistrar.defaultManifestDirectory(),
            extensionDiscovery: discovery,
            pairingStore: ChromeNativeHostPairingStore(
                pairedExtensionIDs: [
                    "bcdefghijklmnopabcdefghijklmnopa",
                    "cdefghijklmnopabcdefghijklmnopab"
                ]
            ),
            nativeHostSearchPaths: [nativeHost]
        )

        let result = registrar.register()
        let chromeManifest = try readManifest(
            at: chromeManifestDirectory.appendingPathComponent("com.swiftgetx.native.json")
        )
        let vivaldiManifest = try readManifest(
            at: vivaldiManifestDirectory.appendingPathComponent("com.swiftgetx.native.json")
        )

        #expect(result.status == .ok)
        #expect(chromeManifest.path == nativeHost.path)
        #expect(chromeManifest.allowed_origins == [
            "chrome-extension://bcdefghijklmnopabcdefghijklmnopa/"
        ])
        #expect(vivaldiManifest.path == nativeHost.path)
        #expect(vivaldiManifest.allowed_origins == [
            "chrome-extension://cdefghijklmnopabcdefghijklmnopab/"
        ])
    }

    @Test("pairs Atlas extension and writes Atlas native host manifest")
    func pairsAtlasExtensionAndWritesAtlasNativeHostManifest() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let atlasDataDirectory = root.appendingPathComponent("Atlas")
        let atlasProfile = atlasDataDirectory.appendingPathComponent("user-123")
        let atlasManifestDirectory = root.appendingPathComponent("OpenAI/ChatGPT Atlas/NativeMessagingHosts")
        let chromeManifestDirectory = root.appendingPathComponent("Chrome/NativeMessagingHosts")
        let nativeHost = root.appendingPathComponent("SwiftGetXNativeHost")
        let extensionDirectory = root.appendingPathComponent("Downloads/SwiftGetX-Chrome")

        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        let extensionManifest = try JSONSerialization.data(
            withJSONObject: manifest(name: "SwiftGetX", permissions: ["nativeMessaging"]),
            options: [.prettyPrinted, .sortedKeys]
        )
        try extensionManifest.write(to: extensionDirectory.appendingPathComponent("manifest.json"))
        try writeSettings(
            to: atlasProfile.appendingPathComponent("Secure Preferences"),
            settings: [
                "mcblddhfakekibmceoppdodhhfjdjjfc": [
                    "path": extensionDirectory.path
                ]
            ]
        )
        try Data("#!/bin/sh\n".utf8).write(to: nativeHost)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: nativeHost.path
        )

        let discovery = ChromeExtensionDiscovery(
            browserConfigurations: [
                ChromiumBrowserConfiguration(
                    name: "Chrome",
                    userDataDirectory: root.appendingPathComponent("Chrome"),
                    nativeMessagingHostDirectory: chromeManifestDirectory
                ),
                ChromiumBrowserConfiguration(
                    name: "Atlas",
                    userDataDirectory: atlasDataDirectory,
                    nativeMessagingHostDirectory: atlasManifestDirectory
                )
            ]
        )
        let registrar = ChromeNativeHostRegistrar(
            manifestDirectory: ChromeNativeHostRegistrar.defaultManifestDirectory(),
            extensionDiscovery: discovery,
            pairingStore: ChromeNativeHostPairingStore(pairedExtensionIDs: []),
            nativeHostSearchPaths: [nativeHost]
        )

        let result = registrar.pairAndRegister(extensionID: "mcblddhfakekibmceoppdodhhfjdjjfc")

        #expect(result.status == .ok)
        #expect(!FileManager.default.fileExists(atPath: chromeManifestDirectory.path))
        let atlasManifestURL = atlasManifestDirectory.appendingPathComponent("com.swiftgetx.native.json")
        let data = try Data(contentsOf: atlasManifestURL)
        let manifest = try JSONDecoder().decode(ChromeNativeHostRegistrar.ManifestContent.self, from: data)
        #expect(manifest.path == nativeHost.path)
        #expect(manifest.allowed_origins == [
            "chrome-extension://mcblddhfakekibmceoppdodhhfjdjjfc/"
        ])
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
        try writeSettings(to: url, settings: settings)
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

    private func manifest(name: String, permissions: [String]) -> [String: Any] {
        [
            "name": name,
            "permissions": permissions
        ]
    }

    private func readManifest(at url: URL) throws -> ChromeNativeHostRegistrar.ManifestContent {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ChromeNativeHostRegistrar.ManifestContent.self, from: data)
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
