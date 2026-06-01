import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftGetXCore
import SwiftGetXTorrentCore

struct TorrentMetadataPreview: Equatable, Sendable {
    var source: String
    var kind: DownloadKind
    var displayName: String
    var resolvedTorrentFilePath: String?
    var files: [TorrentFile]
    var totalBytes: Int64
    var metadataStatus: TorrentMetadataStatus
    var errorMessage: String?
    var trackers: [String]
    var webSeeds: [String]
    var httpResponseMetadata: HTTPResponseMetadata?
    var supportsResume: Bool
    var savePath: String?
    var torrentSaveDirectoryPath: String?
    var torrentOutputName: String?
    var torrentContentRootPath: String?
    var torrentFinalFilePath: String?
    var duplicateStrategy: DownloadPreviewDuplicateStrategy
    var browserContext: BrowserDownloadContext?

    var selectedFileIndexes: [Int] {
        files.map(\.index)
    }

    init(
        source: String,
        kind: DownloadKind,
        displayName: String,
        resolvedTorrentFilePath: String?,
        files: [TorrentFile],
        totalBytes: Int64,
        metadataStatus: TorrentMetadataStatus,
        errorMessage: String?,
        trackers: [String] = [],
        webSeeds: [String] = [],
        httpResponseMetadata: HTTPResponseMetadata? = nil,
        supportsResume: Bool = false,
        savePath: String? = nil,
        torrentSaveDirectoryPath: String? = nil,
        torrentOutputName: String? = nil,
        torrentContentRootPath: String? = nil,
        torrentFinalFilePath: String? = nil,
        duplicateStrategy: DownloadPreviewDuplicateStrategy = .none,
        browserContext: BrowserDownloadContext? = nil
    ) {
        self.source = source
        self.kind = kind
        self.displayName = displayName
        self.resolvedTorrentFilePath = resolvedTorrentFilePath
        self.files = files
        self.totalBytes = totalBytes
        self.metadataStatus = metadataStatus
        self.errorMessage = errorMessage
        self.trackers = trackers
        self.webSeeds = webSeeds
        self.httpResponseMetadata = httpResponseMetadata
        self.supportsResume = supportsResume
        self.savePath = savePath
        self.torrentSaveDirectoryPath = torrentSaveDirectoryPath
        self.torrentOutputName = torrentOutputName
        self.torrentContentRootPath = torrentContentRootPath
        self.torrentFinalFilePath = torrentFinalFilePath
        self.duplicateStrategy = duplicateStrategy
        self.browserContext = browserContext
    }

    func plannedForSaveDirectory(_ saveDirectory: URL) -> TorrentMetadataPreview {
        guard kind == .torrentMagnet || kind == .torrentFile else { return self }
        var preview = self
        let normalizedSaveDirectory = saveDirectory.standardizedFileURL
        preview.savePath = normalizedSaveDirectory.path
        preview.torrentSaveDirectoryPath = normalizedSaveDirectory.path

        guard let layout = try? TorrentContentLayout(
            files: files.map(\.torrentFileInfo),
            saveDirectory: normalizedSaveDirectory,
            outputName: displayName,
            isMultiFile: resolvedTorrentFilePath.flatMap { path in
                (try? TorrentMetainfo.parse(url: URL(fileURLWithPath: path)))?.isMultiFile
            }
        ) else {
            let outputName = SourceParser.sanitizeFilename(displayName)
            preview.torrentOutputName = outputName.isEmpty ? displayName : outputName
            preview.torrentContentRootPath = nil
            preview.torrentFinalFilePath = nil
            return preview
        }

        preview.torrentOutputName = layout.outputName
        preview.torrentContentRootPath = layout.contentRoot.path
        preview.torrentFinalFilePath = layout.finalFileURL?.path
        return preview
    }

    var torrentDisplayPath: String? {
        torrentFinalFilePath ?? torrentContentRootPath ?? torrentSaveDirectoryPath ?? savePath
    }
}

struct TorrentMagnetPreviewResult: Sendable {
    var displayName: String?
    var files: [TorrentFile]
    var totalBytes: Int64
    var trackers: [String]
    var webSeeds: [String]

    init(
        displayName: String? = nil,
        files: [TorrentFile],
        totalBytes: Int64? = nil,
        trackers: [String] = [],
        webSeeds: [String] = []
    ) {
        self.displayName = displayName
        self.files = files
        self.totalBytes = totalBytes ?? files.reduce(0) { $0 + $1.size }
        self.trackers = trackers
        self.webSeeds = webSeeds
    }
}

actor TorrentMetadataService {
    static let shared = TorrentMetadataService()

    private let fileManager: FileManager
    private let urlSession: URLSession
    private let magnetTimeout: Duration
    private let magnetPreview: @Sendable (String) async throws -> TorrentMagnetPreviewResult

    init(
        fileManager: FileManager = .default,
        urlSession: URLSession = .shared,
        magnetTimeout: Duration = .seconds(12),
        magnetPreview: (@Sendable (String) async throws -> TorrentMagnetPreviewResult)? = nil
    ) {
        self.fileManager = fileManager
        self.urlSession = urlSession
        self.magnetTimeout = magnetTimeout
        self.magnetPreview = magnetPreview ?? Self.defaultMagnetPreview(source:)
    }

    func preview(source: String, suggestedFilename: String? = nil) async -> TorrentMetadataPreview {
        let kind = SourceParser.kind(for: source)
        switch kind {
        case .http:
            return TorrentMetadataPreview(
                source: source,
                kind: kind,
                displayName: suggestedFilename ?? SourceParser.displayName(for: source, kind: kind),
                resolvedTorrentFilePath: nil,
                files: [],
                totalBytes: 0,
                metadataStatus: .unavailable,
                errorMessage: nil
            )
        case .torrentFile:
            return await previewTorrentFile(source: source, suggestedFilename: suggestedFilename)
        case .torrentMagnet:
            return await previewMagnet(source: source, suggestedFilename: suggestedFilename)
        }
    }

    func cachedTorrentFile(for source: String) async throws -> URL {
        if let localURL = SourceParser.localFileURL(for: source) {
            return try copyTorrentFileToCache(localURL)
        }

        guard let url = URL(string: source), url.scheme?.hasPrefix("http") == true else {
            throw TorrentMetadataError.invalidTorrentSource
        }

        let (temporaryURL, response) = try await urlSession.download(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw TorrentMetadataError.httpStatus(httpResponse.statusCode)
        }
        let cachedURL = try cacheURL(
            filename: SourceParser.displayName(for: source, kind: .torrentFile),
            preferredExtension: "torrent"
        )
        try? fileManager.removeItem(at: cachedURL)
        try fileManager.moveItem(at: temporaryURL, to: cachedURL)
        return cachedURL
    }

    private func previewTorrentFile(source: String, suggestedFilename: String?) async -> TorrentMetadataPreview {
        do {
            let cachedURL = try await cachedTorrentFile(for: source)
            let metadata = try TorrentMetainfo.parse(url: cachedURL)
            let displayName = suggestedFilename?.nonEmpty
                ?? metadata.name.nonEmpty
                ?? SourceParser.displayName(for: source, kind: .torrentFile)

            return TorrentMetadataPreview(
                source: source,
                kind: .torrentFile,
                displayName: displayName,
                resolvedTorrentFilePath: cachedURL.path,
                files: metadata.files.map {
                    TorrentFile(index: $0.index, path: $0.path, size: $0.length, progress: 0)
                },
                totalBytes: metadata.totalLength,
                metadataStatus: .available,
                errorMessage: nil,
                trackers: metadata.trackerURLs,
                webSeeds: metadata.webSeeds
            )
        } catch {
            return TorrentMetadataPreview(
                source: source,
                kind: .torrentFile,
                displayName: suggestedFilename?.nonEmpty ?? SourceParser.displayName(for: source, kind: .torrentFile),
                resolvedTorrentFilePath: nil,
                files: [],
                totalBytes: 0,
                metadataStatus: .failed,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func previewMagnet(source: String, suggestedFilename: String?) async -> TorrentMetadataPreview {
        let magnet = try? MagnetURI.parse(source)
        let magnetTrackers = magnet?.trackers ?? MagnetURI.parseTrackers(from: source)
        let magnetWebSeeds = magnet?.webSeeds ?? MagnetURI.parseWebSeeds(from: source)

        do {
            let preview = try await magnetPreviewResult(source: source)
            return TorrentMetadataPreview(
                source: source,
                kind: .torrentMagnet,
                displayName: suggestedFilename?.nonEmpty
                    ?? preview.displayName?.nonEmpty
                    ?? magnet?.displayName?.nonEmpty
                    ?? SourceParser.displayName(for: source, kind: .torrentMagnet),
                resolvedTorrentFilePath: nil,
                files: preview.files,
                totalBytes: preview.totalBytes,
                metadataStatus: .available,
                errorMessage: nil,
                trackers: Self.deduplicatedStrings(preview.trackers + magnetTrackers),
                webSeeds: Self.deduplicatedStrings(preview.webSeeds + magnetWebSeeds)
            )
        } catch {
            let metadataStatus: TorrentMetadataStatus = (error as? TorrentMetadataError) == .metadataTimeout
                ? .fetching
                : .unavailable
            return TorrentMetadataPreview(
                source: source,
                kind: .torrentMagnet,
                displayName: suggestedFilename?.nonEmpty
                    ?? magnet?.displayName?.nonEmpty
                    ?? SourceParser.displayName(for: source, kind: .torrentMagnet),
                resolvedTorrentFilePath: nil,
                files: [],
                totalBytes: magnet?.exactLength ?? 0,
                metadataStatus: metadataStatus,
                errorMessage: error.localizedDescription,
                trackers: magnetTrackers,
                webSeeds: magnetWebSeeds
            )
        }
    }

    private func magnetPreviewResult(source: String) async throws -> TorrentMagnetPreviewResult {
        let outcome = MagnetPreviewOutcome()
        let magnetPreview = self.magnetPreview
        let previewTask = Task.detached(priority: .userInitiated) {
            do {
                let preview = try await magnetPreview(source)
                await outcome.store(.success(preview))
            } catch {
                await outcome.store(.failure(error))
            }
        }
        defer { previewTask.cancel() }

        let timeoutDate = Date().addingTimeInterval(magnetTimeout.asTimeInterval)
        while true {
            if let currentOutcome = await outcome.value {
                switch currentOutcome {
                case .success(let preview):
                    return preview
                case .failure(let error):
                    throw error
                }
            }

            if Date() >= timeoutDate {
                throw TorrentMetadataError.metadataTimeout
            }

            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func defaultMagnetPreview(source: String) async throws -> TorrentMagnetPreviewResult {
        #if canImport(CSwiftGetXLibtorrent)
        if let previewer = LibtorrentMetadataPreviewer(),
           let preview = try? await previewer.preview(magnet: source)
        {
            return TorrentMagnetPreviewResult(
                displayName: preview.displayName,
                files: preview.files,
                trackers: MagnetURI.parseTrackers(from: source),
                webSeeds: MagnetURI.parseWebSeeds(from: source)
            )
        }
        #endif
        return try await SwiftTorrentMetadataPreviewer().preview(magnet: source)
    }

    private static func deduplicatedStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private actor SwiftTorrentMetadataPreviewer {
        typealias PeerTransportFactory = @Sendable (TorrentPeerEndpoint) async throws -> any TorrentPeerWireTransport
        typealias PeerDiscoveryProvider = @Sendable (Data, UInt16) async -> [TorrentDiscoveredPeer]

        private static let peerID = Data("-SGX0001-00000000000".utf8)

        private let trackerClient: TorrentTrackerClient
        private let dhtTransport: (any TorrentDHTTransport)?
        private let dhtBootstrapNodes: [String]
        private let peerTransportFactory: PeerTransportFactory
        private let peerExchangeProvider: PeerDiscoveryProvider
        private let localServiceDiscoveryProvider: PeerDiscoveryProvider
        private let maxPeerCount: Int

        init(
            trackerClient: TorrentTrackerClient = TorrentTrackerClient(
                retryPolicy: TorrentTrackerRetryPolicy(maximumRetries: 0, timeout: .seconds(3))
            ),
            dhtTransport: (any TorrentDHTTransport)? = SwiftTorrentMetadataPreviewer.defaultDHTTransport(),
            dhtBootstrapNodes: [String] = TorrentRuntimeOptions.defaultDHTBootstrapNodes,
            peerTransportFactory: @escaping PeerTransportFactory = { endpoint in
                try TorrentPeerWireTCPTransport(endpoint: endpoint, timeoutSeconds: 6)
            },
            peerExchangeProvider: @escaping PeerDiscoveryProvider = { _, _ in [] },
            localServiceDiscoveryProvider: @escaping PeerDiscoveryProvider = { _, _ in [] },
            maxPeerCount: Int = 24
        ) {
            self.trackerClient = trackerClient
            self.dhtTransport = dhtTransport
            self.dhtBootstrapNodes = dhtBootstrapNodes
            self.peerTransportFactory = peerTransportFactory
            self.peerExchangeProvider = peerExchangeProvider
            self.localServiceDiscoveryProvider = localServiceDiscoveryProvider
            self.maxPeerCount = max(1, maxPeerCount)
        }

        func preview(magnet source: String) async throws -> TorrentMagnetPreviewResult {
            let magnet = try MagnetURI.parse(source)
            let peers = await discoveredPeers(for: magnet)
            let endpoints = deduplicatedPeers(peers, limit: maxPeerCount).map(\.endpoint)
            guard !endpoints.isEmpty else {
                throw TorrentTrackerError.invalidResponse(L10n.string("torrent_tracker_no_peers"))
            }

            var lastError: Error?
            for endpoint in endpoints {
                do {
                    let transport = try await peerTransportFactory(endpoint)
                    let session = try TorrentMagnetMetadataSession(
                        infoHash: magnet.infoHashV1,
                        trackers: magnet.trackers,
                        transport: transport
                    )
                    let metainfo = try await session.fetchMetadata()
                    return TorrentMagnetPreviewResult(
                        displayName: metainfo.name,
                        files: metainfo.files.map {
                            TorrentFile(index: $0.index, path: $0.path, size: $0.length, progress: 0)
                        },
                        totalBytes: metainfo.totalLength,
                        trackers: metainfo.trackerURLs,
                        webSeeds: TorrentMetadataService.deduplicatedStrings(metainfo.webSeeds + magnet.webSeeds)
                    )
                } catch {
                    lastError = error
                }
            }

            throw lastError ?? TorrentPeerWireError.metadataExtensionUnavailable
        }

        private func discoveredPeers(for magnet: MagnetURI) async -> [TorrentDiscoveredPeer] {
            let localPort = UInt16(6_881)
            var peers = await trackerPeers(for: magnet, localPort: localPort)

            if let dhtTransport {
                peers.append(contentsOf: await dhtPeers(for: magnet, localPort: localPort, transport: dhtTransport))
            }
            peers.append(contentsOf: await peerExchangeProvider(magnet.infoHashV1, localPort))
            peers.append(contentsOf: await localServiceDiscoveryProvider(magnet.infoHashV1, localPort))

            return peers
        }

        private func trackerPeers(for magnet: MagnetURI, localPort: UInt16) async -> [TorrentDiscoveredPeer] {
            var peers = [TorrentDiscoveredPeer]()
            for tracker in magnet.trackers {
                guard let url = URL(string: tracker) else { continue }
                do {
                    let request = try TorrentTrackerAnnounceRequest(
                        trackerURL: url,
                        infoHash: magnet.infoHashV1,
                        peerID: Self.peerID,
                        port: localPort,
                        downloaded: 0,
                        left: magnet.exactLength ?? 0,
                        event: .started,
                        numWant: Int32(min(maxPeerCount, Int(Int32.max)))
                    )
                    let result = try await trackerClient.announce(request)
                    peers.append(contentsOf: result.peers.map {
                        TorrentDiscoveredPeer(endpoint: $0, source: .tracker)
                    })
                } catch {
                    continue
                }
            }
            return peers
        }

        private func dhtPeers(
            for magnet: MagnetURI,
            localPort: UInt16,
            transport: any TorrentDHTTransport
        ) async -> [TorrentDiscoveredPeer] {
            let nodes = dhtBootstrapNodes.compactMap(Self.dhtBootstrapNode)
            guard !nodes.isEmpty else { return [] }

            do {
                let client = try TorrentDHTClient(timeout: .seconds(2), transport: transport)
                let result = try await client.discoverPeers(
                    infoHash: magnet.infoHashV1,
                    bootstrapNodes: nodes,
                    announcePort: localPort,
                    maxPeers: maxPeerCount
                )
                return result.peers
            } catch {
                return []
            }
        }

        private func deduplicatedPeers(
            _ peers: [TorrentDiscoveredPeer],
            limit: Int
        ) -> [TorrentDiscoveredPeer] {
            var seen = Set<String>()
            return peers.filter {
                $0.endpoint.port > 0
                    && $0.endpoint.port <= Int(UInt16.max)
                    && !$0.endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && seen.insert($0.endpoint.address).inserted
            }
            .prefix(max(1, limit))
            .map { $0 }
        }

        private static func dhtBootstrapNode(from rawValue: String) -> TorrentDHTNode? {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let host: String
            let port: Int
            if let url = URL(string: trimmed),
               let urlHost = url.host,
               let urlPort = url.port
            {
                host = urlHost
                port = urlPort
            } else if let separator = trimmed.lastIndex(of: ":") {
                host = String(trimmed[..<separator])
                port = Int(trimmed[trimmed.index(after: separator)...]) ?? 0
            } else {
                host = trimmed
                port = 6_881
            }

            guard let node = try? TorrentDHTNode(host: host, port: port),
                  node.isUsable
            else {
                return nil
            }
            return node
        }

        private static func defaultDHTTransport() -> (any TorrentDHTTransport)? {
            #if canImport(Network)
            NetworkTorrentDHTTransport()
            #else
            nil
            #endif
        }
    }

    private func copyTorrentFileToCache(_ sourceURL: URL) throws -> URL {
        let filename = sourceURL.lastPathComponent.isEmpty
            ? L10n.string("default_torrent_task_filename")
            : sourceURL.lastPathComponent
        let cachedURL = try cacheURL(filename: filename, preferredExtension: "torrent")
        try? fileManager.removeItem(at: cachedURL)
        try fileManager.copyItem(at: sourceURL, to: cachedURL)
        return cachedURL
    }

    private func cacheURL(filename: String, preferredExtension: String) throws -> URL {
        let directory = try torrentCacheDirectory()
        let sanitized = SourceParser.sanitizeFilename(filename).nonEmpty ?? L10n.string("default_torrent_task_filename")
        let baseURL = directory.appendingPathComponent(sanitized)
        let url = baseURL.pathExtension.isEmpty
            ? baseURL.appendingPathExtension(preferredExtension)
            : baseURL
        return fileManager.uniqueFileURL(for: url)
    }

    private func torrentCacheDirectory() throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("SwiftGetX/Torrents", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor MagnetPreviewOutcome {
    private var outcome: Outcome?

    enum Outcome {
        case success(TorrentMagnetPreviewResult)
        case failure(Error)
    }

    func store(_ outcome: Outcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
    }

    var value: Outcome? {
        outcome
    }
}

enum TorrentMetadataError: LocalizedError, Equatable {
    case invalidTorrentSource
    case httpStatus(Int)
    case metadataTimeout
    case nativeEngineUnavailable
    case invalidTorrentFile
    case invalidBencode

    var errorDescription: String? {
        switch self {
        case .invalidTorrentSource:
            L10n.string("error_invalid_torrent_source")
        case .httpStatus(let status):
            L10n.string("error_server_status", status)
        case .metadataTimeout:
            L10n.string("error_torrent_metadata_timeout")
        case .nativeEngineUnavailable:
            L10n.string("torrent_native_engine_unavailable")
        case .invalidTorrentFile:
            L10n.string("error_invalid_torrent_file")
        case .invalidBencode:
            L10n.string("error_invalid_bencode")
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Duration {
    var asTimeInterval: TimeInterval {
        let components = components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
