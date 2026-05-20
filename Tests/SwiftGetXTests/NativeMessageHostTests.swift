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
            NativeMessageResponse(ok: true, message: "accepted")
        )

        let payloadLength = encoded.prefix(4).withUnsafeBytes { pointer in
            pointer.load(as: UInt32.self).littleEndian
        }

        #expect(Int(payloadLength) == encoded.count - 4)
    }

    private func encodeMessage(_ message: BrowserDownloadMessage) throws -> Data {
        let payload = try JSONEncoder().encode(message)
        var length = UInt32(payload.count).littleEndian
        var data = Data(bytes: &length, count: 4)
        data.append(payload)
        return data
    }
}
