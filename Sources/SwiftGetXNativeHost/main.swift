import AppKit
import Foundation
import SwiftGetXCore

let nativeHostVersion = BrowserIntegrationCompatibility.nativeHostVersion
let nativeHandoffAckTimeout: TimeInterval = 60
let nativeDeepLinkSourceLengthLimit = 6 * 1_024
let nativeMaximumPublicTaskCount = 20

do {
    guard let message = try NativeMessageHost.readMessage() else {
        throw NativeHostError.emptyInput
    }

    switch message.action {
    case "ping":
        let compatibility = BrowserIntegrationCompatibility.extensionCompatibility(
            extensionVersion: message.extensionVersion,
            minimumNativeHostVersion: message.minimumNativeHostVersion,
            protocolVersion: message.protocolVersion,
            requiresExplicitVersion: false
        )
        let response = NativeMessageResponse(
            ok: compatibility.compatible,
            message: compatibility.compatible
                ? "SwiftGetX native host is running"
                : (compatibility.message ?? "SwiftGetX browser integration is incompatible"),
            version: nativeHostVersion,
            protocolVersion: BrowserIntegrationCompatibility.protocolVersion,
            minimumExtensionVersion: BrowserIntegrationCompatibility.minimumChromeExtensionVersion,
            minimumNativeHostVersion: BrowserIntegrationCompatibility.minimumNativeHostVersion,
            compatible: compatibility.compatible,
            compatibilityMessage: compatibility.message
        )
        FileHandle.standardOutput.write(try NativeMessageHost.encodeResponse(response))

    case "download":
        let compatibility = BrowserIntegrationCompatibility.extensionCompatibility(
            extensionVersion: message.extensionVersion,
            minimumNativeHostVersion: message.minimumNativeHostVersion,
            protocolVersion: message.protocolVersion,
            requiresExplicitVersion: true
        )
        guard compatibility.compatible else {
            throw NativeHostError.incompatible(compatibility.message ?? "SwiftGetX browser integration is incompatible")
        }

        guard let source = message.url, !source.isEmpty else {
            throw NativeHostError.invalidDownloadSource
        }

        let handoffSource = message.source ?? "native-host"
        let context = BrowserDownloadContext.context(from: message) ?? BrowserDownloadContext(
            originalURL: source,
            suggestedFilename: message.suggestedFilename,
            sourcePageTitle: message.sourcePageTitle,
            sourcePageURL: message.sourcePageUrl,
            handoffSource: handoffSource,
            handoffSourceText: source
        )
        let payload = try JSONEncoder().encode(context)
        let ackServer = try NativeHandoffAckServer.start(
            payload: payload,
            expiresAt: Date().addingTimeInterval(nativeHandoffAckTimeout)
        )
        let deepLinkSource = deepLinkSource(for: source)
        guard let url = DeepLinkBuilder.downloadURL(
            for: deepLinkSource.source,
            browser: message.browser,
            suggestedFilename: message.suggestedFilename,
            handoffSource: handoffSource,
            sourcePageTitle: message.sourcePageTitle,
            sourcePageUrl: message.sourcePageUrl,
            handoffAck: ackServer.handoff,
            requiresPayloadSource: deepLinkSource.requiresPayload
        ) else {
            ackServer.cancel()
            throw NativeHostError.invalidDownloadSource
        }

        guard NSWorkspace.shared.open(url) else {
            ackServer.cancel()
            throw NativeHostError.openFailed
        }

        let decision = ackServer.waitForResult(timeout: nativeHandoffAckTimeout)
        let response = NativeMessageResponse(
            ok: decision.accepted,
            message: decision.message ?? responseMessage(for: decision),
            version: nativeHostVersion,
            accepted: decision.accepted,
            queued: decision.queued,
            requiresUserConfirmation: decision.requiresUserConfirmation,
            rejectedReason: decision.rejectedReason,
            requestID: ackServer.handoff.requestID,
            protocolVersion: BrowserIntegrationCompatibility.protocolVersion,
            minimumExtensionVersion: BrowserIntegrationCompatibility.minimumChromeExtensionVersion,
            minimumNativeHostVersion: BrowserIntegrationCompatibility.minimumNativeHostVersion,
            compatible: true,
            compatibilityMessage: compatibility.message
        )
        FileHandle.standardOutput.write(try NativeMessageHost.encodeResponse(response))

    default:
        throw NativeHostError.unsupportedAction(message.action)
    }
} catch {
    let isCompatibilityFailure = (error as? NativeHostError)?.isCompatibilityFailure == true
    let response = NativeMessageResponse(
        ok: false,
        message: error.localizedDescription,
        version: nativeHostVersion,
        protocolVersion: BrowserIntegrationCompatibility.protocolVersion,
        minimumExtensionVersion: BrowserIntegrationCompatibility.minimumChromeExtensionVersion,
        minimumNativeHostVersion: BrowserIntegrationCompatibility.minimumNativeHostVersion,
        compatible: isCompatibilityFailure ? false : true,
        compatibilityMessage: isCompatibilityFailure ? error.localizedDescription : nil
    )
    if let data = try? NativeMessageHost.encodeResponse(response) {
        FileHandle.standardOutput.write(data)
    }
}

private func deepLinkSource(for source: String) -> (source: String, requiresPayload: Bool) {
    let candidates = sourceCandidates(in: source)
    let requiresPayload = source.utf8.count > nativeDeepLinkSourceLengthLimit
        || source.contains(where: \.isNewline)
        || candidates.count > nativeMaximumPublicTaskCount

    guard requiresPayload else {
        return (source, false)
    }

    let placeholder = "https://swiftgetx.local/native-payload"
    let safePreview = candidates.first { $0.utf8.count <= nativeDeepLinkSourceLengthLimit }
    return (safePreview ?? placeholder, true)
}

private func sourceCandidates(in source: String) -> [String] {
    guard let regex = try? NSRegularExpression(
        pattern: #"(?i)(magnet:\?[^\s<>\]]+|https?://[^\s<>\]]+|[^\s<>\]]+\.torrent(?:[?#][^\s<>\]]*)?)"#
    ) else {
        return []
    }

    let nsSource = source as NSString
    let range = NSRange(location: 0, length: nsSource.length)
    var candidates = [String]()
    var seen = Set<String>()
    for match in regex.matches(in: source, range: range) {
        let candidate = nsSource.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !seen.contains(candidate) else { continue }
        seen.insert(candidate)
        candidates.append(candidate)
    }
    return candidates
}

private func responseMessage(for decision: NativeHandoffAckDecision) -> String {
    if decision.accepted {
        return decision.requiresUserConfirmation
            ? "SwiftGetX accepted the confirmed download"
            : "SwiftGetX accepted and queued the download"
    }

    switch decision.rejectedReason {
    case "userCancelled":
        return "SwiftGetX download was cancelled by the user"
    case "timeout":
        return "SwiftGetX did not confirm the download before timeout"
    default:
        return "SwiftGetX rejected the download"
    }
}

private enum NativeHostError: LocalizedError {
    case emptyInput
    case unsupportedAction(String)
    case invalidDownloadSource
    case openFailed
    case incompatible(String)

    var isCompatibilityFailure: Bool {
        if case .incompatible = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Native host received no message"
        case .unsupportedAction(let action):
            return "Unsupported native message action: \(action)"
        case .invalidDownloadSource:
            return "Invalid download source"
        case .openFailed:
            return "Unable to open SwiftGetX download URL"
        case .incompatible(let message):
            return message
        }
    }
}
