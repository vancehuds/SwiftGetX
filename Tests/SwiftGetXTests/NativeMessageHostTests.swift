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
                requestID: "request-1"
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
    }

    @Test("builds download deep links with browser takeover metadata")
    func buildsDownloadDeepLinksWithMetadata() throws {
        let handoffAck = NativeHandoffAck(requestID: "request-1", token: "secret-token", port: 49152)
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
            handoffSource: "download-takeover"
        )
        let payload = try JSONEncoder().encode(context)
        let server = try NativeHandoffAckServer.start(payload: payload)
        defer { server.cancel() }

        let fetched = try await NativeHandoffPayloadClient.fetchContext(handoff: server.handoff)

        #expect(fetched == context)
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
            handoffAck: handoff
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
        let currentHandoff = NativeHandoffAck(
            requestID: "request-1",
            token: "token-1",
            port: 49152
        )
        let incomingHandoff = NativeHandoffAck(
            requestID: "request-2",
            token: "token-2",
            port: 49153
        )
        let current = DownloadDraft(
            source: "https://example.com/one.zip",
            handoffSource: "download-takeover",
            handoffAck: currentHandoff
        )
        let incoming = DownloadDraft(
            source: "https://example.com/two.zip",
            handoffSource: "download-takeover",
            handoffAck: incomingHandoff
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
            string: "swiftgetx://browser-setup?browser=Chrome&extensionID=bcdefghijklmnopabcdefghijklmnopa&version=0.2.0"
        ))

        let request = try #require(DeepLinkParser.browserSetupRequest(from: url))

        #expect(request.browser == "Chrome")
        #expect(request.extensionID == "bcdefghijklmnopabcdefghijklmnopa")
        #expect(request.version == "0.2.0")
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
}
