import Foundation
import Network
import Testing
@testable import SwiftGetX

@Suite("HTTPDownloadEngine")
@MainActor
struct HTTPDownloadEngineTests {
    @Test("downloads ranged content with segmented engine")
    func downloadsSegmentedContent() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        let engine = HTTPDownloadEngine()
        engine.configure(segmentCount: 4, retryLimit: 0)
        await engine.start(Self.request(source: server.url, destination: destination))

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".segments"))
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".part0"))
    }

    @Test("resumes single part downloads")
    func resumesSinglePartDownloads() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        try payload.subdata(in: 0..<4096).write(to: URL(fileURLWithPath: destination.path + ".part"))

        let engine = HTTPDownloadEngine()
        engine.configure(segmentCount: 1, retryLimit: 0)
        await engine.start(Self.request(
            source: server.url,
            destination: destination,
            totalBytes: Int64(payload.count),
            downloadedBytes: 4096,
            supportsResume: true,
            eTag: "\"test\""
        ))

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".part"))
    }

    @Test("redownloads single part content when server ignores range")
    func redownloadsSinglePartContentWhenServerIgnoresRange() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload, behavior: .ignoreRange)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        try payload.subdata(in: 0..<4096).write(to: URL(fileURLWithPath: destination.path + ".part"))

        let engine = HTTPDownloadEngine()
        engine.configure(segmentCount: 1, retryLimit: 0)
        await engine.start(Self.request(
            source: server.url,
            destination: destination,
            totalBytes: Int64(payload.count),
            downloadedBytes: 4096,
            supportsResume: true,
            eTag: "\"test\""
        ))

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
    }

    @Test("retries transient server failures")
    func retriesTransientServerFailures() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload, behavior: .failFirstGET(status: 500))
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        let recorder = SnapshotRecorder()
        let engine = HTTPDownloadEngine()
        engine.onSnapshot = { snapshot in
            recorder.append(snapshot)
        }
        engine.configure(segmentCount: 1, retryLimit: 1)
        await engine.start(Self.request(source: server.url, destination: destination))

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(recorder.snapshots.contains { $0.retryCount == 1 })
    }

    @Test("resumes legacy segment files without manifest")
    func resumesLegacySegmentFilesWithoutManifest() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        let plan = SegmentPlan.make(totalBytes: Int64(payload.count), segmentCount: 4)
        for segment in plan.segments {
            let keptLength = max(1, Int(segment.length / 2))
            let range = Int(segment.start)..<(Int(segment.start) + keptLength)
            try payload.subdata(in: range).write(to: URL(fileURLWithPath: destination.path + ".part\(segment.index)"))
        }

        let engine = HTTPDownloadEngine()
        engine.configure(segmentCount: 4, retryLimit: 0)
        await engine.start(Self.request(
            source: server.url,
            destination: destination,
            totalBytes: Int64(payload.count),
            downloadedBytes: Int64(payload.count / 2),
            supportsResume: true,
            eTag: "\"test\""
        ))

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".segments"))
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".part0"))
    }

    @Test("fails safely when segmented server ignores range")
    func failsSafelyWhenSegmentedServerIgnoresRange() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload, behavior: .ignoreRange)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        let recorder = SnapshotRecorder()
        let engine = HTTPDownloadEngine()
        engine.onSnapshot = { snapshot in
            recorder.append(snapshot)
        }
        engine.configure(segmentCount: 4, retryLimit: 0)
        await engine.start(Self.request(source: server.url, destination: destination))

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(FileManager.default.fileExists(atPath: destination.path + ".segments"))
        #expect(recorder.snapshots.last?.status == .failed)
    }

    @Test("fails safely when content range mismatches")
    func failsSafelyWhenContentRangeMismatches() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload, behavior: .mismatchedContentRange)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        let recorder = SnapshotRecorder()
        let engine = HTTPDownloadEngine()
        engine.onSnapshot = { snapshot in
            recorder.append(snapshot)
        }
        engine.configure(segmentCount: 4, retryLimit: 0)
        await engine.start(Self.request(source: server.url, destination: destination))

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(FileManager.default.fileExists(atPath: destination.path + ".segments"))
        #expect(recorder.snapshots.last?.status == .failed)
    }

    @Test("does not merge when validators change during ranged response")
    func doesNotMergeWhenValidatorsChangeDuringRangedResponse() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload, behavior: .changingGETValidator)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        let recorder = SnapshotRecorder()
        let engine = HTTPDownloadEngine()
        engine.onSnapshot = { snapshot in
            recorder.append(snapshot)
        }
        engine.configure(segmentCount: 4, retryLimit: 0)
        await engine.start(Self.request(source: server.url, destination: destination))

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(FileManager.default.fileExists(atPath: destination.path + ".segments"))
        #expect(recorder.snapshots.last?.status == .failed)
    }

    private static func payload() -> Data {
        Data((0..<32_768).map { UInt8($0 % 251) })
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func request(
        source: URL,
        destination: URL,
        totalBytes: Int64 = 0,
        downloadedBytes: Int64 = 0,
        supportsResume: Bool = false,
        eTag: String? = nil,
        lastModified: String? = nil
    ) -> DownloadRequest {
        DownloadRequest(
            id: UUID(),
            name: destination.lastPathComponent,
            source: source.absoluteString,
            kind: .http,
            savePath: destination.path,
            totalBytes: totalBytes,
            downloadedBytes: downloadedBytes,
            supportsResume: supportsResume,
            eTag: eTag,
            lastModified: lastModified,
            selectedFileIndexes: []
        )
    }
}

private final class SnapshotRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [DownloadSnapshot]()

    var snapshots: [DownloadSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func append(_ snapshot: DownloadSnapshot) {
        lock.lock()
        values.append(snapshot)
        lock.unlock()
    }
}

private final class RangeTestServer: @unchecked Sendable {
    enum Behavior: Equatable, Sendable {
        case normal
        case failFirstGET(status: Int)
        case ignoreRange
        case mismatchedContentRange
        case changingGETValidator
    }

    private let payload: Data
    private let behavior: Behavior
    private let listener: NWListener
    private let queue = DispatchQueue(label: "SwiftGetX.RangeTestServer")
    private let lock = NSLock()
    private var getCount = 0

    var url: URL {
        URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/payload.bin")!
    }

    init(payload: Data, behavior: Behavior = .normal) throws {
        self.payload = payload
        self.behavior = behavior
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
            listener.newConnectionHandler = { connection in
                connection.start(queue: self.queue)
                Self.receiveRequest(on: connection) { request in
                    let response = self.response(for: request)
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

    private func response(for request: String) -> Data {
        if request.hasPrefix("HEAD") {
            return Self.httpResponse(
                status: "200 OK",
                headers: baseHeaders(contentLength: payload.count, eTag: "\"test\""),
                body: Data()
            )
        }

        lock.lock()
        getCount += 1
        let currentGETCount = getCount
        lock.unlock()

        if case .failFirstGET(let status) = behavior, currentGETCount == 1 {
            return Self.httpResponse(
                status: "\(status) Server Error",
                headers: baseHeaders(contentLength: 0, eTag: "\"test\""),
                body: Data()
            )
        }

        let requestedRange = Self.parseRange(from: request, payloadCount: payload.count)
        let hasRange = requestedRange != nil

        if behavior == .ignoreRange, hasRange {
            return Self.httpResponse(
                status: "200 OK",
                headers: baseHeaders(contentLength: payload.count, eTag: "\"test\""),
                body: payload
            )
        }

        let range = requestedRange ?? 0..<payload.count
        let body = payload.subdata(in: range)
        let eTag = behavior == .changingGETValidator ? "\"changed\"" : "\"test\""
        let contentRangeStart = behavior == .mismatchedContentRange && hasRange
            ? min(range.lowerBound + 1, range.upperBound - 1)
            : range.lowerBound

        var headers = baseHeaders(contentLength: body.count, eTag: eTag)
        if hasRange {
            headers["Content-Range"] = "bytes \(contentRangeStart)-\(range.upperBound - 1)/\(payload.count)"
        }

        return Self.httpResponse(
            status: hasRange ? "206 Partial Content" : "200 OK",
            headers: headers,
            body: body
        )
    }

    private func baseHeaders(contentLength: Int, eTag: String) -> [String: String] {
        [
            "Content-Length": "\(contentLength)",
            "Accept-Ranges": "bytes",
            "ETag": eTag
        ]
    }

    private static func parseRange(from request: String, payloadCount: Int) -> Range<Int>? {
        guard let rangeLine = request
            .components(separatedBy: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("range: bytes=") })
        else {
            return nil
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
