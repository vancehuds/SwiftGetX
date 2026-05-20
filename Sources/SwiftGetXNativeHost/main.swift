import AppKit
import Foundation
import SwiftGetXCore

let nativeHostVersion = "0.2.0"
let nativeHandoffAckTimeout: TimeInterval = 60

do {
    guard let message = try NativeMessageHost.readMessage() else {
        throw NativeHostError.emptyInput
    }

    switch message.action {
    case "ping":
        let response = NativeMessageResponse(
            ok: true,
            message: "SwiftGetX native host is running",
            version: nativeHostVersion
        )
        FileHandle.standardOutput.write(try NativeMessageHost.encodeResponse(response))

    case "download":
        guard let source = message.url, !source.isEmpty else {
            throw NativeHostError.invalidDownloadSource
        }

        let ackServer = try NativeHandoffAckServer.start()
        guard let url = DeepLinkBuilder.downloadURL(
            for: source,
            browser: message.browser,
            suggestedFilename: message.suggestedFilename,
            handoffSource: message.source,
            sourcePageTitle: message.sourcePageTitle,
            sourcePageUrl: message.sourcePageUrl,
            handoffAck: ackServer.handoff
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
            requestID: ackServer.handoff.requestID
        )
        FileHandle.standardOutput.write(try NativeMessageHost.encodeResponse(response))

    default:
        throw NativeHostError.unsupportedAction(message.action)
    }
} catch {
    let response = NativeMessageResponse(
        ok: false,
        message: error.localizedDescription
    )
    if let data = try? NativeMessageHost.encodeResponse(response) {
        FileHandle.standardOutput.write(data)
    }
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
        }
    }
}
