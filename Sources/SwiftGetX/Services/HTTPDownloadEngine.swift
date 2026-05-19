import Foundation

@MainActor
final class HTTPDownloadEngine: DownloadEngine {
    var onSnapshot: (@Sendable (DownloadSnapshot) -> Void)?

    private var activeTaskIDs = Set<UUID>()
    private var speedLimitBytesPerSecond: Int64 = 0
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

        activeTaskIDs.insert(request.id)

        var lastError: Error?
        for attempt in 0...retryLimit {
            guard activeTaskIDs.contains(request.id) else {
                emitPaused(request)
                return
            }

            do {
                try await download(url: url, request: request)
                activeTaskIDs.remove(request.id)
                return
            } catch is CancellationError {
                activeTaskIDs.remove(request.id)
                emitPaused(request)
                return
            } catch {
                lastError = error
                if attempt < retryLimit {
                    emitRetry(request, error: error, attempt: attempt + 1)
                    try? await Task.sleep(for: .seconds(min(6, attempt + 1)))
                }
            }
        }

        activeTaskIDs.remove(request.id)
        emitFailure(request, message: lastError?.localizedDescription ?? "下载失败")
    }

    func pause(_ request: DownloadRequest) async {
        activeTaskIDs.remove(request.id)
        emitPaused(request)
    }

    func resume(_ request: DownloadRequest) async {
        await start(request)
    }

    func cancel(_ request: DownloadRequest) async {
        activeTaskIDs.remove(request.id)
    }

    func remove(_ request: DownloadRequest, deletingFiles: Bool) async {
        await cancel(request)
        if deletingFiles {
            try? FileManager.default.removeItem(atPath: request.savePath)
            try? FileManager.default.removeItem(atPath: partPath(for: request))
            for index in 0..<segmentCount {
                try? FileManager.default.removeItem(atPath: segmentPath(for: request, index: index))
            }
            try? FileManager.default.removeItem(atPath: segmentProgressPath(for: request))
        }
    }

    func recheck(_ request: DownloadRequest) async {
        let fileURL = URL(fileURLWithPath: request.savePath)
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? 0
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
                lastModified: request.lastModified
            )
        )
    }

    func setFileSelection(_ request: DownloadRequest, selectedFileIndexes: [Int]) async {}

    func setSpeedLimit(downloadBytesPerSecond: Int64, uploadBytesPerSecond: Int64) async {
        speedLimitBytesPerSecond = max(0, downloadBytesPerSecond)
    }

    private func download(url: URL, request: DownloadRequest) async throws {
        let destination = URL(fileURLWithPath: request.savePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let partURL = URL(fileURLWithPath: partPath(for: request))
        let segmentProgressURL = URL(fileURLWithPath: segmentProgressPath(for: request))
        let existingBytes = max(localSize(at: partURL), segmentProgressSize(for: request))
        let metadata = await probe(url: url, existingBytes: existingBytes)

        if metadata.supportsResume, metadata.contentLength > 0, segmentCount > 1 {
            try await downloadSegmented(
                url: url,
                request: request,
                metadata: metadata,
                destination: destination,
                segmentProgressURL: segmentProgressURL
            )
            return
        }

        if !FileManager.default.fileExists(atPath: partURL.path) {
            FileManager.default.createFile(atPath: partURL.path, contents: nil)
        }

        let shouldResume = metadata.supportsResume && existingBytes > 0
        let startOffset = shouldResume ? existingBytes : 0

        if !shouldResume && existingBytes > 0 {
            try Data().write(to: partURL)
        }

        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .running,
                totalBytes: metadata.contentLength,
                downloadedBytes: startOffset,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: nil,
                supportsResume: metadata.supportsResume,
                eTag: metadata.eTag,
                lastModified: metadata.lastModified
            )
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 30
        if shouldResume {
            urlRequest.setValue("bytes=\(startOffset)-", forHTTPHeaderField: "Range")
            if let eTag = request.eTag ?? metadata.eTag {
                urlRequest.setValue(eTag, forHTTPHeaderField: "If-Range")
            } else if let lastModified = request.lastModified ?? metadata.lastModified {
                urlRequest.setValue(lastModified, forHTTPHeaderField: "If-Range")
            }
        }

        let (stream, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            throw HTTPDownloadError.invalidResponse
        }

        let responseMetadata = metadata.merging(response: httpResponse, resumedFrom: startOffset)
        let fileHandle = try FileHandle(forWritingTo: partURL)
        defer {
            try? fileHandle.close()
        }
        try fileHandle.seekToEnd()

        var downloadedBytes = startOffset
        var bytesSinceLastTick: Int64 = 0
        var lastTick = Date()
        var lastEmit = Date()

        for try await byte in stream {
            guard activeTaskIDs.contains(request.id) else {
                throw CancellationError()
            }

            try fileHandle.write(contentsOf: [byte])
            downloadedBytes += 1
            bytesSinceLastTick += 1

            if speedLimitBytesPerSecond > 0 {
                await throttle(bytesSinceLastTick, since: lastTick)
            }

            let now = Date()
            if now.timeIntervalSince(lastEmit) >= 0.35 {
                let elapsed = max(now.timeIntervalSince(lastTick), 0.001)
                let speed = Int64(Double(bytesSinceLastTick) / elapsed)
                let remaining = responseMetadata.contentLength > 0
                    ? max(0, responseMetadata.contentLength - downloadedBytes)
                    : 0
                let eta = speed > 0 && remaining > 0 ? TimeInterval(remaining / speed) : nil

                emit(
                    DownloadSnapshot(
                        taskID: request.id,
                        status: .running,
                        totalBytes: responseMetadata.contentLength,
                        downloadedBytes: downloadedBytes,
                        speedBytesPerSecond: speed,
                        etaSeconds: eta,
                        errorMessage: nil,
                        supportsResume: responseMetadata.supportsResume,
                        eTag: responseMetadata.eTag,
                        lastModified: responseMetadata.lastModified
                    )
                )

                lastEmit = now
                lastTick = now
                bytesSinceLastTick = 0
            }
        }

        let finalURL = FileManager.default.uniqueFileURL(for: destination)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: partURL, to: finalURL)

        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .completed,
                savePath: finalURL.path,
                totalBytes: max(responseMetadata.contentLength, downloadedBytes),
                downloadedBytes: downloadedBytes,
                speedBytesPerSecond: 0,
                etaSeconds: 0,
                errorMessage: nil,
                supportsResume: responseMetadata.supportsResume,
                eTag: responseMetadata.eTag,
                lastModified: responseMetadata.lastModified
            )
        )
    }

    private func downloadSegmented(
        url: URL,
        request: DownloadRequest,
        metadata: HTTPMetadata,
        destination: URL,
        segmentProgressURL: URL
    ) async throws {
        let plan = SegmentPlan.make(totalBytes: metadata.contentLength, segmentCount: segmentCount)
        let progress = SegmentProgress(initialBytes: segmentProgressSize(for: request))
        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .running,
                totalBytes: metadata.contentLength,
                downloadedBytes: segmentProgressSize(for: request),
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: nil,
                supportsResume: true,
                eTag: metadata.eTag,
                lastModified: metadata.lastModified
            )
        )

        let progressReporter = Task { [weak self] in
            await self?.reportSegmentProgress(
                request: request,
                metadata: metadata,
                progress: progress
            )
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for segment in plan.segments {
                    group.addTask {
                        try await self.downloadSegment(
                            segment,
                            url: url,
                            request: request,
                            metadata: metadata,
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
        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .running,
                totalBytes: metadata.contentLength,
                downloadedBytes: downloaded,
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: nil,
                supportsResume: true,
                eTag: metadata.eTag,
                lastModified: metadata.lastModified
            )
        )

        let finalURL = FileManager.default.uniqueFileURL(for: destination)
        try mergeSegments(for: request, plan: plan, destination: finalURL)
        try? FileManager.default.removeItem(at: segmentProgressURL)

        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .completed,
                savePath: finalURL.path,
                totalBytes: metadata.contentLength,
                downloadedBytes: metadata.contentLength,
                speedBytesPerSecond: 0,
                etaSeconds: 0,
                errorMessage: nil,
                supportsResume: true,
                eTag: metadata.eTag,
                lastModified: metadata.lastModified
            )
        )
    }

    private func reportSegmentProgress(
        request: DownloadRequest,
        metadata: HTTPMetadata,
        progress: SegmentProgress
    ) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(350))
            guard activeTaskIDs.contains(request.id) else { return }
            let sample = await progress.sample()
            let remaining = max(0, metadata.contentLength - sample.downloadedBytes)
            let eta = sample.speedBytesPerSecond > 0 && remaining > 0
                ? TimeInterval(remaining / sample.speedBytesPerSecond)
                : nil
            emit(
                DownloadSnapshot(
                    taskID: request.id,
                    status: .running,
                    totalBytes: metadata.contentLength,
                    downloadedBytes: sample.downloadedBytes,
                    speedBytesPerSecond: sample.speedBytesPerSecond,
                    etaSeconds: eta,
                    errorMessage: nil,
                    supportsResume: true,
                    eTag: metadata.eTag,
                    lastModified: metadata.lastModified
                )
            )
        }
    }

    private func downloadSegment(
        _ segment: DownloadSegment,
        url: URL,
        request: DownloadRequest,
        metadata: HTTPMetadata,
        progress: SegmentProgress
    ) async throws {
        let segmentURL = URL(fileURLWithPath: segmentPath(for: request, index: segment.index))
        if !FileManager.default.fileExists(atPath: segmentURL.path) {
            FileManager.default.createFile(atPath: segmentURL.path, contents: nil)
        }

        let localBytes = localSize(at: segmentURL)
        guard localBytes < segment.length else { return }

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 30
        let start = segment.start + localBytes
        urlRequest.setValue("bytes=\(start)-\(segment.end)", forHTTPHeaderField: "Range")
        if let eTag = request.eTag ?? metadata.eTag {
            urlRequest.setValue(eTag, forHTTPHeaderField: "If-Range")
        } else if let lastModified = request.lastModified ?? metadata.lastModified {
            urlRequest.setValue(lastModified, forHTTPHeaderField: "If-Range")
        }

        let (stream, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 206 || (segment.start == 0 && httpResponse.statusCode == 200)
        else {
            throw HTTPDownloadError.invalidResponse
        }

        let fileHandle = try FileHandle(forWritingTo: segmentURL)
        defer {
            try? fileHandle.close()
        }
        try fileHandle.seekToEnd()

        var bytesSinceLastTick: Int64 = 0
        var lastTick = Date()

        for try await byte in stream {
            guard activeTaskIDs.contains(request.id) else {
                throw CancellationError()
            }

            try fileHandle.write(contentsOf: [byte])
            await progress.add(1)
            bytesSinceLastTick += 1

            if speedLimitBytesPerSecond > 0 {
                await throttle(bytesSinceLastTick, since: lastTick)
                if Date().timeIntervalSince(lastTick) >= 0.35 {
                    lastTick = Date()
                    bytesSinceLastTick = 0
                }
            }
        }
    }

    private func mergeSegments(for request: DownloadRequest, plan: SegmentPlan, destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        FileManager.default.createFile(atPath: destination.path, contents: nil)

        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? output.close()
        }

        for segment in plan.segments {
            let segmentURL = URL(fileURLWithPath: segmentPath(for: request, index: segment.index))
            guard localSize(at: segmentURL) == segment.length else {
                throw HTTPDownloadError.incompleteSegment
            }
            let input = try FileHandle(forReadingFrom: segmentURL)
            defer {
                try? input.close()
            }
            try output.write(contentsOf: input.readDataToEndOfFile())
            try? FileManager.default.removeItem(at: segmentURL)
        }
    }

    private func probe(url: URL, existingBytes: Int64) async -> HTTPMetadata {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .unknown
            }

            let length = Int64(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "") ?? 0
            let acceptRanges = httpResponse.value(forHTTPHeaderField: "Accept-Ranges")?.localizedCaseInsensitiveContains("bytes") ?? false
            return HTTPMetadata(
                contentLength: existingBytes > 0 && acceptRanges ? length : max(length, existingBytes),
                supportsResume: acceptRanges,
                eTag: httpResponse.value(forHTTPHeaderField: "ETag"),
                lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified")
            )
        } catch {
            return .unknown
        }
    }

    private func throttle(_ bytesSinceTick: Int64, since date: Date) async {
        guard speedLimitBytesPerSecond > 0 else { return }
        let expected = Double(bytesSinceTick) / Double(speedLimitBytesPerSecond)
        let elapsed = Date().timeIntervalSince(date)
        guard expected > elapsed else { return }
        try? await Task.sleep(for: .seconds(expected - elapsed))
    }

    private func emitRetry(_ request: DownloadRequest, error: Error, attempt: Int) {
        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .running,
                totalBytes: request.totalBytes,
                downloadedBytes: localSize(at: URL(fileURLWithPath: partPath(for: request))),
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: "第 \(attempt) 次重试：\(error.localizedDescription)",
                supportsResume: request.supportsResume,
                eTag: request.eTag,
                lastModified: request.lastModified
            )
        )
    }

    private func emitPaused(_ request: DownloadRequest) {
        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .paused,
                totalBytes: request.totalBytes,
                downloadedBytes: max(
                    request.downloadedBytes,
                    localSize(at: URL(fileURLWithPath: partPath(for: request))),
                    segmentProgressSize(for: request)
                ),
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: nil,
                supportsResume: request.supportsResume,
                eTag: request.eTag,
                lastModified: request.lastModified
            )
        )
    }

    private func emitFailure(_ request: DownloadRequest, message: String) {
        emit(
            DownloadSnapshot(
                taskID: request.id,
                status: .failed,
                totalBytes: request.totalBytes,
                downloadedBytes: max(
                    request.downloadedBytes,
                    localSize(at: URL(fileURLWithPath: partPath(for: request))),
                    segmentProgressSize(for: request)
                ),
                speedBytesPerSecond: 0,
                etaSeconds: nil,
                errorMessage: message,
                supportsResume: request.supportsResume,
                eTag: request.eTag,
                lastModified: request.lastModified
            )
        )
    }

    private func emit(_ snapshot: DownloadSnapshot) {
        onSnapshot?(snapshot)
    }

    private func partPath(for request: DownloadRequest) -> String {
        request.savePath + ".part"
    }

    private func segmentPath(for request: DownloadRequest, index: Int) -> String {
        request.savePath + ".part\(index)"
    }

    private func segmentProgressPath(for request: DownloadRequest) -> String {
        request.savePath + ".segments"
    }

    private func segmentProgressSize(for request: DownloadRequest) -> Int64 {
        (0..<segmentCount).reduce(Int64(0)) { partialResult, index in
            partialResult + localSize(at: URL(fileURLWithPath: segmentPath(for: request, index: index)))
        }
    }

    private func localSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
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

    func merging(response: HTTPURLResponse, resumedFrom offset: Int64) -> HTTPMetadata {
        let responseLength = response.expectedContentLength > 0 ? response.expectedContentLength : 0
        let totalLength = response.statusCode == 206
            ? offset + responseLength
            : max(contentLength, responseLength)

        return HTTPMetadata(
            contentLength: totalLength,
            supportsResume: supportsResume || response.statusCode == 206,
            eTag: response.value(forHTTPHeaderField: "ETag") ?? eTag,
            lastModified: response.value(forHTTPHeaderField: "Last-Modified") ?? lastModified
        )
    }
}

enum HTTPDownloadError: LocalizedError {
    case invalidResponse
    case incompleteSegment

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "服务器响应无效"
        case .incompleteSegment:
            "下载分片不完整"
        }
    }
}

struct SegmentPlan: Sendable, Equatable {
    let totalBytes: Int64
    let segments: [DownloadSegment]

    static func make(totalBytes: Int64, segmentCount: Int) -> SegmentPlan {
        let segmentCount = max(1, min(segmentCount, Int(totalBytes)))
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
