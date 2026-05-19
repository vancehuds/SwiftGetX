import Foundation

@MainActor
final class HTTPDownloadEngine: DownloadEngine {
    var onSnapshot: (@Sendable (DownloadSnapshot) -> Void)?

    private let runState = HTTPDownloadRunState()
    private var segmentCount = 8
    private var retryLimit = 3

    func configure(segmentCount: Int, retryLimit: Int) {
        self.segmentCount = max(1, segmentCount)
        self.retryLimit = max(0, retryLimit)
    }

    func start(_ request: DownloadRequest) async {
        guard let url = URL(string: request.source) else {
            emitFailure(request, message: "链接格式无效")
            return
        }

        await runState.activate(request.id)
        let worker = HTTPDownloadWorker(
            segmentCount: segmentCount,
            retryLimit: retryLimit,
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
            try? FileManager.default.removeItem(atPath: request.savePath)
            HTTPTemporaryLayout(savePath: request.savePath).removeTemporaryFiles(maxSegments: segmentScanLimit)
        }
    }

    func recheck(_ request: DownloadRequest) async {
        let fileURL = URL(fileURLWithPath: request.savePath)
        let size = HTTPTemporaryLayout.localSize(at: fileURL)
        let status: DownloadStatus = request.totalBytes > 0 && size == request.totalBytes ? .completed : .failed
        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: status,
                totalBytes: request.totalBytes,
                downloadedBytes: size,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: status == .failed ? "文件大小与任务记录不一致" : nil,
                supportsResume: request.supportsResume,
                eTag: request.eTag,
                lastModified: request.lastModified,
                connectionSummary: request.supportsResume ? "HTTP · 可续传" : "HTTP · 不支持续传"
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

private let segmentScanLimit = 128

private actor HTTPDownloadRunState {
    private var activeTaskIDs = Set<UUID>()
    private var speedLimitBytesPerSecond: Int64 = 0
    private var nextDownloadSlot = Date()

    func activate(_ id: UUID) {
        activeTaskIDs.insert(id)
    }

    func deactivate(_ id: UUID) {
        activeTaskIDs.remove(id)
    }

    func isActive(_ id: UUID) -> Bool {
        activeTaskIDs.contains(id)
    }

    func setSpeedLimit(_ bytesPerSecond: Int64) {
        speedLimitBytesPerSecond = max(0, bytesPerSecond)
        nextDownloadSlot = Date()
    }

    func waitForDownloadCapacity(bytes: Int64) async {
        guard speedLimitBytesPerSecond > 0, bytes > 0 else { return }

        let now = Date()
        if nextDownloadSlot < now {
            nextDownloadSlot = now
        }

        let delay = nextDownloadSlot.timeIntervalSince(now)
        nextDownloadSlot = nextDownloadSlot.addingTimeInterval(
            Double(bytes) / Double(speedLimitBytesPerSecond)
        )

        guard delay > 0 else { return }
        try? await Task.sleep(for: .seconds(delay))
    }
}

private struct HTTPDownloadWorker: Sendable {
    private static let bufferSize = 64 * 1024
    private static let minimumSplitSize: Int64 = 1024 * 1024

    let segmentCount: Int
    let retryLimit: Int
    let runState: HTTPDownloadRunState
    let onSnapshot: (@Sendable (DownloadSnapshot) -> Void)?

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
            message: lastError?.localizedDescription ?? "下载失败"
        ))
    }

    private func download(url: URL, request: DownloadRequest) async throws {
        let destination = URL(fileURLWithPath: request.savePath)
        let layout = HTTPTemporaryLayout(savePath: request.savePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var metadata = await probe(url: url, request: request)

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
            let manifest = try layout.loadManifest()
                ?? legacyManifest(for: request, layout: layout, metadata: metadata)
            metadata = metadata.filled(from: manifest)
            try validate(manifest: manifest, request: request, against: metadata)
            try layout.writeManifest(manifest)
            try await downloadSegmented(
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
            try layout.writeManifest(manifest)
            try await downloadSegmented(
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

        var metadata = metadata
        var existingBytes = HTTPTemporaryLayout.localSize(at: layout.singlePartURL)
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
                connectionSummary: connectionSummary(segmentCount: 1, supportsResume: metadata.supportsResume)
            )
        )

        var urlRequest = makeRequest(url: url, method: "GET", timeoutInterval: 30)
        if shouldResume {
            urlRequest.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
            applyIfRange(to: &urlRequest, metadata: metadata, request: request)
        }

        let (stream, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPDownloadError.invalidResponse("服务器响应无效")
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
            metadata = metadata.merging(response: httpResponse, resumedFrom: existingBytes)
        case 200...299:
            if shouldResume {
                try Data().write(to: layout.singlePartURL)
                appendExistingBytes = false
                existingBytes = 0
            }
            metadata = metadata.merging(response: httpResponse, resumedFrom: 0)
        default:
            throw HTTPDownloadError.serverStatus(httpResponse.statusCode)
        }

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

            await runState.waitForDownloadCapacity(bytes: bytes)

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
                    connectionSummary: connectionSummary(segmentCount: 1, supportsResume: metadata.supportsResume)
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
                connectionSummary: connectionSummary(segmentCount: 1, supportsResume: metadata.supportsResume)
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
        let initialBytes = try layout.segmentProgress(for: plan)
        let progress = SegmentProgress(initialBytes: initialBytes)
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
                connectionSummary: summary
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
                connectionSummary: summary
            )
        )

        let finalURL = FileManager.default.uniqueFileURL(for: destination)
        let mergeURL = layout.mergeURL(for: finalURL)
        try? FileManager.default.removeItem(at: mergeURL)

        do {
            try mergeSegments(plan: plan, layout: layout, destination: mergeURL)
            guard HTTPTemporaryLayout.localSize(at: mergeURL) == manifest.totalBytes else {
                throw HTTPDownloadError.incompleteSegment
            }
            try FileManager.default.moveItem(at: mergeURL, to: finalURL)
        } catch {
            try? FileManager.default.removeItem(at: mergeURL)
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
                connectionSummary: summary
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
                    connectionSummary: summary
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

        let localBytes = HTTPTemporaryLayout.localSize(at: segmentURL)
        guard localBytes <= segment.length else {
            throw HTTPDownloadError.invalidLocalData("分片 \(segment.index) 大小超过预期")
        }
        guard localBytes < segment.length else { return }

        let start = segment.start + localBytes
        var urlRequest = makeRequest(url: url, method: "GET", timeoutInterval: 30)
        urlRequest.setValue("bytes=\(start)-\(segment.end)", forHTTPHeaderField: "Range")
        applyIfRange(to: &urlRequest, metadata: metadata, request: request)

        let (stream, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPDownloadError.invalidResponse("服务器响应无效")
        }
        guard httpResponse.statusCode == 206 else {
            if (400...599).contains(httpResponse.statusCode) {
                throw HTTPDownloadError.serverStatus(httpResponse.statusCode)
            }
            throw HTTPDownloadError.invalidResponse("服务器未按 Range 返回分片")
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
            await progress.add(bytes)
            buffer.removeAll(keepingCapacity: true)
            await runState.waitForDownloadCapacity(bytes: bytes)
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
        destination: URL
    ) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
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

    private func probe(url: URL, request: DownloadRequest) async -> HTTPMetadata {
        let headRequest = makeRequest(url: url, method: "HEAD", timeoutInterval: 20)
        var metadata = HTTPMetadata.unknown

        do {
            let (_, response) = try await URLSession.shared.data(for: headRequest)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                return await probeRange(url: url).filled(from: request)
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
            )
        } catch {
            metadata = .unknown
        }

        metadata = metadata.filled(from: request)
        guard !metadata.supportsResume, segmentCount > 1 || request.supportsResume else {
            return metadata
        }

        return await probeRange(url: url).merged(over: metadata)
    }

    private func probeRange(url: URL) async -> HTTPMetadata {
        var request = makeRequest(url: url, method: "GET", timeoutInterval: 20)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        do {
            let (_, response) = try await URLSession.shared.bytes(for: request)
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
                )
            default:
                return .unknown
            }
        } catch {
            return .unknown
        }
    }

    private func makeRequest(url: URL, method: String, timeoutInterval: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeoutInterval
        request.setValue("SwiftGetX", forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if url.host?.localizedCaseInsensitiveCompare("api.github.com") == .orderedSame {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        }
        return request
    }

    private func applyIfRange(
        to urlRequest: inout URLRequest,
        metadata: HTTPMetadata,
        request: DownloadRequest
    ) {
        if let eTag = request.eTag ?? metadata.eTag {
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
            throw HTTPDownloadError.invalidLocalData("缺少分片任务的总大小，无法安全恢复")
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
            throw HTTPDownloadError.invalidResponse("缺少 Content-Range")
        }

        guard contentRange.start == expectedStart else {
            throw HTTPDownloadError.invalidResponse("Content-Range 起点不匹配")
        }
        if let expectedEnd, contentRange.end != expectedEnd {
            throw HTTPDownloadError.invalidResponse("Content-Range 终点不匹配")
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
                errorMessage: "第 \(attempt) 次重试：\(error.localizedDescription)",
                supportsResume: request.supportsResume,
                eTag: request.eTag,
                lastModified: request.lastModified,
                retryCount: attempt
            )
        )
    }

    private func emit(_ snapshot: DownloadSnapshot) {
        onSnapshot?(snapshot)
    }

    private func connectionSummary(segmentCount: Int, supportsResume: Bool) -> String {
        let streamDescription = segmentCount > 1 ? "\(segmentCount) 分片" : "单流"
        let resumeDescription = supportsResume ? "可续传" : "不支持续传"
        return "HTTP · \(streamDescription) · \(resumeDescription)"
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
                 .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
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
            lastModified: request.lastModified
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
            lastModified: request.lastModified
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
                throw HTTPDownloadError.invalidLocalData("分片 \(segment.index) 大小超过预期")
            }
            return partialResult + size
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

    func writeManifest(_ manifest: HTTPDownloadManifest) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
    }

    func removeTemporaryFiles(maxSegments: Int) {
        try? FileManager.default.removeItem(at: singlePartURL)
        try? FileManager.default.removeItem(at: manifestURL)
        try? FileManager.default.removeItem(atPath: savePath + ".merge")
        for index in 0..<maxSegments {
            try? FileManager.default.removeItem(at: segmentURL(index: index))
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

    static let unknown = HTTPMetadata(
        contentLength: 0,
        supportsResume: false,
        eTag: nil,
        lastModified: nil
    )

    func filled(from request: DownloadRequest) -> HTTPMetadata {
        HTTPMetadata(
            contentLength: contentLength > 0 ? contentLength : request.totalBytes,
            supportsResume: supportsResume || request.supportsResume,
            eTag: eTag ?? request.eTag,
            lastModified: lastModified ?? request.lastModified
        )
    }

    fileprivate func filled(from manifest: HTTPDownloadManifest) -> HTTPMetadata {
        HTTPMetadata(
            contentLength: contentLength > 0 ? contentLength : manifest.totalBytes,
            supportsResume: true,
            eTag: eTag ?? manifest.eTag,
            lastModified: lastModified ?? manifest.lastModified
        )
    }

    func merged(over fallback: HTTPMetadata) -> HTTPMetadata {
        HTTPMetadata(
            contentLength: contentLength > 0 ? contentLength : fallback.contentLength,
            supportsResume: supportsResume || fallback.supportsResume,
            eTag: eTag ?? fallback.eTag,
            lastModified: lastModified ?? fallback.lastModified
        )
    }

    func merging(response: HTTPURLResponse, resumedFrom offset: Int64) -> HTTPMetadata {
        let responseLength = response.expectedContentLength > 0 ? response.expectedContentLength : 0
        let contentRange = response
            .value(forHTTPHeaderField: "Content-Range")
            .flatMap(HTTPContentRange.init)
        let totalLength = contentRange?.total
            ?? (response.statusCode == 206 ? offset + responseLength : max(contentLength, responseLength))

        return HTTPMetadata(
            contentLength: totalLength,
            supportsResume: supportsResume || response.statusCode == 206,
            eTag: response.value(forHTTPHeaderField: "ETag") ?? eTag,
            lastModified: response.value(forHTTPHeaderField: "Last-Modified") ?? lastModified
        )
    }
}

enum HTTPDownloadError: LocalizedError, Equatable {
    case invalidResponse(String)
    case serverStatus(Int)
    case incompleteSegment
    case invalidLocalData(String)
    case validatorChanged

    var isRetryable: Bool {
        switch self {
        case .serverStatus(let status):
            status == 408 || status == 429 || (500...599).contains(status)
        case .incompleteSegment:
            true
        case .invalidResponse, .invalidLocalData, .validatorChanged:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            message
        case .serverStatus(let status):
            "服务器返回 HTTP \(status)"
        case .incompleteSegment:
            "下载分片不完整"
        case .invalidLocalData(let message):
            message
        case .validatorChanged:
            "服务器文件已变化，已保留临时文件以避免合并错误数据"
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

    init(initialBytes: Int64) {
        downloaded = initialBytes
        lastDownloaded = initialBytes
        lastSampledAt = Date()
    }

    func add(_ bytes: Int64) {
        downloaded += bytes
    }

    func downloadedBytes() -> Int64 {
        downloaded
    }

    func sample() -> SegmentProgressSample {
        let now = Date()
        let elapsed = max(now.timeIntervalSince(lastSampledAt), 0.001)
        let delta = max(0, downloaded - lastDownloaded)
        let speed = Int64(Double(delta) / elapsed)
        lastDownloaded = downloaded
        lastSampledAt = now
        return SegmentProgressSample(
            downloadedBytes: downloaded,
            speedBytesPerSecond: speed
        )
    }
}

struct SegmentProgressSample: Sendable, Equatable {
    let downloadedBytes: Int64
    let speedBytesPerSecond: Int64
}
