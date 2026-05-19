import AppKit
import Foundation
import SwiftGetXCore

let input = FileHandle.standardInput.readDataToEndOfFile()

do {
    let messages = try NativeMessageHost.decodeMessages(from: input)
    var accepted = 0

    for message in messages where message.action == "download" {
        guard let url = DeepLinkBuilder.downloadURL(for: message.url) else { continue }
        NSWorkspace.shared.open(url)
        accepted += 1
    }

    let response = NativeMessageResponse(
        ok: accepted > 0,
        message: accepted > 0 ? "accepted \(accepted) download(s)" : "no supported messages"
    )
    FileHandle.standardOutput.write(try NativeMessageHost.encodeResponse(response))
} catch {
    let response = NativeMessageResponse(
        ok: false,
        message: error.localizedDescription
    )
    if let data = try? NativeMessageHost.encodeResponse(response) {
        FileHandle.standardOutput.write(data)
    }
}
