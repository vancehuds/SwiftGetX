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

    @Test("encodes length-prefixed response")
    func encodesResponse() throws {
        let encoded = try NativeMessageHost.encodeResponse(
            NativeMessageResponse(ok: true, message: "accepted")
        )

        let payloadLength = encoded.prefix(4).withUnsafeBytes { pointer in
            pointer.load(as: UInt32.self).littleEndian
        }

        #expect(Int(payloadLength) == encoded.count - 4)
    }
}
