import Foundation
import Testing
@testable import SwiftGetX
@testable import SwiftGetXCore

@Suite("NativeMessageHost")
struct NativeMessageHostTests {
    @Test("decodes length-prefixed browser messages")
    func decodesMessages() throws {
        let message = BrowserDownloadMessage(
            action: "download",
            url: "https://example.com/file.zip",
            browser: "Chrome",
            suggestedFilename: "file.zip"
        )
        let payload = try JSONEncoder().encode(message)
        var length = UInt32(payload.count).littleEndian
        var data = Data(bytes: &length, count: 4)
        data.append(payload)

        let decoded = try NativeMessageHost.decodeMessages(from: data)

        #expect(decoded.count == 1)
        #expect(decoded[0].url == "https://example.com/file.zip")
        #expect(decoded[0].browser == "Chrome")
    }

    @Test("reads one native message without waiting for stdin EOF")
    func readsSingleMessage() throws {
        let message = BrowserDownloadMessage(
            action: "download",
            url: "https://example.com/file.dmg",
            browser: "Chrome",
            suggestedFilename: "file.dmg"
        )
        let data = try encodeMessage(message)
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(data)
        pipe.fileHandleForWriting.closeFile()

        let decoded = try NativeMessageHost.readMessage(from: pipe.fileHandleForReading)

        #expect(decoded?.action == "download")
        #expect(decoded?.url == "https://example.com/file.dmg")
        #expect(decoded?.suggestedFilename == "file.dmg")
    }

    @Test("encodes length-prefixed response")
    func encodesResponse() throws {
        let encoded = try NativeMessageHost.encodeResponse(
            NativeMessageResponse(
                ok: true,
                message: "accepted",
                accepted: true,
                queued: true,
                requiresUserConfirmation: false,
                requestID: "request-1",
                protocolVersion: BrowserIntegrationCompatibility.protocolVersion,
                minimumExtensionVersion: BrowserIntegrationCompatibility.minimumChromeExtensionVersion,
                minimumNativeHostVersion: BrowserIntegrationCompatibility.minimumNativeHostVersion,
                compatible: true,
                compatibilityMessage: nil
            )
        )

        let payloadLength = encoded.prefix(4).withUnsafeBytes { pointer in
            pointer.load(as: UInt32.self).littleEndian
        }

        #expect(Int(payloadLength) == encoded.count - 4)

        let response = try JSONDecoder().decode(NativeMessageResponse.self, from: encoded.dropFirst(4))
        #expect(response.accepted == true)
        #expect(response.queued == true)
        #expect(response.requiresUserConfirmation == false)
        #expect(response.requestID == "request-1")
        #expect(response.protocolVersion == BrowserIntegrationCompatibility.protocolVersion)
        #expect(response.minimumExtensionVersion == BrowserIntegrationCompatibility.minimumChromeExtensionVersion)
        #expect(response.minimumNativeHostVersion == BrowserIntegrationCompatibility.minimumNativeHostVersion)
        #expect(response.compatible == true)
    }

    @Test("browser download messages carry compatibility metadata")
    func browserDownloadMessagesCarryCompatibilityMetadata() throws {
        let message = BrowserDownloadMessage(
            action: "download",
            url: "https://example.com/file.zip",
            browser: "Chrome",
            extensionVersion: "0.2.0",
            minimumNativeHostVersion: "0.2.0",
            protocolVersion: BrowserIntegrationCompatibility.protocolVersion
        )
        let data = try encodeMessage(message)

        let decoded = try #require(NativeMessageHost.decodeMessages(from: data).first)

        #expect(decoded.extensionVersion == "0.2.0")
        #expect(decoded.minimumNativeHostVersion == "0.2.0")
        #expect(decoded.protocolVersion == BrowserIntegrationCompatibility.protocolVersion)
    }

    @Test("browser integration compatibility rejects old versions and protocol drift")
    func browserIntegrationCompatibilityRejectsOldVersionsAndProtocolDrift() {
        #expect(BrowserIntegrationCompatibility.isVersion("v0.2.0", atLeast: "0.2.0"))
        #expect(BrowserIntegrationCompatibility.isVersion("0.10.0-beta", atLeast: "0.2.0"))
        #expect(!BrowserIntegrationCompatibility.isVersion("0.1.9", atLeast: "0.2.0"))

        let compatible = BrowserIntegrationCompatibility.extensionCompatibility(
            extensionVersion: "0.2.0",
            minimumNativeHostVersion: "0.2.0",
            protocolVersion: BrowserIntegrationCompatibility.protocolVersion,
            requiresExplicitVersion: true
        )
        #expect(compatible.compatible)

        let oldExtension = BrowserIntegrationCompatibility.extensionCompatibility(
            extensionVersion: "0.1.9",
            minimumNativeHostVersion: "0.2.0",
            protocolVersion: BrowserIntegrationCompatibility.protocolVersion,
            requiresExplicitVersion: true
        )
        #expect(!oldExtension.compatible)

        let protocolDrift = BrowserIntegrationCompatibility.extensionCompatibility(
            extensionVersion: "0.2.0",
            minimumNativeHostVersion: "0.2.0",
            protocolVersion: BrowserIntegrationCompatibility.protocolVersion + 1,
            requiresExplicitVersion: true
        )
        #expect(!protocolDrift.compatible)

        let missingExplicitVersion = BrowserIntegrationCompatibility.extensionCompatibility(
            extensionVersion: nil,
            minimumNativeHostVersion: "0.2.0",
            protocolVersion: BrowserIntegrationCompatibility.protocolVersion,
            requiresExplicitVersion: true
        )
        #expect(!missingExplicitVersion.compatible)
    }

    @Test("builds download deep links with browser takeover metadata")
    func buildsDownloadDeepLinksWithMetadata() throws {
        let expiresAt = Date(timeIntervalSince1970: 1_850_000_100)
        let handoffAck = NativeHandoffAck(
            requestID: "request-1",
            token: "secret-token",
            port: 49152,
            expiresAt: expiresAt
        )
        let url = try #require(DeepLinkBuilder.downloadURL(
            for: "https://example.com/file.dmg?token=a b",
            browser: "Chrome",
            suggestedFilename: "file.dmg",
            handoffSource: "download-takeover",
            sourcePageTitle: "Downloads",
            sourcePageUrl: "https://example.com",
            handoffAck: handoffAck
        ))

        let draft = try #require(DeepLinkParser.downloadDraft(from: url))

        #expect(draft.source == "https://example.com/file.dmg?token=a b")
        #expect(draft.browser == "Chrome")
        #expect(draft.suggestedFilename == "file.dmg")
        #expect(draft.handoffSource == "download-takeover")
        #expect(draft.isBrowserTakeover)
        #expect(draft.handoffAck == handoffAck)
        #expect(draft.isTrustedNativeHandoff)
        #expect(draft.requiresUserConfirmation == false)
        #expect(draft.browserContext?.originalURL == "https://example.com/file.dmg?token=a b")
    }

    @Test("download deep links preserve native handoff expiry")
    func downloadDeepLinksPreserveNativeHandoffExpiry() throws {
        let expiresAt = Date(timeIntervalSince1970: 1_850_000_000)
        let handoffAck = NativeHandoffAck(
            requestID: "request-1",
            token: "secret-token",
            port: 49152,
            expiresAt: expiresAt
        )
        let url = try #require(DeepLinkBuilder.downloadURL(
            for: "https://example.com/file.dmg",
            browser: "Chrome",
            handoffSource: "download-takeover",
            handoffAck: handoffAck
        ))

        let draft = try #require(DeepLinkParser.downloadDraft(from: url))

        #expect(draft.handoffAck == handoffAck)
        #expect(draft.handoffAck?.isExpired(now: expiresAt.addingTimeInterval(-1)) == false)
        #expect(draft.handoffAck?.isExpired(now: expiresAt) == true)
    }

    @Test("download deep links can require native payload source")
    func downloadDeepLinksCanRequireNativePayloadSource() throws {
        let handoffAck = NativeHandoffAck(
            requestID: "request-1",
            token: "secret-token",
            port: 49152,
            expiresAt: Date(timeIntervalSince1970: 1_850_000_100)
        )
        let previewSource = "https://example.com/preview.zip"
        let url = try #require(DeepLinkBuilder.downloadURL(
            for: previewSource,
            browser: "Chrome",
            handoffSource: "popup-scan",
            handoffAck: handoffAck,
            requiresPayloadSource: true
        ))

        let draft = try #require(DeepLinkParser.downloadDraft(from: url))

        #expect(draft.source == previewSource)
        #expect(draft.isTrustedNativeHandoff)
        #expect(draft.requiresNativePayloadSource)
        #expect(draft.requiresUserConfirmation == false)
    }

    @Test("trusted native payload source validation allows bounded multi-link sources")
    func trustedNativePayloadSourceValidationAllowsBoundedMultiLinkSources() {
        let source = (0..<DownloadDeepLinkPolicy.maximumTrustedPayloadTaskCount)
            .map { "https://example.com/file-\($0).zip" }
            .joined(separator: "\n")

        let validation = DownloadDeepLinkPolicy.validationForTrustedPayloadSource(source)

        #expect(validation?.linkTrust == .trustedNativeHandoff)
        #expect(validation?.sourceCount == DownloadDeepLinkPolicy.maximumTrustedPayloadTaskCount)
    }

    @Test("trusted native payload source validation rejects unsafe sources")
    func trustedNativePayloadSourceValidationRejectsUnsafeSources() {
        let tooManySources = (0...DownloadDeepLinkPolicy.maximumTrustedPayloadTaskCount)
            .map { "https://example.com/file-\($0).zip" }
            .joined(separator: "\n")
        let unsafeSources = [
            "https://example.com/file.zip\u{0000}",
            "https://example.com/file\u{202E}gpj.zip",
            "https://example.com/file.zip\njavascript:alert(1)",
            "https://example.com/file.zip\nswiftgetx://download?url=https://example.com/file.zip",
            tooManySources
        ]

        for source in unsafeSources {
            #expect(DownloadDeepLinkPolicy.validationForTrustedPayloadSource(source) == nil)
        }
    }

    @Test("public download deep links require confirmation and carry no browser context")
    func publicDownloadDeepLinksRequireConfirmation() throws {
        let url = try #require(DeepLinkBuilder.downloadURL(
            for: "https://example.com/file.zip",
            browser: "Chrome",
            suggestedFilename: "file.zip",
            sourcePageTitle: "Downloads",
            sourcePageUrl: "https://example.com"
        ))

        let draft = try #require(DeepLinkParser.downloadDraft(from: url))

        #expect(draft.source == "https://example.com/file.zip")
        #expect(draft.sourceCount == 1)
        #expect(draft.isTrustedNativeHandoff == false)
        #expect(draft.requiresUserConfirmation)
        #expect(draft.browserContext == nil)
    }

    @Test("public download deep links allow bounded multi-link confirmation")
    func publicDownloadDeepLinksAllowBoundedMultiLinkConfirmation() throws {
        let source = "https://example.com/one.zip\nhttps://example.com/two.zip"
        let url = try #require(downloadURL(source: source))

        let draft = try #require(DeepLinkParser.downloadDraft(from: url))

        #expect(draft.sourceCount == 2)
        #expect(draft.requiresUserConfirmation)
        #expect(draft.isTrustedNativeHandoff == false)
    }

    @Test("public local torrent deep links require confirmation")
    func publicLocalTorrentDeepLinksRequireConfirmation() throws {
        let localSources = [
            "file:///tmp/demo.torrent",
            "/tmp/demo.torrent"
        ]

        for source in localSources {
            let url = try #require(downloadURL(source: source))
            let draft = try #require(DeepLinkParser.downloadDraft(from: url))

            #expect(draft.source == source)
            #expect(draft.sourceCount == 1)
            #expect(draft.requiresUserConfirmation)
            #expect(draft.isTrustedNativeHandoff == false)
        }
    }

    @Test("trusted torrent deep links still require confirmation")
    func trustedTorrentDeepLinksStillRequireConfirmation() throws {
        let handoffAck = NativeHandoffAck(
            requestID: "request-1",
            token: "secret-token",
            port: 49152,
            expiresAt: Date(timeIntervalSince1970: 1_850_000_100)
        )
        let url = try #require(DeepLinkBuilder.downloadURL(
            for: "magnet:?xt=urn:btih:0123456789012345678901234567890123456789&dn=Demo",
            browser: "Chrome",
            handoffSource: "download-takeover",
            handoffAck: handoffAck
        ))

        let draft = try #require(DeepLinkParser.downloadDraft(from: url))

        #expect(draft.isTrustedNativeHandoff)
        #expect(draft.containsTorrentSource)
        #expect(draft.requiresUserConfirmation)
    }

    @Test("download deep links reject oversized payloads")
    func downloadDeepLinksRejectOversizedPayloads() throws {
        let source = "https://example.com/" + String(
            repeating: "a",
            count: DownloadDeepLinkPolicy.maximumURLLength
        )
        let url = try #require(downloadURL(source: source))

        #expect(DeepLinkParser.downloadDraft(from: url) == nil)
        #expect(DeepLinkParser.isDownloadURL(url))
    }

    @Test("public download deep links reject too many tasks")
    func publicDownloadDeepLinksRejectTooManyTasks() throws {
        let source = (0...DownloadDeepLinkPolicy.maximumPublicTaskCount)
            .map { "https://example.com/file-\($0).zip" }
            .joined(separator: "\n")
        let url = try #require(downloadURL(source: source))

        #expect(DeepLinkParser.downloadDraft(from: url) == nil)
        #expect(DeepLinkParser.isDownloadURL(url))
    }

    @Test("public download deep links reject dangerous sources")
    func publicDownloadDeepLinksRejectDangerousSources() throws {
        let dangerousSources = [
            "javascript:alert(1)",
            "data:text/plain,hello",
            "swiftgetx://download?url=https://example.com/file.zip"
        ]

        for source in dangerousSources {
            let url = try #require(downloadURL(source: source))
            #expect(DeepLinkParser.downloadDraft(from: url) == nil)
            #expect(DeepLinkParser.isDownloadURL(url))
        }
    }

    @Test("download deep links reject control characters")
    func downloadDeepLinksRejectControlCharacters() throws {
        let url = try #require(downloadURL(source: "https://example.com/file.zip\u{0000}"))

        #expect(DeepLinkParser.downloadDraft(from: url) == nil)
        #expect(DeepLinkParser.isDownloadURL(url))
    }

    @Test("download deep links reject bidi control characters")
    func downloadDeepLinksRejectBidiControlCharacters() throws {
        let url = try #require(downloadURL(source: "https://example.com/file\u{202E}gpj.zip"))

        #expect(DeepLinkParser.downloadDraft(from: url) == nil)
        #expect(DeepLinkParser.isDownloadURL(url))
    }

    @Test("native handoff without expiry is not trusted")
    func nativeHandoffWithoutExpiryIsNotTrusted() throws {
        let handoffAck = NativeHandoffAck(requestID: "request-1", token: "secret-token", port: 49152)
        let url = try #require(DeepLinkBuilder.downloadURL(
            for: "https://example.com/file.zip",
            browser: "Chrome",
            handoffSource: "download-takeover",
            handoffAck: handoffAck
        ))

        let draft = try #require(DeepLinkParser.downloadDraft(from: url))

        #expect(draft.handoffAck == nil)
        #expect(draft.handoffSource == nil)
        #expect(draft.isTrustedNativeHandoff == false)
        #expect(draft.requiresUserConfirmation)
        #expect(draft.browserContext == nil)
        #expect(draft.canAcknowledgeNativeHandoff == false)
    }

    @Test("complete ack metadata from known native source is trusted")
    func completeAckMetadataFromKnownNativeSourceIsTrusted() throws {
        let handoffAck = NativeHandoffAck(
            requestID: "request-1",
            token: "secret-token",
            port: 49152,
            expiresAt: Date(timeIntervalSince1970: 1_850_000_100)
        )
        let url = try #require(DeepLinkBuilder.downloadURL(
            for: "https://example.com/file.zip",
            browser: "Chrome",
            handoffSource: "context-menu-link",
            sourcePageTitle: "Downloads",
            sourcePageUrl: "https://example.com",
            handoffAck: handoffAck
        ))

        let draft = try #require(DeepLinkParser.downloadDraft(from: url))

        #expect(draft.handoffAck == handoffAck)
        #expect(draft.handoffSource == "context-menu-link")
        #expect(draft.sourcePageTitle == "Downloads")
        #expect(draft.sourcePageUrl == "https://example.com")
        #expect(draft.isTrustedNativeHandoff)
        #expect(draft.requiresUserConfirmation == false)
        #expect(draft.browserContext?.handoffSource == "context-menu-link")
        #expect(draft.canAcknowledgeNativeHandoff)
    }

    @Test("complete ack metadata from unknown source is stripped")
    func completeAckMetadataFromUnknownSourceIsStripped() throws {
        let handoffAck = NativeHandoffAck(
            requestID: "request-1",
            token: "secret-token",
            port: 49152,
            expiresAt: Date(timeIntervalSince1970: 1_850_000_100)
        )
        let url = try #require(DeepLinkBuilder.downloadURL(
            for: "https://example.com/file.zip",
            browser: "Chrome",
            handoffSource: "external-script",
            sourcePageTitle: "Downloads",
            sourcePageUrl: "https://example.com",
            handoffAck: handoffAck
        ))

        let draft = try #require(DeepLinkParser.downloadDraft(from: url))

        #expect(draft.handoffAck == nil)
        #expect(draft.handoffSource == nil)
        #expect(draft.sourcePageTitle == nil)
        #expect(draft.sourcePageUrl == nil)
        #expect(draft.isTrustedNativeHandoff == false)
        #expect(draft.requiresUserConfirmation)
        #expect(draft.browserContext == nil)
        #expect(draft.canAcknowledgeNativeHandoff == false)
    }

    @Test("expired native handoff is rejected rather than trusted")
    func expiredNativeHandoffIsRejectedRatherThanTrusted() throws {
        let handoffAck = NativeHandoffAck(
            requestID: "request-1",
            token: "secret-token",
            port: 49152,
            expiresAt: Date(timeIntervalSince1970: 1)
        )
        let url = try #require(DeepLinkBuilder.downloadURL(
            for: "https://example.com/file.zip",
            browser: "Chrome",
            handoffSource: "download-takeover",
            sourcePageTitle: "Downloads",
            sourcePageUrl: "https://example.com",
            handoffAck: handoffAck
        ))

        let draft = try #require(DeepLinkParser.downloadDraft(from: url))

        #expect(draft.handoffAck == handoffAck)
        #expect(draft.handoffSource == "download-takeover")
        #expect(draft.sourcePageTitle == nil)
        #expect(draft.sourcePageUrl == nil)
        #expect(draft.isTrustedNativeHandoff == false)
        #expect(draft.requiresUserConfirmation)
        #expect(draft.browserContext == nil)
        #expect(draft.canAcknowledgeNativeHandoff)

        let resolution = try #require(PendingNativeHandoffPolicy.expirationResolution(
            draft: draft,
            now: Date(timeIntervalSince1970: 2)
        ))
        #expect(resolution.handoff == handoffAck)
        #expect(resolution.decision.rejectedReason == "expired")
    }

    @Test("download deep links reject duplicate source parameters")
    func downloadDeepLinksRejectDuplicateSourceParameters() throws {
        let url = try #require(URL(
            string: "swiftgetx://download?url=https://example.com/one.zip&url=https://example.com/two.zip"
        ))

        #expect(DeepLinkParser.downloadDraft(from: url) == nil)
        #expect(DeepLinkParser.isDownloadURL(url))
    }

    @Test("ack server returns accepted decisions from app callback")
    func ackServerReturnsAcceptedDecisions() async throws {
        let server = try NativeHandoffAckServer.start()
        let waiter = Task.detached {
            server.waitForResult(timeout: 2)
        }

        let expected = NativeHandoffAckDecision.accepted(
            queued: true,
            requiresUserConfirmation: false,
            message: "queued"
        )
        try await NativeHandoffAckClient.acknowledge(expected, handoff: server.handoff)

        let decision = await waiter.value
        #expect(decision == expected)
    }

    @Test("ack server returns rejected decisions from user cancellation")
    func ackServerReturnsRejectedDecisions() async throws {
        let server = try NativeHandoffAckServer.start()
        let waiter = Task.detached {
            server.waitForResult(timeout: 2)
        }

        let expected = NativeHandoffAckDecision.rejected(
            reason: "userCancelled",
            requiresUserConfirmation: true,
            message: "cancelled"
        )
        try await NativeHandoffAckClient.acknowledge(expected, handoff: server.handoff)

        let decision = await waiter.value
        #expect(decision == expected)
    }

    @Test("handoff payload returns browser download context")
    func handoffPayloadReturnsBrowserDownloadContext() async throws {
        let context = BrowserDownloadContext(
            referrer: "https://example.com/downloads",
            userAgent: "Example Browser",
            method: "GET",
            headers: [
                BrowserDownloadHeader(name: "Authorization", value: "Bearer secret", sensitive: true),
                BrowserDownloadHeader(name: "Accept-Language", value: "en-US")
            ],
            finalURL: "https://cdn.example.com/file.zip",
            originalURL: "https://example.com/file.zip",
            suggestedFilename: "file.zip",
            sourcePageTitle: "Downloads",
            sourcePageURL: "https://example.com/downloads",
            handoffSource: "download-takeover",
            handoffSourceText: "https://example.com/file.zip\nhttps://example.com/other.zip"
        )
        let payload = try JSONEncoder().encode(context)
        let server = try NativeHandoffAckServer.start(payload: payload)
        defer { server.cancel() }

        let fetched = try await NativeHandoffPayloadClient.fetchContext(handoff: server.handoff)

        #expect(fetched == context)
    }

    @Test("browser context preserves multiline handoff source text")
    func browserContextPreservesMultilineHandoffSourceText() throws {
        let sourceText = "https://example.com/one.zip\nhttps://example.com/two.zip"
        let message = BrowserDownloadMessage(
            action: "download",
            url: sourceText,
            browser: "Chrome",
            suggestedFilename: "Downloads",
            sourcePageTitle: "Downloads",
            sourcePageUrl: "https://example.com/downloads",
            source: "popup-scan"
        )

        let context = try #require(BrowserDownloadContext.context(from: message))

        #expect(context.handoffSourceText == sourceText)
        #expect(context.originalURL == nil)
        #expect(context.sourcePageURL == "https://example.com/downloads")
        #expect(context.handoffSource == "popup-scan")
    }

    @Test("ack server times out when app never responds")
    func ackServerTimesOutWhenAppNeverResponds() throws {
        let server = try NativeHandoffAckServer.start()

        let decision = server.waitForResult(timeout: 0.05)

        #expect(decision.accepted == false)
        #expect(decision.queued == false)
        #expect(decision.requiresUserConfirmation == false)
        #expect(decision.rejectedReason == "timeout")
    }

    @Test("native handoff decision rejects empty task creation")
    func nativeHandoffDecisionRejectsEmptyTaskCreation() {
        let decision = NativeHandoffDecisionFactory.decision(
            queuedTaskCount: 0,
            requiresUserConfirmation: true
        )

        #expect(decision.accepted == false)
        #expect(decision.queued == false)
        #expect(decision.requiresUserConfirmation == true)
        #expect(decision.rejectedReason == "noDownloadableSources")
    }

    @Test("native handoff decision accepts queued tasks")
    func nativeHandoffDecisionAcceptsQueuedTasks() {
        let decision = NativeHandoffDecisionFactory.decision(
            queuedTaskCount: 2,
            requiresUserConfirmation: true
        )

        #expect(decision.accepted == true)
        #expect(decision.queued == true)
        #expect(decision.requiresUserConfirmation == true)
    }

    @Test("native handoff rejects browser POST and body replay")
    func nativeHandoffRejectsBrowserPOSTAndBodyReplay() throws {
        let draft = DownloadDraft(
            source: "https://example.com/export",
            handoffSource: "download-takeover",
            handoffAck: NativeHandoffAck(requestID: "request-1", token: "token", port: 49152),
            browserContext: BrowserDownloadContext(
                method: "POST",
                bodyMetadata: BrowserDownloadBodyMetadata(byteCount: 128, description: "form fields: 2")
            ),
            linkTrust: .trustedNativeHandoff
        )

        let decision = try #require(BrowserDownloadRecoveryPolicy.nativeHandoffRejection(for: draft))

        #expect(decision.accepted == false)
        #expect(decision.queued == false)
        #expect(decision.requiresUserConfirmation == true)
        #expect(decision.rejectedReason == "unsupportedRequestReplay")
        #expect(decision.message?.contains("POST") == true)
    }

    @Test("pending native handoff is rejected when expired")
    func pendingNativeHandoffIsRejectedWhenExpired() throws {
        let expiry = Date(timeIntervalSince1970: 1_850_000_000)
        let handoff = NativeHandoffAck(
            requestID: "request-1",
            token: "token-1",
            port: 49152,
            expiresAt: expiry
        )
        let draft = DownloadDraft(
            source: "https://example.com/file.zip",
            handoffSource: "download-takeover",
            handoffAck: handoff,
            linkTrust: .trustedNativeHandoff
        )

        #expect(
            PendingNativeHandoffPolicy.expirationResolution(
                draft: draft,
                now: expiry.addingTimeInterval(-1)
            ) == nil
        )

        let resolution = try #require(
            PendingNativeHandoffPolicy.expirationResolution(
                draft: draft,
                now: expiry
            )
        )

        #expect(resolution.handoff == handoff)
        #expect(resolution.decision.accepted == false)
        #expect(resolution.decision.requiresUserConfirmation == true)
        #expect(resolution.decision.rejectedReason == "expired")
    }

    @Test("pending native handoff is rejected when replaced")
    func pendingNativeHandoffIsRejectedWhenReplaced() throws {
        let expiresAt = Date(timeIntervalSince1970: 1_850_000_100)
        let currentHandoff = NativeHandoffAck(
            requestID: "request-1",
            token: "token-1",
            port: 49152,
            expiresAt: expiresAt
        )
        let incomingHandoff = NativeHandoffAck(
            requestID: "request-2",
            token: "token-2",
            port: 49153,
            expiresAt: expiresAt
        )
        let current = DownloadDraft(
            source: "https://example.com/one.zip",
            handoffSource: "download-takeover",
            handoffAck: currentHandoff,
            linkTrust: .trustedNativeHandoff
        )
        let incoming = DownloadDraft(
            source: "https://example.com/two.zip",
            handoffSource: "download-takeover",
            handoffAck: incomingHandoff,
            linkTrust: .trustedNativeHandoff
        )

        let resolution = try #require(
            PendingNativeHandoffPolicy.replacementResolution(
                current: current,
                incoming: incoming
            )
        )

        #expect(resolution.handoff == currentHandoff)
        #expect(resolution.decision.accepted == false)
        #expect(resolution.decision.requiresUserConfirmation == true)
        #expect(resolution.decision.rejectedReason == "supersededByNewRequest")
        #expect(
            PendingNativeHandoffPolicy.replacementResolution(
                current: current,
                incoming: current
            ) == nil
        )
    }

    @Test("parses browser setup deep links")
    func parsesBrowserSetupDeepLinks() throws {
        let url = try #require(URL(
            string: "swiftgetx://browser-setup?browser=Chrome&extensionID=bcdefghijklmnopabcdefghijklmnopa&version=0.2.0&protocolVersion=1&minimumNativeHostVersion=0.2.0"
        ))

        let request = try #require(DeepLinkParser.browserSetupRequest(from: url))

        #expect(request.browser == "Chrome")
        #expect(request.extensionID == "bcdefghijklmnopabcdefghijklmnopa")
        #expect(request.version == "0.2.0")
        #expect(request.protocolVersion == BrowserIntegrationCompatibility.protocolVersion)
        #expect(request.minimumNativeHostVersion == "0.2.0")
    }

    @Test("rejects invalid browser setup extension IDs")
    func rejectsInvalidBrowserSetupExtensionIDs() throws {
        let url = try #require(URL(
            string: "swiftgetx://browser-setup?browser=Chrome&extensionID=not-valid&version=0.2.0"
        ))

        #expect(DeepLinkParser.browserSetupRequest(from: url) == nil)
    }

    private func encodeMessage(_ message: BrowserDownloadMessage) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        var length = UInt32(payload.count).littleEndian
        var data = Data(bytes: &length, count: 4)
        data.append(payload)
        return data
    }

    private func downloadURL(source: String) -> URL? {
        var components = URLComponents()
        components.scheme = "swiftgetx"
        components.host = "download"
        components.queryItems = [
            URLQueryItem(name: "url", value: source)
        ]
        return components.url
    }
}
