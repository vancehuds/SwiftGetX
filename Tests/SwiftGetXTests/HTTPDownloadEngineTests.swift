import Foundation
import Network
import Testing
@testable import SwiftGetX

@Suite("HTTPDownloadEngine")
@MainActor
struct HTTPDownloadEngineTests {
    @Test("downloads ranged content with segmented engine")
    func downloadsSegmentedContent() async throws {
        let payload = Data((0..<32_768).map { UInt8($0 % 251) })
        let server = try RangeTestServer(payload: payload)
        try await server.start()
        defer {
            server.stop()
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let destination = directory.appendingPathComponent("payload.bin")
        let request = DownloadRequest(
            id: UUID(),
            name: "payload.bin",
            source: server.url.absoluteString,
            kind: .http,
            savePath: destination.path,
            totalBytes: 0,
            downloadedBytes: 0,
            supportsResume: false,
            eTag: nil,
            lastModified: nil,
            selectedFileIndexes: []
        )

        let engine = HTTPDownloadEngine()
        engine.configure(segmentCount: 4, retryLimit: 0)
        await engine.start(request)

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
    }
}

private final class RangeTestServer: @unchecked Sendable {
    private let payload: Data
    private let listener: NWListener
    private let queue = DispatchQueue(label: "SwiftGetX.RangeTestServer")

    var url: URL {
        URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/payload.bin")!
    }

    init(payload: Data) throws {
        self.payload = payload
        listener = try NWListener(using: .tcp, on: 0)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [payload] connection in
                connection.start(queue: self.queue)
                Self.receiveRequest(on: connection) { request in
                    let response = Self.response(for: request, payload: payload)
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private static func receiveRequest(on connection: NWConnection, completion: @escaping @Sendable (String) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
            completion(String(data: data ?? Data(), encoding: .utf8) ?? "")
        }
    }

    private static func response(for request: String, payload: Data) -> Data {
        if request.hasPrefix("HEAD") {
            return httpResponse(
                status: "200 OK",
                headers: [
                    "Content-Length": "\(payload.count)",
                    "Accept-Ranges": "bytes",
                    "ETag": "\"test\""
                ],
                body: Data()
            )
        }

        let range = parseRange(from: request, payloadCount: payload.count)
        let body = payload.subdata(in: range)
        return httpResponse(
            status: range.count == payload.count ? "200 OK" : "206 Partial Content",
            headers: [
                "Content-Length": "\(body.count)",
                "Accept-Ranges": "bytes",
                "Content-Range": "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(payload.count)",
                "ETag": "\"test\""
            ],
            body: body
        )
    }

    private static func parseRange(from request: String, payloadCount: Int) -> Range<Int> {
        guard let rangeLine = request
            .components(separatedBy: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("range: bytes=") })
        else {
            return 0..<payloadCount
        }

        let rawRange = rangeLine
            .replacingOccurrences(of: "Range: bytes=", with: "")
            .replacingOccurrences(of: "range: bytes=", with: "")
        let parts = rawRange.split(separator: "-", maxSplits: 1).map(String.init)
        let start = Int(parts.first ?? "0") ?? 0
        let end = Int(parts.dropFirst().first ?? "") ?? (payloadCount - 1)
        return start..<(min(end, payloadCount - 1) + 1)
    }

    private static func httpResponse(status: String, headers: [String: String], body: Data) -> Data {
        var lines = ["HTTP/1.1 \(status)"]
        lines.append(contentsOf: headers.map { "\($0.key): \($0.value)" })
        lines.append("Connection: close")
        lines.append("")
        lines.append("")
        var data = lines.joined(separator: "\r\n").data(using: .utf8)!
        data.append(body)
        return data
    }
}
