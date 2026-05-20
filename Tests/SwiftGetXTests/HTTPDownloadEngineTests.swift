import Foundation
import Network
import Testing
@testable import SwiftGetX
@testable import SwiftGetXCore

@Suite("HTTPDownloadEngine")
@MainActor
struct HTTPDownloadEngineTests {
    @Test("downloads ranged content with segmented engine")
    func downloadsSegmentedContent() async throws {
        let payload = Self.largePayload()
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

    @Test("keeps HTTP on one stream when multithreading is disabled")
    func keepsHTTPOnOneStreamWhenMultithreadingIsDisabled() async throws {
        let payload = Self.largePayload()
        let server = try RangeTestServer(payload: payload)
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
        engine.configure(
            multithreadingEnabled: false,
            segmentCount: 8,
            hidesTemporaryFiles: true,
            retryLimit: 0
        )
        await engine.start(Self.request(source: server.url, destination: destination))

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".segments"))
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".part0"))
        #expect(recorder.snapshots.contains {
            $0.connectionSummary == L10n.string(
                "http_connection_summary",
                L10n.string("http_connection_single_stream"),
                L10n.string("http_connection_resumable")
            )
        })
    }

    @Test("keeps small ranged downloads on a single stream")
    func keepsSmallRangedDownloadsSingleStream() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload)
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
        engine.configure(segmentCount: 8, retryLimit: 0)
        await engine.start(Self.request(source: server.url, destination: destination))

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(recorder.snapshots.contains {
            $0.connectionSummary == L10n.string(
                "http_connection_summary",
                L10n.string("http_connection_single_stream"),
                L10n.string("http_connection_resumable")
            )
        })
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

    @Test("redownloads oversized single part temp file")
    func redownloadsOversizedSinglePartTempFile() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        try Data(repeating: 7, count: payload.count + 128)
            .write(to: URL(fileURLWithPath: destination.path + ".part"))

        let engine = HTTPDownloadEngine()
        engine.configure(segmentCount: 1, retryLimit: 0)
        await engine.start(Self.request(
            source: server.url,
            destination: destination,
            totalBytes: Int64(payload.count),
            downloadedBytes: Int64(payload.count + 128),
            supportsResume: true,
            eTag: "\"test\""
        ))

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".part"))
    }

    @Test("finalizes single part temp file when it already matches known size")
    func finalizesSinglePartTempFileWhenItAlreadyMatchesKnownSize() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        try payload.write(to: URL(fileURLWithPath: destination.path + ".part"))

        let engine = HTTPDownloadEngine()
        engine.configure(segmentCount: 1, retryLimit: 0)
        await engine.start(Self.request(
            source: server.url,
            destination: destination,
            totalBytes: Int64(payload.count),
            downloadedBytes: Int64(payload.count),
            supportsResume: true,
            eTag: "\"test\""
        ))

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".part"))
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
        let payload = Self.largePayload()
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

    @Test("recovers from corrupt segment manifest")
    func recoversFromCorruptSegmentManifest() async throws {
        let payload = Self.largePayload()
        let server = try RangeTestServer(payload: payload)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        let plan = SegmentPlan.make(totalBytes: Int64(payload.count), segmentCount: 4)
        for segment in plan.segments {
            let keptLength = max(1, Int(segment.length / 3))
            let range = Int(segment.start)..<(Int(segment.start) + keptLength)
            try payload.subdata(in: range).write(to: URL(fileURLWithPath: destination.path + ".part\(segment.index)"))
        }
        try Data("{broken".utf8).write(to: URL(fileURLWithPath: destination.path + ".segments"))

        let engine = HTTPDownloadEngine()
        engine.configure(segmentCount: 4, retryLimit: 0)
        await engine.start(Self.request(
            source: server.url,
            destination: destination,
            totalBytes: Int64(payload.count),
            downloadedBytes: Int64(payload.count / 3),
            supportsResume: true,
            eTag: "\"test\""
        ))

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".segments"))
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".part0"))
    }

    @Test("redownloads oversized segment temp file")
    func redownloadsOversizedSegmentTempFile() async throws {
        let payload = Self.largePayload()
        let server = try RangeTestServer(payload: payload)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        let plan = SegmentPlan.make(totalBytes: Int64(payload.count), segmentCount: 4)
        for segment in plan.segments {
            let length = Int(segment.index == 0 ? segment.length + 64 : max(1, segment.length / 2))
            let range = Int(segment.start)..<min(Int(segment.start) + length, payload.count)
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

    @Test("falls back to single stream when segmented server ignores range")
    func fallsBackToSingleStreamWhenSegmentedServerIgnoresRange() async throws {
        let payload = Self.largePayload()
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

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".segments"))
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".part0"))
        #expect(recorder.snapshots.contains {
            $0.connectionSummary == L10n.string(
                "http_connection_summary",
                L10n.string("http_connection_single_stream"),
                L10n.string("http_connection_not_resumable")
            )
        })
    }

    @Test("falls back to single stream when segmented server rejects range")
    func fallsBackToSingleStreamWhenSegmentedServerRejectsRange() async throws {
        let payload = Self.largePayload()
        let server = try RangeTestServer(payload: payload, behavior: .rejectRangeRequests)
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

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".segments"))
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".part0"))
        #expect(recorder.snapshots.contains {
            $0.connectionSummary == L10n.string(
                "http_connection_summary",
                L10n.string("http_connection_single_stream"),
                L10n.string("http_connection_not_resumable")
            )
        })
    }

    @Test("fails safely when content range mismatches")
    func failsSafelyWhenContentRangeMismatches() async throws {
        let payload = Self.largePayload()
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
        let payload = Self.largePayload()
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

    @Test("falls back to range probe when HEAD omits range metadata")
    func fallsBackToRangeProbeWhenHEADOmitsRangeMetadata() async throws {
        let payload = Self.largePayload()
        let server = try RangeTestServer(payload: payload, behavior: .headWithoutRangeMetadata)
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

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(recorder.snapshots.contains {
            $0.connectionSummary == L10n.string(
                "http_connection_summary",
                L10n.string("http_connection_segments", 4),
                L10n.string("http_connection_resumable")
            )
        })
    }

    @Test("falls back to range probe when HEAD omits content length")
    func fallsBackToRangeProbeWhenHEADOmitsContentLength() async throws {
        let payload = Self.largePayload()
        let server = try RangeTestServer(payload: payload, behavior: .headWithoutContentLength)
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

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(recorder.snapshots.contains {
            $0.totalBytes == Int64(payload.count)
                && $0.connectionSummary == L10n.string(
                    "http_connection_summary",
                    L10n.string("http_connection_segments", 4),
                    L10n.string("http_connection_resumable")
                )
        })
    }

    @Test("retries an individual ranged segment")
    func retriesIndividualRangedSegment() async throws {
        let payload = Self.largePayload()
        let server = try RangeTestServer(payload: payload, behavior: .failFirstRangedGET(status: 500))
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
        engine.configure(segmentCount: 4, retryLimit: 1)
        await engine.start(Self.request(source: server.url, destination: destination))

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(recorder.snapshots.contains { $0.retryCount == 1 })
    }

    @Test("removes partial HTTP data when deleting unfinished task")
    func removesPartialHTTPDataWhenDeletingUnfinishedTask() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        try Data("{}".utf8)
            .write(to: URL(fileURLWithPath: destination.path + ".segments"))
        try Data(repeating: 1, count: 1024)
            .write(to: URL(fileURLWithPath: destination.path + ".part0"))
        try Data(repeating: 2, count: 1024)
            .write(to: URL(fileURLWithPath: destination.path + ".part1"))

        let engine = HTTPDownloadEngine()
        await engine.remove(Self.request(
            source: URL(string: "http://example.com/payload.bin")!,
            destination: destination,
            status: .paused,
            totalBytes: 4_096,
            downloadedBytes: 2_048
        ), deletingFiles: false)

        #expect(!FileManager.default.fileExists(atPath: destination.path + ".segments"))
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".part0"))
        #expect(!FileManager.default.fileExists(atPath: destination.path + ".part1"))
    }

    @Test("applies browser download context headers to HTTP requests")
    func appliesBrowserDownloadContextHeadersToHTTPRequests() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("payload.bin")
        let context = BrowserDownloadContext(
            referrer: "https://example.com/releases?token=secret",
            userAgent: "ExampleBrowser/1.0",
            method: "GET",
            headers: [
                BrowserDownloadHeader(name: "Authorization", value: "Bearer secret", sensitive: true),
                BrowserDownloadHeader(name: "Accept-Language", value: "en-US"),
                BrowserDownloadHeader(name: "Range", value: "bytes=100-200")
            ]
        )
        let engine = HTTPDownloadEngine()
        engine.configure(segmentCount: 1, retryLimit: 0)
        await engine.start(Self.request(
            source: server.url,
            destination: destination,
            browserContext: context
        ))

        let downloaded = try Data(contentsOf: destination)
        #expect(downloaded == payload)
        #expect(server.requests.contains { request in
            request.hasPrefix("HEAD")
                && request.contains("Authorization: Bearer secret")
                && request.contains("Accept-Language: en-US")
                && request.contains("Referer: https://example.com/releases?token=secret")
                && request.contains("User-Agent: ExampleBrowser/1.0")
                && !request.contains("Range: bytes=100-200")
        })
        #expect(server.requests.contains { request in
            request.hasPrefix("GET")
                && request.contains("Authorization: Bearer secret")
                && request.contains("Accept-Language: en-US")
                && request.contains("Referer: https://example.com/releases?token=secret")
                && request.contains("User-Agent: ExampleBrowser/1.0")
                && !request.contains("Range: bytes=100-200")
        })
    }

    @Test("uses Content-Disposition filename and records HTTP metadata")
    func usesContentDispositionFilenameAndRecordsHTTPMetadata() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload, behavior: .contentDispositionMetadata)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("download")
        let finalDestination = directory.appendingPathComponent("report final.zip")
        let recorder = SnapshotRecorder()
        let engine = HTTPDownloadEngine()
        engine.onSnapshot = { snapshot in
            recorder.append(snapshot)
        }
        engine.configure(segmentCount: 1, retryLimit: 0)
        await engine.start(Self.request(source: server.url, destination: destination))

        let downloaded = try Data(contentsOf: finalDestination)
        let completed = try #require(recorder.snapshots.last(where: { $0.status == .completed }))
        let metadata = try #require(completed.httpResponseMetadata)

        #expect(downloaded == payload)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(completed.savePath == finalDestination.path)
        #expect(recorder.snapshots.contains { $0.name == "report final.zip" })
        #expect(metadata.suggestedFilename == "report final.zip")
        #expect(metadata.mimeType == "application/zip")
        #expect(metadata.contentDisposition == RangeTestServer.contentDisposition)
        #expect(metadata.server == "SwiftGetXTest")
        #expect(metadata.finalURL == server.url.absoluteString)
        #expect(metadata.contentLength == Int64(payload.count))
        #expect(metadata.supportsResume == true)
        #expect(metadata.eTag == "\"test\"")
        #expect(metadata.lastModified == RangeTestServer.lastModified)
    }

    @Test("records final URL and redirect metadata")
    func recordsFinalURLAndRedirectMetadata() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload, behavior: .redirectToMetadata)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("download.bin")
        let recorder = SnapshotRecorder()
        let engine = HTTPDownloadEngine()
        engine.onSnapshot = { snapshot in
            recorder.append(snapshot)
        }
        engine.configure(segmentCount: 1, retryLimit: 0)
        await engine.start(Self.request(source: server.redirectURL, destination: destination))

        let completed = try #require(recorder.snapshots.last(where: { $0.status == .completed }))
        let metadata = try #require(completed.httpResponseMetadata)

        #expect(try Data(contentsOf: directory.appendingPathComponent("report final.zip")) == payload)
        #expect(metadata.originalURL == server.redirectURL.absoluteString)
        #expect(metadata.finalURL == server.url.absoluteString)
        #expect(metadata.wasRedirected)
        #expect(metadata.redirects.contains {
            $0.statusCode == 302
                && $0.fromURL == server.redirectURL.absoluteString
                && $0.toURL == server.url.absoluteString
        })
    }

    @Test("previews HTTP metadata before creating a task")
    func previewsHTTPMetadataBeforeCreatingTask() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload, behavior: .contentDispositionMetadata)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        FileManager.default.createFile(
            atPath: directory.appendingPathComponent("report final.zip").path,
            contents: Data()
        )

        let service = HTTPMetadataPreviewService()
        let preview = await service.preview(
            source: server.url.absoluteString,
            saveDirectory: directory
        )

        #expect(preview.kind == .http)
        #expect(preview.metadataStatus == .available)
        #expect(preview.displayName == "report final.zip")
        #expect(preview.totalBytes == Int64(payload.count))
        #expect(preview.supportsResume)
        #expect(preview.savePath == directory.appendingPathComponent("report final 2.zip").path)
        #expect(preview.duplicateStrategy == .autoRename(
            originalFilename: "report final.zip",
            resolvedFilename: "report final 2.zip"
        ))

        let metadata = try #require(preview.httpResponseMetadata)
        #expect(metadata.suggestedFilename == "report final.zip")
        #expect(metadata.mimeType == "application/zip")
        #expect(metadata.contentDisposition == RangeTestServer.contentDisposition)
        #expect(metadata.server == "SwiftGetXTest")
        #expect(metadata.finalURL == server.url.absoluteString)
        #expect(metadata.contentLength == Int64(payload.count))
        #expect(metadata.supportsResume == true)
        #expect(metadata.eTag == "\"test\"")
        #expect(metadata.lastModified == RangeTestServer.lastModified)
    }

    @Test("HTTP preview falls back to range probe for incomplete HEAD metadata")
    func httpPreviewFallsBackToRangeProbeForIncompleteHEADMetadata() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload, behavior: .headWithoutContentLength)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let service = HTTPMetadataPreviewService()
        let preview = await service.preview(
            source: server.url.absoluteString,
            saveDirectory: directory
        )

        #expect(preview.metadataStatus == .available)
        #expect(preview.displayName == "payload.bin")
        #expect(preview.totalBytes == Int64(payload.count))
        #expect(preview.supportsResume)
        #expect(preview.httpResponseMetadata?.contentLength == Int64(payload.count))
        #expect(server.requests.contains { $0.hasPrefix("HEAD") })
        #expect(server.requests.contains { request in
            request.hasPrefix("GET") && request.contains("Range: bytes=0-0")
        })
    }

    @Test("HTTP preview falls back when server metadata probe is unavailable")
    func httpPreviewFallsBackWhenMetadataProbeUnavailable() async throws {
        let payload = Self.payload()
        let server = try RangeTestServer(payload: payload, behavior: .rejectMetadataProbe)
        try await server.start()
        defer { server.stop() }

        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let service = HTTPMetadataPreviewService()
        let preview = await service.preview(
            source: server.url.absoluteString,
            suggestedFilename: "fallback.bin",
            saveDirectory: directory
        )

        #expect(preview.kind == .http)
        #expect(preview.metadataStatus == .unavailable)
        #expect(preview.displayName == "fallback.bin")
        #expect(preview.totalBytes == 0)
        #expect(!preview.supportsResume)
        #expect(preview.savePath == directory.appendingPathComponent("fallback.bin").path)
        #expect(preview.httpResponseMetadata?.suggestedFilename == "fallback.bin")
        #expect(preview.errorMessage == nil)
        #expect(server.requests.contains { $0.hasPrefix("HEAD") })
        #expect(server.requests.contains { request in
            request.hasPrefix("GET") && request.contains("Range: bytes=0-0")
        })
    }

    @Test("HTTP preview rejects invalid sources safely")
    func httpPreviewRejectsInvalidSourcesSafely() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let service = HTTPMetadataPreviewService()
        let preview = await service.preview(
            source: "not-a-url",
            suggestedFilename: "../bad:name.zip",
            saveDirectory: directory
        )

        #expect(preview.kind == .http)
        #expect(preview.metadataStatus == .failed)
        #expect(preview.displayName == "bad-name.zip")
        #expect(preview.savePath == directory.appendingPathComponent("bad-name.zip").path)
        #expect(preview.httpResponseMetadata?.suggestedFilename == "bad-name.zip")
        #expect(preview.errorMessage == L10n.string("error_invalid_url"))
    }

    @Test("coordinator adds HTTP tasks from preview metadata")
    func coordinatorAddsHTTPTasksFromPreviewMetadata() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let context = BrowserDownloadContext(
            referrer: "https://example.com/releases?token=secret",
            headers: [
                BrowserDownloadHeader(name: "Authorization", value: "Bearer secret", sensitive: true),
                BrowserDownloadHeader(name: "Accept-Language", value: "en-US")
            ],
            finalURL: "https://cdn.example.com/file.zip?signature=secret",
            originalURL: "https://example.com/file.zip?token=secret",
            suggestedFilename: "file.zip",
            sourcePageURL: "https://example.com/releases?token=secret"
        )
        let metadata = HTTPResponseMetadata(
            originalURL: "https://example.com/file.zip?token=secret",
            finalURL: "https://cdn.example.com/file.zip?signature=secret",
            mimeType: "application/zip",
            suggestedFilename: "file.zip",
            supportsResume: true,
            contentLength: 42
        )
        let preview = TorrentMetadataPreview(
            source: "https://example.com/file.zip?token=secret",
            kind: .http,
            displayName: "file.zip",
            resolvedTorrentFilePath: nil,
            files: [],
            totalBytes: 42,
            metadataStatus: .available,
            errorMessage: nil,
            httpResponseMetadata: metadata,
            supportsResume: true,
            savePath: directory.appendingPathComponent("file 2.zip").path,
            duplicateStrategy: .autoRename(originalFilename: "file.zip", resolvedFilename: "file 2.zip"),
            browserContext: context
        )
        let coordinator = DownloadCoordinator()

        let tasks = coordinator.add(previews: [preview], saveDirectory: directory)
        let task = tasks.first

        #expect(tasks.count == 1)
        #expect(task?.name == "file.zip")
        #expect(task?.savePath == directory.appendingPathComponent("file 2.zip").path)
        #expect(task?.totalBytes == 42)
        #expect(task?.supportsResume == true)
        #expect(task?.httpResponseMetadata?.finalURL == "https://cdn.example.com/file.zip?signature=%3Credacted%3E")
        #expect(task?.browserContext?.headers == [
            BrowserDownloadHeader(name: "Accept-Language", value: "en-US")
        ])
        #expect(task?.browserContextJSON?.contains("Bearer secret") == false)
    }

    @Test("parses Content-Disposition filenames safely")
    func parsesContentDispositionFilenamesSafely() {
        #expect(HTTPContentDisposition.suggestedFilename(
            from: #"attachment; filename="fallback.zip"; filename*=UTF-8''server%20name.zip"#
        ) == "server name.zip")
        #expect(HTTPContentDisposition.suggestedFilename(
            from: #"attachment; filename="../unsafe/name.zip""#
        ) == "name.zip")

        let controlFilename = "attachment; filename=\"bad\(String(UnicodeScalar(1)))name.zip\""
        #expect(HTTPContentDisposition.suggestedFilename(from: controlFilename) == "bad-name.zip")
    }

    private static func payload() -> Data {
        Data((0..<32_768).map { UInt8($0 % 251) })
    }

    private static func largePayload() -> Data {
        Data((0..<(4 * 1024 * 1024 + 123)).map { UInt8($0 % 251) })
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
        status: DownloadStatus = .queued,
        totalBytes: Int64 = 0,
        downloadedBytes: Int64 = 0,
        supportsResume: Bool = false,
        eTag: String? = nil,
        lastModified: String? = nil,
        browserContext: BrowserDownloadContext? = nil
    ) -> DownloadRequest {
        DownloadRequest(
            id: UUID(),
            name: destination.lastPathComponent,
            source: source.absoluteString,
            kind: .http,
            status: status,
            savePath: destination.path,
            totalBytes: totalBytes,
            downloadedBytes: downloadedBytes,
            supportsResume: supportsResume,
            eTag: eTag,
            lastModified: lastModified,
            selectedFileIndexes: [],
            browserContext: browserContext
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
        case contentDispositionMetadata
        case redirectToMetadata
        case failFirstGET(status: Int)
        case failFirstRangedGET(status: Int)
        case ignoreRange
        case mismatchedContentRange
        case changingGETValidator
        case headWithoutRangeMetadata
        case headWithoutContentLength
        case rejectRangeRequests
        case rejectMetadataProbe
    }

    private let payload: Data
    private let behavior: Behavior
    private let listener: NWListener
    private let queue = DispatchQueue(label: "SwiftGetX.RangeTestServer")
    private let lock = NSLock()
    private var getCount = 0
    private var rangedGETCount = 0
    private var capturedRequests = [String]()

    static let contentDisposition = #"attachment; filename="fallback.zip"; filename*=UTF-8''report%20final.zip"#
    static let lastModified = "Wed, 21 Oct 2015 07:28:00 GMT"

    var url: URL {
        URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/payload.bin")!
    }

    var redirectURL: URL {
        URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/redirect.bin")!
    }

    var requests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
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
        lock.lock()
        capturedRequests.append(request)
        lock.unlock()

        let path = Self.requestPath(from: request)
        if behavior == .redirectToMetadata, path == "/redirect.bin" {
            return Self.httpResponse(
                status: "302 Found",
                headers: [
                    "Location": url.absoluteString,
                    "Content-Length": "0"
                ],
                body: Data()
            )
        }

        if request.hasPrefix("HEAD") {
            if behavior == .rejectMetadataProbe {
                return Self.httpResponse(
                    status: "405 Method Not Allowed",
                    headers: ["Content-Length": "0"],
                    body: Data()
                )
            }

            if behavior == .headWithoutRangeMetadata {
                return Self.httpResponse(
                    status: "200 OK",
                    headers: [
                        "Content-Length": "\(payload.count)",
                        "ETag": "\"test\""
                    ],
                    body: Data()
                )
            }

            if behavior == .headWithoutContentLength {
                return Self.httpResponse(
                    status: "200 OK",
                    headers: [
                        "Accept-Ranges": "bytes",
                        "ETag": "\"test\""
                    ],
                    body: Data()
                )
            }

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

        lock.lock()
        if hasRange {
            rangedGETCount += 1
        }
        let currentRangedGETCount = rangedGETCount
        lock.unlock()

        if case .failFirstRangedGET(let status) = behavior, hasRange, currentRangedGETCount == 2 {
            return Self.httpResponse(
                status: "\(status) Server Error",
                headers: baseHeaders(contentLength: 0, eTag: "\"test\""),
                body: Data()
            )
        }

        if behavior == .ignoreRange, hasRange {
            return Self.httpResponse(
                status: "200 OK",
                headers: baseHeaders(contentLength: payload.count, eTag: "\"test\""),
                body: payload
            )
        }

        if (behavior == .rejectRangeRequests || behavior == .rejectMetadataProbe), hasRange {
            return Self.httpResponse(
                status: "416 Range Not Satisfiable",
                headers: [
                    "Content-Range": "bytes */\(payload.count)",
                    "ETag": "\"test\""
                ],
                body: Data()
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
        var headers = [
            "Content-Length": "\(contentLength)",
            "Accept-Ranges": "bytes",
            "ETag": eTag,
            "Last-Modified": Self.lastModified
        ]
        if behavior == .contentDispositionMetadata || behavior == .redirectToMetadata {
            headers["Content-Disposition"] = Self.contentDisposition
            headers["Content-Type"] = "application/zip"
            headers["Server"] = "SwiftGetXTest"
        }
        return headers
    }

    private static func requestPath(from request: String) -> String {
        let line = request.components(separatedBy: "\r\n").first ?? ""
        let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
        return parts.count > 1 ? parts[1] : "/"
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
        guard start < payloadCount else { return start..<start }
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
