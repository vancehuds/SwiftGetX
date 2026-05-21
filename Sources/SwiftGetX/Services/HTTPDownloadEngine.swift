import Foundation
import SwiftGetXCore

@MainActor
final class HTTPDownloadEngine: DownloadEngine {
    var onSnapshot: (@Sendable (DownloadSnapshot) -> Void)?

    private let runState = HTTPDownloadRunState()
    private var multithreadingEnabled = true
    private var segmentCount = 8
    private var hidesTemporaryFiles = true
    private var retryLimit = 3

    func configure(
        multithreadingEnabled: Bool,
        segmentCount: Int,
        hidesTemporaryFiles: Bool,
        retryLimit: Int
    ) {
        self.multithreadingEnabled = multithreadingEnabled
        self.segmentCount = multithreadingEnabled ? min(max(1, segmentCount), segmentScanLimit) : 1
        self.hidesTemporaryFiles = hidesTemporaryFiles
        self.retryLimit = max(0, retryLimit)
    }

    func configure(segmentCount: Int, retryLimit: Int) {
        configure(
            multithreadingEnabled: segmentCount > 1,
            segmentCount: segmentCount,
            hidesTemporaryFiles: true,
            retryLimit: retryLimit
        )
    }

    func start(_ request: DownloadRequest) async {
        guard let url = URL(string: request.source) else {
            emitFailure(request, message: L10n.string("error_invalid_url"))
            return
        }

        let requestSegmentCount = request.httpOptions?.effectiveSegmentCount(
            defaultSegmentCount: segmentCount,
            multithreadingEnabled: multithreadingEnabled
        ) ?? (multithreadingEnabled ? segmentCount : 1)
        let requestRetryLimit = request.httpOptions?.effectiveRetryLimit(defaultRetryLimit: retryLimit) ?? retryLimit
        await runState.activate(request.id)
        let worker = HTTPDownloadWorker(
            segmentCount: min(max(1, requestSegmentCount), segmentScanLimit),
            hidesTemporaryFiles: hidesTemporaryFiles,
            retryLimit: max(0, requestRetryLimit),
            runState: runState,
            onSnapshot: onSnapshot
        )
        await worker.start(request, url: url)
    }

    func pause(_ request: DownloadRequest) async {
        await runState.deactivate(request.id)
        emitPaused(request)
    }

    func resume(_ request: DownloadRequest) async {
        await start(request)
    }

    func cancel(_ request: DownloadRequest) async {
        await runState.deactivate(request.id)
    }

    func remove(_ request: DownloadRequest, deletingFiles: Bool) async {
        await cancel(request)
        if deletingFiles {
            _ = try? FileSystemSafety.removeSafely(
                URL(fileURLWithPath: request.savePath),
                allowedRoot: URL(fileURLWithPath: request.savePath).deletingLastPathComponent(),
                allowsDirectories: false
            )
            HTTPPartialDataStore(savePath: request.savePath).removeData()
        }
    }

    func recheck(_ request: DownloadRequest) async {
        let fileURL = URL(fileURLWithPath: request.savePath)
        let size = HTTPPartialDataStore.localSize(at: fileURL)
        let status: DownloadStatus = request.totalBytes > 0 && size == request.totalBytes ? .completed : .failed
        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: status,
                totalBytes: request.totalBytes,
                downloadedBytes: size,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: status == .failed ? L10n.string("error_file_size_mismatch") : nil,
                supportsResume: request.supportsResume,
                eTag: request.eTag,
                lastModified: request.lastModified,
                connectionSummary: request.supportsResume
                    ? L10n.string("http_connection_resume_only")
                    : L10n.string("http_connection_no_resume_only"),
                httpResponseMetadata: request.httpResponseMetadata
            )
        )
    }

    func setFileSelection(_ request: DownloadRequest, selectedFileIndexes: [Int]) async {}

    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async {
        await runState.setSpeedLimit(max(0, downloadBytesPerSecond))
    }

    private func emitPaused(_ request: DownloadRequest) {
        emit(HTTPDownloadWorker.pausedSnapshot(for: request))
    }

    private func emitFailure(_ request: DownloadRequest, message: String) {
        emit(HTTPDownloadWorker.failureSnapshot(for: request, message: message))
    }

    private func emit(_ snapshot: DownloadSnapshot) {
        onSnapshot?(snapshot)
    }
}

private let segmentScanLimit = HTTPPartialDataStore.maxSegmentCount

private actor HTTPDownloadRunState {
    private var activeTaskIDs = Set<UUID>()
    private var speedLimitBytesPerSecond: Int64 = 0
    private var nextDownloadSlot = Date()
    private var nextPerTaskDownloadSlots = [UUID: Date]()

    func activate(_ id: UUID) {
        activeTaskIDs.insert(id)
    }

    func deactivate(_ id: UUID) {
        activeTaskIDs.remove(id)
        nextPerTaskDownloadSlots[id] = nil
    }

    func isActive(_ id: UUID) -> Bool {
        activeTaskIDs.contains(id)
    }

    func setSpeedLimit(_ bytesPerSecond: Int64) {
        speedLimitBytesPerSecond = max(0, bytesPerSecond)
        nextDownloadSlot = Date()
    }

    func waitForDownloadCapacity(
        taskID: UUID,
        bytes: Int64,
        perTaskLimitBytesPerSecond: Int64?
    ) async {
        let taskLimitBytesPerSecond = max(0, perTaskLimitBytesPerSecond ?? 0)
        guard bytes > 0,
              speedLimitBytesPerSecond > 0 || taskLimitBytesPerSecond > 0
        else {
            return
        }

        let now = Date()
        var delay: TimeInterval = 0

        if speedLimitBytesPerSecond > 0 {
            if nextDownloadSlot < now {
                nextDownloadSlot = now
            }
            delay = max(delay, nextDownloadSlot.timeIntervalSince(now))
            nextDownloadSlot = nextDownloadSlot.addingTimeInterval(
                Double(bytes) / Double(speedLimitBytesPerSecond)
            )
        }

        if taskLimitBytesPerSecond > 0 {
            var nextTaskSlot = nextPerTaskDownloadSlots[taskID] ?? now
            if nextTaskSlot < now {
                nextTaskSlot = now
            }
            delay = max(delay, nextTaskSlot.timeIntervalSince(now))
            nextPerTaskDownloadSlots[taskID] = nextTaskSlot.addingTimeInterval(
                Double(bytes) / Double(taskLimitBytesPerSecond)
            )
        }

        guard delay > 0 else { return }
        try? await Task.sleep(for: .seconds(delay))
    }
}

private final class HTTPRedirectRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var values = [HTTPRedirectMetadata]()

    var redirects: [HTTPRedirectMetadata] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let redirect = HTTPRedirectMetadata(
            statusCode: response.statusCode,
            fromURL: response.url?.absoluteString,
            toURL: request.url?.absoluteString
        )
        lock.lock()
        values.append(redirect)
        lock.unlock()
        completionHandler(request)
    }
}

struct HTTPMetadataProbe: Sendable {
    var segmentCount: Int
    var probesRangeForIncompleteMetadata = false
    var timeoutInterval: TimeInterval = 20

    func probe(url: URL, request: DownloadRequest) async -> HTTPMetadata {
        let headRequest = HTTPRequestFactory.makeRequest(
            url: url,
            method: "HEAD",
            timeoutInterval: timeoutInterval,
            request: request
        )
        var metadata = HTTPMetadata.unknown

        do {
            let redirectRecorder = HTTPRedirectRecorder()
            let session = HTTPRequestFactory.redirectRecordingSession(redirectRecorder)
            defer { session.invalidateAndCancel() }
            let (_, response) = try await session.data(for: headRequest)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                return await probeRange(url: url, request: request).filled(from: request)
            }

            let length = Int64(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "") ?? 0
            let acceptRanges = httpResponse
                .value(forHTTPHeaderField: "Accept-Ranges")?
                .localizedCaseInsensitiveContains("bytes") ?? false

            metadata = HTTPMetadata(
                contentLength: max(0, length),
                supportsResume: acceptRanges,
                eTag: httpResponse.value(forHTTPHeaderField: "ETag"),
                lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified")
            ).merging(
                response: httpResponse,
                resumedFrom: 0,
                redirects: redirectRecorder.redirects,
                filenameOverride: request.httpOptions?.filenameOverride
            )
        } catch {
            metadata = .unknown
        }

        metadata = metadata.filled(from: request)
        let needsRangeProbe = (!metadata.supportsResume && (segmentCount > 1 || request.supportsResume))
            || (metadata.contentLength <= 0 && (segmentCount > 1 || request.supportsResume))
            || (probesRangeForIncompleteMetadata && (!metadata.supportsResume || metadata.contentLength <= 0))
        guard needsRangeProbe else {
            return metadata
        }

        return await probeRange(url: url, request: request).merged(over: metadata)
    }

    private func probeRange(url: URL, request: DownloadRequest) async -> HTTPMetadata {
        var urlRequest = HTTPRequestFactory.makeRequest(
            url: url,
            method: "GET",
            timeoutInterval: timeoutInterval,
            request: request
        )
        urlRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        do {
            let redirectRecorder = HTTPRedirectRecorder()
            let session = HTTPRequestFactory.redirectRecordingSession(redirectRecorder)
            defer { session.invalidateAndCancel() }
            let (_, response) = try await session.bytes(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .unknown
            }

            switch httpResponse.statusCode {
            case 206:
                guard let rawRange = httpResponse.value(forHTTPHeaderField: "Content-Range"),
                      let contentRange = HTTPContentRange(rawRange),
                      contentRange.start == 0,
                      contentRange.end == 0
                else {
                    return .unknown
                }

                return HTTPMetadata(
                    contentLength: contentRange.total ?? 0,
                    supportsResume: true,
                    eTag: httpResponse.value(forHTTPHeaderField: "ETag"),
                    lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified")
                ).merging(
                    response: httpResponse,
                    resumedFrom: 0,
                    redirects: redirectRecorder.redirects,
                    filenameOverride: request.httpOptions?.filenameOverride
                )
            case 200...299:
                let responseLength = httpResponse.expectedContentLength > 0
                    ? httpResponse.expectedContentLength
                    : 0
                return HTTPMetadata(
                    contentLength: responseLength,
                    supportsResume: false,
                    eTag: httpResponse.value(forHTTPHeaderField: "ETag"),
                    lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified")
                ).merging(
                    response: httpResponse,
                    resumedFrom: 0,
                    redirects: redirectRecorder.redirects,
                    filenameOverride: request.httpOptions?.filenameOverride
                )
            default:
                return .unknown
            }
        } catch {
            return .unknown
        }
    }
}

private enum HTTPRequestFactory {
    static func redirectRecordingSession(_ recorder: HTTPRedirectRecorder) -> URLSession {
        URLSession(configuration: sessionConfiguration(), delegate: recorder, delegateQueue: nil)
    }

    static func makeRequest(
        url: URL,
        method: String,
        timeoutInterval: TimeInterval,
        request downloadRequest: DownloadRequest
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeoutInterval
        request.setValue("SwiftGetX", forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if url.host?.localizedCaseInsensitiveCompare("api.github.com") == .orderedSame {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        }
        applyBrowserContext(downloadRequest.browserContext, to: &request)
        applyHTTPOptions(downloadRequest.httpOptions, to: &request)
        return request
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        return configuration
    }

    private static func applyBrowserContext(_ context: BrowserDownloadContext?, to request: inout URLRequest) {
        guard let context else { return }
        for (name, value) in context.httpHeaders() {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    private static func applyHTTPOptions(_ options: HTTPDownloadOptions?, to request: inout URLRequest) {
        guard let options else { return }
        for (name, value) in options.httpHeaders() {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }
}

private struct HTTPDownloadWorker: Sendable {
    private static let bufferSize = 64 * 1024
    private static let minimumSplitSize: Int64 = 1024 * 1024
    private static let session: URLSession = {
        URLSession(configuration: sessionConfiguration())
    }()

    let segmentCount: Int
    let hidesTemporaryFiles: Bool
    let retryLimit: Int
    let runState: HTTPDownloadRunState
    let onSnapshot: (@Sendable (DownloadSnapshot) -> Void)?

    private func waitForDownloadCapacity(request: DownloadRequest, bytes: Int64) async {
        let perTaskLimit = request.perTaskDownloadLimitBytes > 0
            ? request.perTaskDownloadLimitBytes
            : request.httpOptions?.perTaskDownloadLimitBytes
        await runState.waitForDownloadCapacity(
            taskID: request.id,
            bytes: bytes,
            perTaskLimitBytesPerSecond: perTaskLimit
        )
    }

    private static func sessionConfiguration() -> URLSessionConfiguration {
        HTTPRequestFactory.sessionConfiguration()
    }

    func start(_ request: DownloadRequest, url: URL) async {
        var lastError: Error?

        for attempt in 0...retryLimit {
            guard await runState.isActive(request.id) else {
                await runState.deactivate(request.id)
                emit(Self.pausedSnapshot(for: request))
                return
            }

            do {
                try await download(url: url, request: request)
                await runState.deactivate(request.id)
                return
            } catch is CancellationError {
                await runState.deactivate(request.id)
                emit(Self.pausedSnapshot(for: request))
                return
            } catch {
                lastError = error
                guard await runState.isActive(request.id) else {
                    await runState.deactivate(request.id)
                    emit(Self.pausedSnapshot(for: request))
                    return
                }

                guard attempt < retryLimit, Self.isRetryable(error) else {
                    break
                }

                emitRetry(request, error: error, attempt: attempt + 1)
                try? await Task.sleep(for: .seconds(min(6, attempt + 1)))
            }
        }

        await runState.deactivate(request.id)
        emit(Self.failureSnapshot(
            for: request,
            message: lastError?.localizedDescription ?? L10n.string("error_download_failed")
        ))
    }

    private func download(url: URL, request: DownloadRequest) async throws {
        var destination = URL(fileURLWithPath: request.savePath)
        var layout = HTTPTemporaryLayout(savePath: request.savePath)
        try Self.preflight(
            destination: destination,
            expectedBytes: request.totalBytes,
            existingBytes: layout.temporaryProgress(maxSegments: segmentScanLimit)
        )

        var metadata = await HTTPMetadataProbe(segmentCount: segmentCount)
            .probe(url: url, request: request)
        let prepared = prepareInitialDestination(
            request: request,
            metadata: metadata,
            destination: destination,
            layout: layout
        )
        destination = prepared.destination
        layout = prepared.layout
        try Self.preflight(
            destination: destination,
            expectedBytes: max(metadata.contentLength, request.totalBytes),
            existingBytes: layout.temporaryProgress(maxSegments: segmentScanLimit),
            additionalScratchBytes: segmentedScratchBytes(
                contentLength: metadata.contentLength,
                supportsResume: metadata.supportsResume,
                segmentCount: segmentCount
            )
        )

        let singlePartBytes = HTTPTemporaryLayout.localSize(at: layout.singlePartURL)
        let segmentedBytes = layout.segmentProgress(maxSegments: segmentScanLimit)

        if singlePartBytes > 0 {
            try await downloadSingle(
                url: url,
                request: request,
                metadata: metadata,
                layout: layout,
                destination: destination
            )
            return
        }

        if segmentedBytes > 0 {
            let manifest: HTTPDownloadManifest
            if let storedManifest = try? layout.loadManifest() {
                manifest = storedManifest
            } else {
                manifest = try legacyManifest(for: request, layout: layout, metadata: metadata)
            }
            metadata = metadata.filled(from: manifest)
            try validate(manifest: manifest, request: request, against: metadata)
            try layout.writeManifest(manifest, hidden: hidesTemporaryFiles)
            try await downloadSegmentedWithSingleStreamFallback(
                url: url,
                request: request,
                metadata: metadata,
                manifest: manifest,
                layout: layout,
                destination: destination
            )
            return
        }

        if metadata.supportsResume, metadata.contentLength > 0, segmentCount > 1 {
            let plan = SegmentPlan.make(
                totalBytes: metadata.contentLength,
                segmentCount: segmentCount,
                minSplitSize: Self.minimumSplitSize
            )
            guard plan.segments.count > 1 else {
                try await downloadSingle(
                    url: url,
                    request: request,
                    metadata: metadata,
                    layout: layout,
                    destination: destination
                )
                return
            }

            let manifest = HTTPDownloadManifest(
                source: request.source,
                totalBytes: metadata.contentLength,
                eTag: metadata.eTag,
                lastModified: metadata.lastModified,
                segments: plan.segments.map(HTTPManifestSegment.init)
            )
            try layout.writeManifest(manifest, hidden: hidesTemporaryFiles)
            try await downloadSegmentedWithSingleStreamFallback(
                url: url,
                request: request,
                metadata: metadata,
                manifest: manifest,
                layout: layout,
                destination: destination
            )
            return
        }

        try await downloadSingle(
            url: url,
            request: request,
            metadata: metadata,
            layout: layout,
            destination: destination
        )
    }

    private static func preflight(
        destination: URL,
        expectedBytes: Int64,
        existingBytes: Int64,
        additionalScratchBytes: Int64 = 0
    ) throws {
        do {
            try FileSystemSafety.preflightDownloadDestination(
                destination,
                expectedBytes: expectedBytes,
                existingBytes: existingBytes,
                additionalScratchBytes: additionalScratchBytes
            )
        } catch {
            throw HTTPDownloadError.localPreflight(error.localizedDescription)
        }
    }

    private func segmentedScratchBytes(contentLength: Int64, supportsResume: Bool, segmentCount: Int) -> Int64 {
        guard supportsResume, contentLength > 0, segmentCount > 1 else { return 0 }
        let plan = SegmentPlan.make(
            totalBytes: contentLength,
            segmentCount: segmentCount,
            minSplitSize: Self.minimumSplitSize
        )
        return plan.segments.count > 1 ? contentLength : 0
    }

    private func prepareInitialDestination(
        request: DownloadRequest,
        metadata: HTTPMetadata,
        destination: URL,
        layout: HTTPTemporaryLayout
    ) -> (destination: URL, layout: HTTPTemporaryLayout) {
        guard request.downloadedBytes == 0,
              layout.temporaryProgress(maxSegments: segmentScanLimit) == 0,
              let filename = metadata.responseMetadata?.suggestedFilename,
              !filename.isEmpty,
              filename != destination.lastPathComponent
        else {
            return (destination, layout)
        }

        let updatedDestination = destination
            .deletingLastPathComponent()
            .appendingPathComponent(filename)
        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .running,
                name: filename,
                savePath: updatedDestination.path,
                totalBytes: metadata.contentLength,
                downloadedBytes: 0,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: nil,
                supportsResume: metadata.supportsResume,
                eTag: metadata.eTag,
                lastModified: metadata.lastModified,
                connectionSummary: connectionSummary(segmentCount: 1, supportsResume: metadata.supportsResume),
                httpResponseMetadata: metadata.responseMetadata
            )
        )
        return (updatedDestination, HTTPTemporaryLayout(savePath: updatedDestination.path))
    }

    private func downloadSegmentedWithSingleStreamFallback(
        url: URL,
        request: DownloadRequest,
        metadata: HTTPMetadata,
        manifest: HTTPDownloadManifest,
        layout: HTTPTemporaryLayout,
        destination: URL
    ) async throws {
        do {
            try await downloadSegmented(
                url: url,
                request: request,
                metadata: metadata,
                manifest: manifest,
                layout: layout,
                destination: destination
            )
        } catch {
            guard Self.shouldFallbackToSingleStream(after: error) else {
                throw error
            }

            try await ensureActive(request.id)
            layout.removeTemporaryFiles(maxSegments: segmentScanLimit)

            var singleStreamMetadata = metadata
            singleStreamMetadata.supportsResume = false
            try await downloadSingle(
                url: url,
                request: request,
                metadata: singleStreamMetadata,
                layout: layout,
                destination: destination
            )
        }
    }

    private func downloadSingle(
        url: URL,
        request: DownloadRequest,
        metadata: HTTPMetadata,
        layout: HTTPTemporaryLayout,
        destination: URL
    ) async throws {
        try await ensureActive(request.id)

        if !FileManager.default.fileExists(atPath: layout.singlePartURL.path) {
            FileManager.default.createFile(atPath: layout.singlePartURL.path, contents: nil)
        }
        layout.setFileHidden(at: layout.singlePartURL, hidden: hidesTemporaryFiles)

        var metadata = metadata
        var existingBytes = HTTPTemporaryLayout.localSize(at: layout.singlePartURL)
        if existingBytes > 0,
           metadata.contentLength > 0,
           existingBytes > metadata.contentLength
        {
            try Data().write(to: layout.singlePartURL)
            existingBytes = 0
        }
        if existingBytes > 0,
           metadata.contentLength > 0,
           existingBytes == metadata.contentLength
        {
            try finalizeSinglePart(
                request: request,
                metadata: metadata,
                layout: layout,
                destination: destination,
                downloadedBytes: existingBytes
            )
            return
        }

        let shouldResume = metadata.supportsResume && existingBytes > 0
        if existingBytes > 0 && !shouldResume {
            try Data().write(to: layout.singlePartURL)
            existingBytes = 0
        }

        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .running,
                totalBytes: metadata.contentLength,
                downloadedBytes: shouldResume ? existingBytes : 0,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: nil,
                supportsResume: metadata.supportsResume,
                eTag: metadata.eTag,
                lastModified: metadata.lastModified,
                connectionSummary: connectionSummary(segmentCount: 1, supportsResume: metadata.supportsResume),
                httpResponseMetadata: metadata.responseMetadata,
                httpSegments: singleStreamSegments(
                    totalBytes: metadata.contentLength,
                    downloadedBytes: shouldResume ? existingBytes : 0,
                    speedBytesPerSecond: 0
                )
            )
        )

        var urlRequest = HTTPRequestFactory.makeRequest(
            url: url,
            method: "GET",
            timeoutInterval: 30,
            request: request
        )
        if shouldResume {
            urlRequest.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
            applyIfRange(to: &urlRequest, metadata: metadata, request: request)
        }

        let redirectRecorder = HTTPRedirectRecorder()
        let session = HTTPRequestFactory.redirectRecordingSession(redirectRecorder)
        defer { session.finishTasksAndInvalidate() }
        let (stream, response) = try await session.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPDownloadError.invalidResponse(L10n.string("error_invalid_server_response"))
        }

        var appendExistingBytes = shouldResume
        switch httpResponse.statusCode {
        case 206:
            try validateRangeResponse(
                httpResponse,
                expectedStart: existingBytes,
                expectedEnd: nil,
                expectedTotal: metadata.contentLength,
                expectedETag: request.eTag ?? metadata.eTag,
                expectedLastModified: request.lastModified ?? metadata.lastModified
            )
            metadata = metadata.merging(
                response: httpResponse,
                resumedFrom: existingBytes,
                redirects: redirectRecorder.redirects,
                filenameOverride: request.httpOptions?.filenameOverride
            )
        case 200...299:
            if shouldResume {
                try Data().write(to: layout.singlePartURL)
                appendExistingBytes = false
                existingBytes = 0
            }
            metadata = metadata.merging(
                response: httpResponse,
                resumedFrom: 0,
                redirects: redirectRecorder.redirects,
                filenameOverride: request.httpOptions?.filenameOverride
            )
        case 416 where shouldResume:
            if let totalBytes = Self.unsatisfiedRangeTotal(from: httpResponse),
               totalBytes > 0,
               existingBytes == totalBytes
            {
                metadata.contentLength = totalBytes
                try finalizeSinglePart(
                    request: request,
                    metadata: metadata,
                    layout: layout,
                    destination: destination,
                    downloadedBytes: existingBytes
                )
                return
            }

            try Data().write(to: layout.singlePartURL)
            var restartMetadata = metadata.merging(
                response: httpResponse,
                resumedFrom: 0,
                redirects: redirectRecorder.redirects,
                filenameOverride: request.httpOptions?.filenameOverride
            )
            restartMetadata.supportsResume = false
            try await downloadSingle(
                url: url,
                request: request,
                metadata: restartMetadata,
                layout: layout,
                destination: destination
            )
            return
        default:
            throw HTTPDownloadError.serverStatus(httpResponse.statusCode)
        }

        try? FileSystemSafety.preallocateFile(at: layout.singlePartURL, byteCount: metadata.contentLength)
        let fileHandle = try FileHandle(forWritingTo: layout.singlePartURL)
        defer {
            try? fileHandle.close()
        }

        if appendExistingBytes {
            try fileHandle.seekToEnd()
        } else {
            try fileHandle.truncate(atOffset: 0)
        }

        var downloadedBytes = appendExistingBytes ? existingBytes : 0
        var bytesSinceLastEmit: Int64 = 0
        var lastEmit = Date()
        var buffer = [UInt8]()
        buffer.reserveCapacity(Self.bufferSize)

        func flushBuffer() async throws {
            guard !buffer.isEmpty else { return }
            try await ensureActive(request.id)

            let bytes = Int64(buffer.count)
            try fileHandle.write(contentsOf: Data(buffer))
            downloadedBytes += bytes
            bytesSinceLastEmit += bytes
            buffer.removeAll(keepingCapacity: true)

            await waitForDownloadCapacity(request: request, bytes: bytes)

            let now = Date()
            guard now.timeIntervalSince(lastEmit) >= 0.35 else { return }

            let elapsed = max(now.timeIntervalSince(lastEmit), 0.001)
            let speed = Int64(Double(bytesSinceLastEmit) / elapsed)
            let remaining = metadata.contentLength > 0
                ? max(0, metadata.contentLength - downloadedBytes)
                : 0
            let eta = speed > 0 && remaining > 0 ? TimeInterval(remaining / speed) : nil

            emit(
                DownloadSnapshot(
                    taskID: request.id,
                    status: .running,
                    totalBytes: metadata.contentLength,
                    downloadedBytes: downloadedBytes,
                    speedBytesPerSecond: speed,
                    etaSeconds: eta,
                    errorMessage: nil,
                    supportsResume: metadata.supportsResume,
                    eTag: metadata.eTag,
                    lastModified: metadata.lastModified,
                    connectionSummary: connectionSummary(segmentCount: 1, supportsResume: metadata.supportsResume),
                    httpResponseMetadata: metadata.responseMetadata,
                    httpSegments: singleStreamSegments(
                        totalBytes: metadata.contentLength,
                        downloadedBytes: downloadedBytes,
                        speedBytesPerSecond: speed
                    )
                )
            )

            lastEmit = now
            bytesSinceLastEmit = 0
        }

        for try await byte in stream {
            buffer.append(byte)
            if buffer.count >= Self.bufferSize {
                try await flushBuffer()
            }
        }
        try await flushBuffer()

        if metadata.contentLength > 0, downloadedBytes != metadata.contentLength {
            throw HTTPDownloadError.incompleteSegment
        }

        try finalizeSinglePart(
            request: request,
            metadata: metadata,
            layout: layout,
            destination: destination,
            downloadedBytes: downloadedBytes
        )
    }

    private func finalizeSinglePart(
        request: DownloadRequest,
        metadata: HTTPMetadata,
        layout: HTTPTemporaryLayout,
        destination: URL,
        downloadedBytes: Int64
    ) throws {
        let finalURL = FileManager.default.uniqueFileURL(for: destination)
        try FileManager.default.moveItem(at: layout.singlePartURL, to: finalURL)
        layout.setFileHidden(at: finalURL, hidden: false)
        layout.removeTemporaryFiles(maxSegments: segmentScanLimit)

        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .completed,
                savePath: finalURL.path,
                totalBytes: max(metadata.contentLength, downloadedBytes),
                downloadedBytes: downloadedBytes,
                speedBytesPerSecond: 0,
                etaSeconds: 0,
                errorMessage: nil,
                supportsResume: metadata.supportsResume,
                eTag: metadata.eTag,
                lastModified: metadata.lastModified,
                connectionSummary: connectionSummary(segmentCount: 1, supportsResume: metadata.supportsResume),
                httpResponseMetadata: metadata.responseMetadata,
                httpSegments: singleStreamSegments(
                    totalBytes: max(metadata.contentLength, downloadedBytes),
                    downloadedBytes: downloadedBytes,
                    speedBytesPerSecond: 0
                )
            )
        )
    }

    private func downloadSegmented(
        url: URL,
        request: DownloadRequest,
        metadata: HTTPMetadata,
        manifest: HTTPDownloadManifest,
        layout: HTTPTemporaryLayout,
        destination: URL
    ) async throws {
        try await ensureActive(request.id)

        let plan = manifest.segmentPlan
        try layout.repairOversizedSegments(for: plan)
        let initialSegments = try layout.segmentInfos(for: plan)
        let initialBytes = initialSegments.reduce(Int64(0)) { $0 + $1.downloadedBytes }
        let progress = SegmentProgress(segments: initialSegments)
        let summary = connectionSummary(segmentCount: plan.segments.count, supportsResume: true)

        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .running,
                totalBytes: manifest.totalBytes,
                downloadedBytes: initialBytes,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: nil,
                supportsResume: true,
                eTag: metadata.eTag,
                lastModified: metadata.lastModified,
                connectionSummary: summary,
                httpResponseMetadata: metadata.responseMetadata,
                httpSegments: initialSegments
            )
        )

        let progressReporter = Task { [self] in
            await reportSegmentProgress(
                request: request,
                metadata: metadata,
                totalBytes: manifest.totalBytes,
                summary: summary,
                progress: progress
            )
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for segment in plan.segments {
                    group.addTask {
                        try await downloadSegmentWithRetries(
                            segment,
                            url: url,
                            request: request,
                            metadata: metadata,
                            layout: layout,
                            progress: progress
                        )
                    }
                }

                try await group.waitForAll()
            }
        } catch {
            progressReporter.cancel()
            throw error
        }

        progressReporter.cancel()
        let downloaded = await progress.downloadedBytes()
        guard downloaded == manifest.totalBytes else {
            throw HTTPDownloadError.incompleteSegment
        }

        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .running,
                totalBytes: manifest.totalBytes,
                downloadedBytes: downloaded,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: nil,
                supportsResume: true,
                eTag: metadata.eTag,
                lastModified: metadata.lastModified,
                connectionSummary: summary,
                httpResponseMetadata: metadata.responseMetadata,
                httpSegments: await progress.currentSegments()
            )
        )

        let finalURL = FileManager.default.uniqueFileURL(for: destination)
        let mergeURL = layout.mergeURL(for: finalURL)
        _ = try? FileSystemSafety.removeSafely(
            mergeURL,
            allowedRoot: finalURL.deletingLastPathComponent(),
            allowsDirectories: false
        )

        do {
            try? FileSystemSafety.preallocateFile(at: mergeURL, byteCount: manifest.totalBytes)
            try mergeSegments(
                plan: plan,
                layout: layout,
                destination: mergeURL,
                hidesTemporaryFiles: hidesTemporaryFiles
            )
            guard HTTPTemporaryLayout.localSize(at: mergeURL) == manifest.totalBytes else {
                throw HTTPDownloadError.incompleteSegment
            }
            try FileManager.default.moveItem(at: mergeURL, to: finalURL)
            layout.setFileHidden(at: finalURL, hidden: false)
        } catch {
            _ = try? FileSystemSafety.removeSafely(
                mergeURL,
                allowedRoot: finalURL.deletingLastPathComponent(),
                allowsDirectories: false
            )
            throw error
        }

        layout.removeTemporaryFiles(maxSegments: segmentScanLimit)

        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .completed,
                savePath: finalURL.path,
                totalBytes: manifest.totalBytes,
                downloadedBytes: manifest.totalBytes,
                speedBytesPerSecond: 0,
                etaSeconds: 0,
                errorMessage: nil,
                supportsResume: true,
                eTag: metadata.eTag,
                lastModified: metadata.lastModified,
                connectionSummary: summary,
                httpResponseMetadata: metadata.responseMetadata,
                httpSegments: await progress.currentSegments()
            )
        )
    }

    private func reportSegmentProgress(
        request: DownloadRequest,
        metadata: HTTPMetadata,
        totalBytes: Int64,
        summary: String,
        progress: SegmentProgress
    ) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(350))
            guard await runState.isActive(request.id) else { return }

            let sample = await progress.sample()
            let remaining = max(0, totalBytes - sample.downloadedBytes)
            let eta = sample.speedBytesPerSecond > 0 && remaining > 0
                ? TimeInterval(remaining / sample.speedBytesPerSecond)
                : nil

            emit(
                DownloadSnapshot(
                    taskID: request.id,
                    status: .running,
                    totalBytes: totalBytes,
                    downloadedBytes: sample.downloadedBytes,
                    speedBytesPerSecond: sample.speedBytesPerSecond,
                    etaSeconds: eta,
                    errorMessage: nil,
                    supportsResume: true,
                    eTag: metadata.eTag,
                    lastModified: metadata.lastModified,
                    connectionSummary: summary,
                    httpResponseMetadata: metadata.responseMetadata,
                    httpSegments: sample.segments
                )
            )
        }
    }

    private func downloadSegmentWithRetries(
        _ segment: DownloadSegment,
        url: URL,
        request: DownloadRequest,
        metadata: HTTPMetadata,
        layout: HTTPTemporaryLayout,
        progress: SegmentProgress
    ) async throws {
        var lastError: Error?

        for attempt in 0...retryLimit {
            try await ensureActive(request.id)

            do {
                try await downloadSegment(
                    segment,
                    url: url,
                    request: request,
                    metadata: metadata,
                    layout: layout,
                    progress: progress
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard await runState.isActive(request.id) else {
                    throw CancellationError()
                }
                guard attempt < retryLimit, Self.isRetryable(error) else {
                    throw error
                }

                emitRetry(request, error: error, attempt: attempt + 1)
                await progress.setRetryCount(attempt + 1, for: segment.index)
                try? await Task.sleep(for: .seconds(min(6, attempt + 1)))
            }
        }

        throw lastError ?? HTTPDownloadError.incompleteSegment
    }

    private func downloadSegment(
        _ segment: DownloadSegment,
        url: URL,
        request: DownloadRequest,
        metadata: HTTPMetadata,
        layout: HTTPTemporaryLayout,
        progress: SegmentProgress
    ) async throws {
        try await ensureActive(request.id)

        let segmentURL = layout.segmentURL(index: segment.index)
        if !FileManager.default.fileExists(atPath: segmentURL.path) {
            FileManager.default.createFile(atPath: segmentURL.path, contents: nil)
        }
        layout.setFileHidden(at: segmentURL, hidden: hidesTemporaryFiles)

        var localBytes = HTTPTemporaryLayout.localSize(at: segmentURL)
        if localBytes > segment.length {
            await progress.setDownloadedBytes(0, for: segment.index)
            try FileSystemSafety.removeSafely(
                segmentURL,
                allowedRoot: URL(fileURLWithPath: layout.savePath).deletingLastPathComponent(),
                allowsDirectories: false
            )
            FileManager.default.createFile(atPath: segmentURL.path, contents: nil)
            layout.setFileHidden(at: segmentURL, hidden: hidesTemporaryFiles)
            localBytes = 0
        }
        guard localBytes < segment.length else { return }

        let start = segment.start + localBytes
        var urlRequest = HTTPRequestFactory.makeRequest(
            url: url,
            method: "GET",
            timeoutInterval: 30,
            request: request
        )
        urlRequest.setValue("bytes=\(start)-\(segment.end)", forHTTPHeaderField: "Range")
        applyIfRange(to: &urlRequest, metadata: metadata, request: request)

        let (stream, response) = try await Self.session.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPDownloadError.invalidResponse(L10n.string("error_invalid_server_response"))
        }
        guard httpResponse.statusCode == 206 else {
            if (200...299).contains(httpResponse.statusCode) {
                throw HTTPDownloadError.rangeNotSupported
            }
            if (400...599).contains(httpResponse.statusCode) {
                if httpResponse.statusCode == 416 {
                    throw HTTPDownloadError.rangeNotSupported
                }
                throw HTTPDownloadError.serverStatus(httpResponse.statusCode)
            }
            throw HTTPDownloadError.invalidResponse(L10n.string("error_server_did_not_return_range"))
        }

        try validateRangeResponse(
            httpResponse,
            expectedStart: start,
            expectedEnd: segment.end,
            expectedTotal: metadata.contentLength,
            expectedETag: request.eTag ?? metadata.eTag,
            expectedLastModified: request.lastModified ?? metadata.lastModified
        )

        let fileHandle = try FileHandle(forWritingTo: segmentURL)
        defer {
            try? fileHandle.close()
        }
        try fileHandle.seekToEnd()

        var buffer = [UInt8]()
        buffer.reserveCapacity(Self.bufferSize)

        func flushBuffer() async throws {
            guard !buffer.isEmpty else { return }
            try await ensureActive(request.id)

            let bytes = Int64(buffer.count)
            try fileHandle.write(contentsOf: Data(buffer))
            await progress.add(bytes, to: segment.index)
            buffer.removeAll(keepingCapacity: true)
            await waitForDownloadCapacity(request: request, bytes: bytes)
        }

        for try await byte in stream {
            buffer.append(byte)
            if buffer.count >= Self.bufferSize {
                try await flushBuffer()
            }
        }
        try await flushBuffer()

        guard HTTPTemporaryLayout.localSize(at: segmentURL) == segment.length else {
            throw HTTPDownloadError.incompleteSegment
        }
    }

    private func mergeSegments(
        plan: SegmentPlan,
        layout: HTTPTemporaryLayout,
        destination: URL,
        hidesTemporaryFiles: Bool
    ) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        layout.setFileHidden(at: destination, hidden: hidesTemporaryFiles)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? output.close()
        }

        for segment in plan.segments {
            let segmentURL = layout.segmentURL(index: segment.index)
            guard HTTPTemporaryLayout.localSize(at: segmentURL) == segment.length else {
                throw HTTPDownloadError.incompleteSegment
            }

            let input = try FileHandle(forReadingFrom: segmentURL)
            defer {
                try? input.close()
            }

            while true {
                let data = try input.read(upToCount: Self.bufferSize) ?? Data()
                guard !data.isEmpty else { break }
                try output.write(contentsOf: data)
            }
        }
    }

    private func applyIfRange(
        to urlRequest: inout URLRequest,
        metadata: HTTPMetadata,
        request: DownloadRequest
    ) {
        if let eTag = request.eTag ?? metadata.eTag,
           !eTag.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("w/")
        {
            urlRequest.setValue(eTag, forHTTPHeaderField: "If-Range")
        } else if let lastModified = request.lastModified ?? metadata.lastModified {
            urlRequest.setValue(lastModified, forHTTPHeaderField: "If-Range")
        }
    }

    private func legacyManifest(
        for request: DownloadRequest,
        layout: HTTPTemporaryLayout,
        metadata: HTTPMetadata
    ) throws -> HTTPDownloadManifest {
        let totalBytes = metadata.contentLength > 0 ? metadata.contentLength : request.totalBytes
        guard totalBytes > 0 else {
            throw HTTPDownloadError.invalidLocalData(L10n.string("error_missing_segment_total_size"))
        }

        let indexes = layout.existingSegmentIndexes(maxSegments: segmentScanLimit)
        let legacySegmentCount = max(indexes.last.map { $0 + 1 } ?? segmentCount, segmentCount)
        return HTTPDownloadManifest(
            source: request.source,
            totalBytes: totalBytes,
            eTag: metadata.eTag ?? request.eTag,
            lastModified: metadata.lastModified ?? request.lastModified,
            segments: SegmentPlan
                .make(totalBytes: totalBytes, segmentCount: legacySegmentCount)
                .segments
                .map(HTTPManifestSegment.init)
        )
    }

    private func validate(
        manifest: HTTPDownloadManifest,
        request: DownloadRequest,
        against metadata: HTTPMetadata
    ) throws {
        if manifest.source != request.source {
            throw HTTPDownloadError.validatorChanged
        }
        if metadata.contentLength > 0, manifest.totalBytes != metadata.contentLength {
            throw HTTPDownloadError.validatorChanged
        }
        if let oldETag = manifest.eTag, let newETag = metadata.eTag, oldETag != newETag {
            throw HTTPDownloadError.validatorChanged
        }
        if let oldLastModified = manifest.lastModified,
           let newLastModified = metadata.lastModified,
           oldLastModified != newLastModified
        {
            throw HTTPDownloadError.validatorChanged
        }
    }

    private func validateRangeResponse(
        _ response: HTTPURLResponse,
        expectedStart: Int64,
        expectedEnd: Int64?,
        expectedTotal: Int64,
        expectedETag: String?,
        expectedLastModified: String?
    ) throws {
        guard let rawRange = response.value(forHTTPHeaderField: "Content-Range"),
              let contentRange = HTTPContentRange(rawRange)
        else {
            throw HTTPDownloadError.invalidResponse(L10n.string("error_missing_content_range"))
        }

        guard contentRange.start == expectedStart else {
            throw HTTPDownloadError.invalidResponse(L10n.string("error_content_range_start_mismatch"))
        }
        if let expectedEnd, contentRange.end != expectedEnd {
            throw HTTPDownloadError.invalidResponse(L10n.string("error_content_range_end_mismatch"))
        }
        if expectedTotal > 0, let total = contentRange.total, total != expectedTotal {
            throw HTTPDownloadError.validatorChanged
        }
        if let expectedETag,
           let responseETag = response.value(forHTTPHeaderField: "ETag"),
           responseETag != expectedETag
        {
            throw HTTPDownloadError.validatorChanged
        }
        if let expectedLastModified,
           let responseLastModified = response.value(forHTTPHeaderField: "Last-Modified"),
           responseLastModified != expectedLastModified
        {
            throw HTTPDownloadError.validatorChanged
        }
    }

    private func ensureActive(_ taskID: UUID) async throws {
        guard await runState.isActive(taskID) else {
            throw CancellationError()
        }
    }

    private func emitRetry(_ request: DownloadRequest, error: Error, attempt: Int) {
        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .running,
                totalBytes: request.totalBytes,
                downloadedBytes: HTTPTemporaryLayout(savePath: request.savePath)
                    .temporaryProgress(maxSegments: segmentScanLimit),
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: L10n.string("error_retry_attempt", attempt, error.localizedDescription),
                supportsResume: request.supportsResume,
                eTag: request.eTag,
                lastModified: request.lastModified,
                httpResponseMetadata: request.httpResponseMetadata,
                retryCount: attempt
            )
        )
    }

    private func emit(_ snapshot: DownloadSnapshot) {
        onSnapshot?(snapshot)
    }

    private func singleStreamSegments(
        totalBytes: Int64,
        downloadedBytes: Int64,
        speedBytesPerSecond: Int64
    ) -> [HTTPSegmentInfo]? {
        guard totalBytes > 0 else { return nil }
        return [
            HTTPSegmentInfo(
                index: 0,
                startByte: 0,
                endByte: totalBytes - 1,
                downloadedBytes: downloadedBytes,
                speedBytesPerSecond: speedBytesPerSecond
            )
        ]
    }

    private func connectionSummary(segmentCount: Int, supportsResume: Bool) -> String {
        let streamDescription = segmentCount > 1
            ? L10n.string("http_connection_segments", segmentCount)
            : L10n.string("http_connection_single_stream")
        let resumeDescription = supportsResume
            ? L10n.string("http_connection_resumable")
            : L10n.string("http_connection_not_resumable")
        return L10n.string("http_connection_summary", streamDescription, resumeDescription)
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        if let httpError = error as? HTTPDownloadError {
            return httpError.isRetryable
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .notConnectedToInternet,
                 .cannotLoadFromNetwork,
                 .resourceUnavailable:
                return true
            default:
                return false
            }
        }
        return false
    }

    private static func shouldFallbackToSingleStream(after error: Error) -> Bool {
        guard let httpError = error as? HTTPDownloadError else { return false }
        switch httpError {
        case .rangeNotSupported, .serverStatus(416):
            return true
        case .invalidResponse, .serverStatus, .incompleteSegment, .invalidLocalData, .localPreflight, .validatorChanged:
            return false
        }
    }

    private static func unsatisfiedRangeTotal(from response: HTTPURLResponse) -> Int64? {
        guard response.statusCode == 416,
              let rawRange = response.value(forHTTPHeaderField: "Content-Range")
        else {
            return nil
        }

        let trimmed = rawRange.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("bytes */") else { return nil }
        return Int64(trimmed.dropFirst("bytes */".count))
    }

    static func pausedSnapshot(for request: DownloadRequest) -> DownloadSnapshot {
        DownloadSnapshot(
            taskID: request.id,
            status: .paused,
            totalBytes: request.totalBytes,
            downloadedBytes: max(
                request.downloadedBytes,
                HTTPTemporaryLayout(savePath: request.savePath).temporaryProgress(maxSegments: segmentScanLimit)
            ),
            speedBytesPerSecond: 0,
            etaSeconds: nil,
            errorMessage: nil,
            supportsResume: request.supportsResume,
            eTag: request.eTag,
            lastModified: request.lastModified,
            httpResponseMetadata: request.httpResponseMetadata
        )
    }

    static func failureSnapshot(for request: DownloadRequest, message: String) -> DownloadSnapshot {
        DownloadSnapshot(
            taskID: request.id,
            status: .failed,
            totalBytes: request.totalBytes,
            downloadedBytes: max(
                request.downloadedBytes,
                HTTPTemporaryLayout(savePath: request.savePath).temporaryProgress(maxSegments: segmentScanLimit)
            ),
            speedBytesPerSecond: 0,
            etaSeconds: nil,
            errorMessage: message,
            supportsResume: request.supportsResume,
            eTag: request.eTag,
            lastModified: request.lastModified,
            httpResponseMetadata: request.httpResponseMetadata
        )
    }
}

private struct HTTPTemporaryLayout: Sendable {
    let savePath: String

    var singlePartURL: URL {
        URL(fileURLWithPath: savePath + ".part")
    }

    var manifestURL: URL {
        URL(fileURLWithPath: savePath + ".segments")
    }

    func segmentURL(index: Int) -> URL {
        URL(fileURLWithPath: savePath + ".part\(index)")
    }

    func mergeURL(for finalURL: URL) -> URL {
        URL(fileURLWithPath: finalURL.path + ".merge")
    }

    func temporaryProgress(maxSegments: Int) -> Int64 {
        max(Self.localSize(at: singlePartURL), segmentProgress(maxSegments: maxSegments))
    }

    func segmentProgress(maxSegments: Int) -> Int64 {
        (0..<maxSegments).reduce(Int64(0)) { partialResult, index in
            partialResult + Self.localSize(at: segmentURL(index: index))
        }
    }

    func segmentProgress(for plan: SegmentPlan) throws -> Int64 {
        try plan.segments.reduce(Int64(0)) { partialResult, segment in
            let size = Self.localSize(at: segmentURL(index: segment.index))
            guard size <= segment.length else {
                throw HTTPDownloadError.invalidLocalData(L10n.string("error_segment_too_large", segment.index))
            }
            return partialResult + size
        }
    }

    func segmentInfos(for plan: SegmentPlan) throws -> [HTTPSegmentInfo] {
        try plan.segments.map { segment in
            let size = Self.localSize(at: segmentURL(index: segment.index))
            guard size <= segment.length else {
                throw HTTPDownloadError.invalidLocalData(L10n.string("error_segment_too_large", segment.index))
            }
            return HTTPSegmentInfo(
                index: segment.index,
                startByte: segment.start,
                endByte: segment.end,
                downloadedBytes: size
            )
        }
    }

    func repairOversizedSegments(for plan: SegmentPlan) throws {
        for segment in plan.segments {
            let url = segmentURL(index: segment.index)
            guard Self.localSize(at: url) > segment.length else { continue }
            try FileSystemSafety.removeSafely(
                url,
                allowedRoot: URL(fileURLWithPath: savePath).deletingLastPathComponent(),
                allowsDirectories: false
            )
        }
    }

    func existingSegmentIndexes(maxSegments: Int) -> [Int] {
        (0..<maxSegments).filter { index in
            FileManager.default.fileExists(atPath: segmentURL(index: index).path)
        }
    }

    func loadManifest() throws -> HTTPDownloadManifest? {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        let data = try Data(contentsOf: manifestURL)
        guard !data.isEmpty else { return nil }
        return try JSONDecoder().decode(HTTPDownloadManifest.self, from: data)
    }

    func writeManifest(_ manifest: HTTPDownloadManifest, hidden: Bool) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
        setFileHidden(at: manifestURL, hidden: hidden)
    }

    func setFileHidden(at url: URL, hidden: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var resourceValues = URLResourceValues()
        resourceValues.isHidden = hidden
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)
    }

    func removeTemporaryFiles(maxSegments: Int) {
        let root = URL(fileURLWithPath: savePath).deletingLastPathComponent()
        _ = try? FileSystemSafety.removeSafely(singlePartURL, allowedRoot: root, allowsDirectories: false)
        _ = try? FileSystemSafety.removeSafely(manifestURL, allowedRoot: root, allowsDirectories: false)
        _ = try? FileSystemSafety.removeSafely(
            URL(fileURLWithPath: savePath + ".merge"),
            allowedRoot: root,
            allowsDirectories: false
        )
        for index in 0..<maxSegments {
            _ = try? FileSystemSafety.removeSafely(
                segmentURL(index: index),
                allowedRoot: root,
                allowsDirectories: false
            )
        }
    }

    static func localSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }
}

private struct HTTPDownloadManifest: Codable, Sendable {
    var version = 1
    var source: String
    var totalBytes: Int64
    var eTag: String?
    var lastModified: String?
    var segments: [HTTPManifestSegment]

    var segmentPlan: SegmentPlan {
        SegmentPlan(
            totalBytes: totalBytes,
            segments: segments.map {
                DownloadSegment(index: $0.index, start: $0.start, end: $0.end)
            }
        )
    }
}

private struct HTTPManifestSegment: Codable, Sendable {
    var index: Int
    var start: Int64
    var end: Int64

    init(index: Int, start: Int64, end: Int64) {
        self.index = index
        self.start = start
        self.end = end
    }

    init(_ segment: DownloadSegment) {
        self.init(index: segment.index, start: segment.start, end: segment.end)
    }
}

private struct HTTPContentRange: Sendable {
    let start: Int64
    let end: Int64
    let total: Int64?

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("bytes ") else { return nil }

        let value = trimmed.dropFirst("bytes ".count)
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        let rangeParts = parts[0].split(separator: "-", maxSplits: 1).map(String.init)
        guard rangeParts.count == 2,
              let start = Int64(rangeParts[0]),
              let end = Int64(rangeParts[1]),
              start <= end
        else {
            return nil
        }

        self.start = start
        self.end = end
        self.total = parts[1] == "*" ? nil : Int64(parts[1])
    }
}

struct HTTPMetadata: Sendable {
    var contentLength: Int64
    var supportsResume: Bool
    var eTag: String?
    var lastModified: String?
    var responseMetadata: HTTPResponseMetadata? = nil

    static let unknown = HTTPMetadata(
        contentLength: 0,
        supportsResume: false,
        eTag: nil,
        lastModified: nil,
        responseMetadata: nil
    )

    func filled(from request: DownloadRequest) -> HTTPMetadata {
        let requestMetadata = (
            request.httpResponseMetadata
                ?? HTTPResponseMetadata.fromCreationContext(
                source: request.source,
                browserContext: request.browserContext,
                suggestedFilename: request.httpOptions?.filenameOverride,
                totalBytes: request.totalBytes,
                supportsResume: request.supportsResume,
                eTag: request.eTag,
                lastModified: request.lastModified
            )
        ).replacingSuggestedFilename(request.httpOptions?.filenameOverride)
        return HTTPMetadata(
            contentLength: contentLength > 0 ? contentLength : request.totalBytes,
            supportsResume: supportsResume || request.supportsResume,
            eTag: eTag ?? request.eTag,
            lastModified: lastModified ?? request.lastModified,
            responseMetadata: responseMetadata?.merged(over: requestMetadata) ?? requestMetadata
        )
    }

    fileprivate func filled(from manifest: HTTPDownloadManifest) -> HTTPMetadata {
        let manifestMetadata = HTTPResponseMetadata(
            contentLength: manifest.totalBytes,
            eTag: manifest.eTag,
            lastModified: manifest.lastModified
        )
        return HTTPMetadata(
            contentLength: contentLength > 0 ? contentLength : manifest.totalBytes,
            supportsResume: true,
            eTag: eTag ?? manifest.eTag,
            lastModified: lastModified ?? manifest.lastModified,
            responseMetadata: responseMetadata?.merged(over: manifestMetadata) ?? manifestMetadata
        )
    }

    func merged(over fallback: HTTPMetadata) -> HTTPMetadata {
        HTTPMetadata(
            contentLength: contentLength > 0 ? contentLength : fallback.contentLength,
            supportsResume: supportsResume || fallback.supportsResume,
            eTag: eTag ?? fallback.eTag,
            lastModified: lastModified ?? fallback.lastModified,
            responseMetadata: responseMetadata?.merged(over: fallback.responseMetadata) ?? fallback.responseMetadata
        )
    }

    func merging(
        response: HTTPURLResponse,
        resumedFrom offset: Int64,
        redirects: [HTTPRedirectMetadata] = [],
        filenameOverride: String? = nil
    ) -> HTTPMetadata {
        let responseLength = response.expectedContentLength > 0 ? response.expectedContentLength : 0
        let contentRange = response
            .value(forHTTPHeaderField: "Content-Range")
            .flatMap(HTTPContentRange.init)
        let totalLength = contentRange?.total
            ?? (response.statusCode == 206 ? offset + responseLength : max(contentLength, responseLength))
        let responseETag = response.value(forHTTPHeaderField: "ETag") ?? eTag
        let responseLastModified = response.value(forHTTPHeaderField: "Last-Modified") ?? lastModified
        let canResume = supportsResume || response.statusCode == 206
        let serverMetadata = HTTPResponseMetadata(
            originalURL: responseMetadata?.originalURL,
            finalURL: response.url?.absoluteString ?? responseMetadata?.finalURL,
            sourcePageURL: responseMetadata?.sourcePageURL,
            mimeType: response.mimeType ?? contentType(from: response),
            contentDisposition: response.value(forHTTPHeaderField: "Content-Disposition"),
            suggestedFilename: filenameOverride ?? HTTPContentDisposition.suggestedFilename(
                from: response.value(forHTTPHeaderField: "Content-Disposition")
            ) ?? responseMetadata?.suggestedFilename,
            server: response.value(forHTTPHeaderField: "Server"),
            supportsResume: canResume,
            contentLength: totalLength > 0 ? totalLength : nil,
            eTag: responseETag,
            lastModified: responseLastModified,
            redirects: redirects
        )

        return HTTPMetadata(
            contentLength: totalLength,
            supportsResume: canResume,
            eTag: responseETag,
            lastModified: responseLastModified,
            responseMetadata: serverMetadata.merged(over: responseMetadata)
        )
    }

    private func contentType(from response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: "Content-Type")?
            .split(separator: ";", maxSplits: 1)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

enum HTTPDownloadError: LocalizedError, Equatable {
    case invalidResponse(String)
    case serverStatus(Int)
    case incompleteSegment
    case invalidLocalData(String)
    case localPreflight(String)
    case rangeNotSupported
    case validatorChanged

    var isRetryable: Bool {
        switch self {
        case .serverStatus(let status):
            status == 408 || status == 429 || (500...599).contains(status)
        case .incompleteSegment:
            true
        case .invalidResponse, .invalidLocalData, .localPreflight, .rangeNotSupported, .validatorChanged:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            message
        case .serverStatus(let status):
            Self.serverStatusDescription(status)
        case .incompleteSegment:
            L10n.string("error_incomplete_segment")
        case .invalidLocalData(let message):
            message
        case .localPreflight(let message):
            message
        case .rangeNotSupported:
            L10n.string("error_range_not_supported")
        case .validatorChanged:
            L10n.string("error_validator_changed")
        }
    }

    private static func serverStatusDescription(_ status: Int) -> String {
        switch status {
        case 401:
            L10n.string("error_server_status_401")
        case 403:
            L10n.string("error_server_status_403")
        case 404:
            L10n.string("error_server_status_404")
        case 416:
            L10n.string("error_server_status_416")
        case 429:
            L10n.string("error_server_status_429")
        case 500...599:
            L10n.string("error_server_status_5xx", status)
        default:
            L10n.string("error_server_status", status)
        }
    }
}

struct SegmentPlan: Sendable, Equatable {
    let totalBytes: Int64
    let segments: [DownloadSegment]

    static func make(totalBytes: Int64, segmentCount: Int) -> SegmentPlan {
        make(totalBytes: totalBytes, segmentCount: segmentCount, minSplitSize: 1)
    }

    static func make(totalBytes: Int64, segmentCount: Int, minSplitSize: Int64) -> SegmentPlan {
        guard totalBytes > 0 else {
            return SegmentPlan(totalBytes: totalBytes, segments: [])
        }

        let boundedMinSplitSize = max(1, minSplitSize)
        let maxSegmentsBySize = max(1, Int(totalBytes / boundedMinSplitSize))
        let segmentCount = max(1, min(segmentCount, Int(totalBytes), maxSegmentsBySize))
        let baseLength = totalBytes / Int64(segmentCount)
        let remainder = totalBytes % Int64(segmentCount)
        var cursor: Int64 = 0
        let segments = (0..<segmentCount).map { index in
            let length = baseLength + (Int64(index) < remainder ? 1 : 0)
            let segment = DownloadSegment(
                index: index,
                start: cursor,
                end: cursor + length - 1
            )
            cursor += length
            return segment
        }
        return SegmentPlan(totalBytes: totalBytes, segments: segments)
    }
}

struct DownloadSegment: Sendable, Equatable {
    let index: Int
    let start: Int64
    let end: Int64

    var length: Int64 {
        end - start + 1
    }
}

actor SegmentProgress {
    private var downloaded: Int64
    private var lastDownloaded: Int64
    private var lastSampledAt: Date
    private var segmentsByIndex: [Int: HTTPSegmentInfo]
    private var lastSegmentBytesByIndex: [Int: Int64]

    init(initialBytes: Int64) {
        downloaded = initialBytes
        lastDownloaded = initialBytes
        lastSampledAt = Date()
        segmentsByIndex = [:]
        lastSegmentBytesByIndex = [:]
    }

    init(segments: [HTTPSegmentInfo]) {
        segmentsByIndex = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, $0) })
        lastSegmentBytesByIndex = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, $0.downloadedBytes) })
        downloaded = segments.reduce(Int64(0)) { $0 + $1.downloadedBytes }
        lastDownloaded = downloaded
        lastSampledAt = Date()
    }

    func add(_ bytes: Int64) {
        downloaded = max(0, downloaded + bytes)
    }

    func add(_ bytes: Int64, to index: Int) {
        guard var segment = segmentsByIndex[index] else {
            add(bytes)
            return
        }
        let previous = segment.downloadedBytes
        segment = HTTPSegmentInfo(
            index: segment.index,
            startByte: segment.startByte,
            endByte: segment.endByte,
            downloadedBytes: previous + bytes,
            speedBytesPerSecond: segment.speedBytesPerSecond,
            retryCount: segment.retryCount
        )
        segmentsByIndex[index] = segment
        downloaded = max(0, downloaded + (segment.downloadedBytes - previous))
    }

    func setDownloadedBytes(_ bytes: Int64, for index: Int) {
        guard var segment = segmentsByIndex[index] else { return }
        let previous = segment.downloadedBytes
        segment = HTTPSegmentInfo(
            index: segment.index,
            startByte: segment.startByte,
            endByte: segment.endByte,
            downloadedBytes: bytes,
            speedBytesPerSecond: segment.speedBytesPerSecond,
            retryCount: segment.retryCount
        )
        segmentsByIndex[index] = segment
        downloaded = max(0, downloaded + (segment.downloadedBytes - previous))
    }

    func setRetryCount(_ count: Int, for index: Int) {
        guard var segment = segmentsByIndex[index] else { return }
        segment = HTTPSegmentInfo(
            index: segment.index,
            startByte: segment.startByte,
            endByte: segment.endByte,
            downloadedBytes: segment.downloadedBytes,
            speedBytesPerSecond: segment.speedBytesPerSecond,
            retryCount: max(segment.retryCount, count)
        )
        segmentsByIndex[index] = segment
    }

    func downloadedBytes() -> Int64 {
        downloaded
    }

    func currentSegments() -> [HTTPSegmentInfo] {
        segmentsByIndex.values.sorted { $0.index < $1.index }
    }

    func sample() -> SegmentProgressSample {
        let now = Date()
        let elapsed = max(now.timeIntervalSince(lastSampledAt), 0.001)
        let delta = max(0, downloaded - lastDownloaded)
        let speed = Int64(Double(delta) / elapsed)
        var segments = currentSegments()
        for index in segments.indices {
            let segment = segments[index]
            let lastBytes = lastSegmentBytesByIndex[segment.index] ?? segment.downloadedBytes
            let delta = max(0, segment.downloadedBytes - lastBytes)
            segments[index] = HTTPSegmentInfo(
                index: segment.index,
                startByte: segment.startByte,
                endByte: segment.endByte,
                downloadedBytes: segment.downloadedBytes,
                speedBytesPerSecond: Int64(Double(delta) / elapsed),
                retryCount: segment.retryCount
            )
        }
        segmentsByIndex = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, $0) })
        lastSegmentBytesByIndex = Dictionary(uniqueKeysWithValues: segments.map { ($0.index, $0.downloadedBytes) })
        lastDownloaded = downloaded
        lastSampledAt = now
        return SegmentProgressSample(
            downloadedBytes: downloaded,
            speedBytesPerSecond: speed,
            segments: segments
        )
    }
}

struct SegmentProgressSample: Sendable, Equatable {
    let downloadedBytes: Int64
    let speedBytesPerSecond: Int64
    let segments: [HTTPSegmentInfo]

    init(
        downloadedBytes: Int64,
        speedBytesPerSecond: Int64,
        segments: [HTTPSegmentInfo] = []
    ) {
        self.downloadedBytes = downloadedBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.segments = segments
    }
}
