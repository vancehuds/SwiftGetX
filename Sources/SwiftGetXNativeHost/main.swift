import AppKit
import Foundation
import SwiftGetXCore

let nativeHostVersion = "0.2.0"

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

        guard let url = DeepLinkBuilder.downloadURL(for: source) else {
            throw NativeHostError.invalidDownloadSource
        }

        guard NSWorkspace.shared.open(url) else {
            throw NativeHostError.openFailed
        }

        let response = NativeMessageResponse(
            ok: true,
            message: "accepted download",
            version: nativeHostVersion
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

