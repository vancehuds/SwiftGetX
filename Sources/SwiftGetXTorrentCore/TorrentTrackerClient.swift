import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Network)
import Network
#endif

public enum TorrentTrackerEvent: String, Codable, CaseIterable, Sendable {
    case none
    case started
    case stopped
    case completed

    var httpValue: String? {
        self == .none ? nil : rawValue
    }

    var udpValue: UInt32 {
        switch self {
        case .none:
            0
        case .completed:
            1
        case .started:
            2
        case .stopped:
            3
        }
    }
}

public enum TorrentTrackerError: Error, Equatable, Sendable, LocalizedError {
    case invalidRequest(String)
    case unsupportedScheme(String)
    case invalidResponse(String)
    case trackerFailure(String)
    case transactionIDMismatch(expected: Int32, actual: Int32)
    case timeout
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            message
        case .unsupportedScheme(let scheme):
            "Unsupported tracker scheme: \(scheme)."
        case .invalidResponse(let message):
            message
        case .trackerFailure(let message):
            message
        case .transactionIDMismatch(let expected, let actual):
            "UDP tracker transaction id mismatch. Expected \(expected), got \(actual)."
        case .timeout:
            "Tracker request timed out."
        case .transport(let message):
            message
        }
    }
}

public struct TorrentPeerEndpoint: Codable, Equatable, Hashable, Sendable {
    public var host: String
    public var port: Int
    public var peerID: String?

    public init(host: String, port: Int, peerID: String? = nil) {
        self.host = host
        self.port = port
        self.peerID = peerID
    }

    public var address: String {
        "\(host):\(port)"
    }
}

public struct TorrentTrackerAnnounceRequest: Equatable, Sendable {
    public var trackerURL: URL
    public var infoHash: Data
    public var peerID: Data
    public var port: UInt16
    public var uploaded: Int64
    public var downloaded: Int64
    public var left: Int64
    public var event: TorrentTrackerEvent
    public var compact: Bool
    public var numWant: Int32
    public var key: UInt32

    public init(
        trackerURL: URL,
        infoHash: Data,
        peerID: Data,
        port: UInt16 = 6881,
        uploaded: Int64 = 0,
        downloaded: Int64 = 0,
        left: Int64,
        event: TorrentTrackerEvent = .started,
        compact: Bool = true,
        numWant: Int32 = 50,
        key: UInt32 = 0
    ) throws {
        guard infoHash.count == 20 else {
            throw TorrentTrackerError.invalidRequest("Tracker announce requires a 20-byte v1 info hash.")
        }
        guard peerID.count == 20 else {
            throw TorrentTrackerError.invalidRequest("Tracker announce requires a 20-byte peer id.")
        }
        guard left >= 0, uploaded >= 0, downloaded >= 0 else {
            throw TorrentTrackerError.invalidRequest("Tracker byte counters cannot be negative.")
        }
        self.trackerURL = trackerURL
        self.infoHash = infoHash
        self.peerID = peerID
        self.port = port
        self.uploaded = uploaded
        self.downloaded = downloaded
        self.left = left
        self.event = event
        self.compact = compact
        self.numWant = numWant
        self.key = key
    }

    public func httpURLRequest(timeout: Duration = .seconds(12)) throws -> URLRequest {
        guard let scheme = trackerURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            throw TorrentTrackerError.unsupportedScheme(trackerURL.scheme ?? "")
        }

        var components = URLComponents(url: trackerURL, resolvingAgainstBaseURL: false)
        let existingQuery = components?.percentEncodedQuery
        var query = existingQuery.map { $0.isEmpty ? "" : "\($0)&" } ?? ""
        query += [
            "info_hash=\(Self.percentEncoded(infoHash))",
            "peer_id=\(Self.percentEncoded(peerID))",
            "port=\(port)",
            "uploaded=\(uploaded)",
            "downloaded=\(downloaded)",
            "left=\(left)",
            "compact=\(compact ? 1 : 0)",
            "numwant=\(numWant)",
            "key=\(key)"
        ].joined(separator: "&")
        if let event = event.httpValue {
            query += "&event=\(Self.percentEncoded(Data(event.utf8)))"
        }
        components?.percentEncodedQuery = query
        guard let url = components?.url else {
            throw TorrentTrackerError.invalidRequest("Unable to build HTTP tracker announce URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout.timeInterval
        request.setValue("SwiftGetX/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func percentEncoded(_ data: Data) -> String {
        data.map { byte in
            if byte.isTrackerQueryUnreserved {
                String(UnicodeScalar(byte))
            } else {
                String(format: "%%%02X", byte)
            }
        }.joined()
    }
}

public struct TorrentTrackerAnnounceResult: Equatable, Sendable {
    public var interval: Int
    public var minInterval: Int?
    public var peers: [TorrentPeerEndpoint]
    public var seedCount: Int
    public var leecherCount: Int
    public var downloadedCount: Int
    public var warningMessage: String?

    public init(
        interval: Int,
        minInterval: Int? = nil,
        peers: [TorrentPeerEndpoint],
        seedCount: Int = -1,
        leecherCount: Int = -1,
        downloadedCount: Int = -1,
        warningMessage: String? = nil
    ) {
        self.interval = max(0, interval)
        self.minInterval = minInterval.map { max(0, $0) }
        self.peers = peers
        self.seedCount = seedCount
        self.leecherCount = leecherCount
        self.downloadedCount = downloadedCount
        self.warningMessage = warningMessage
    }

    public func nextAnnounceDate(from date: Date) -> Date {
        date.addingTimeInterval(TimeInterval(max(minInterval ?? interval, interval)))
    }
}

public protocol TorrentHTTPTrackerTransport: Sendable {
    func load(_ request: URLRequest) async throws -> Data
}

public struct URLSessionTorrentHTTPTrackerTransport: TorrentHTTPTrackerTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func load(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            if let response = response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                throw TorrentTrackerError.transport("HTTP tracker returned status \(response.statusCode).")
            }
            return data
        } catch let error as TorrentTrackerError {
            throw error
        } catch {
            throw TorrentTrackerError.transport(error.localizedDescription)
        }
    }
}

public protocol TorrentUDPTrackerTransport: Sendable {
    func send(_ data: Data, to url: URL, timeout: Duration) async throws -> Data
}

#if canImport(Network)
public struct NetworkTorrentUDPTrackerTransport: TorrentUDPTrackerTransport {
    public init() {}

    public func send(_ data: Data, to url: URL, timeout: Duration) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await Self.sendOnce(data, to: url)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TorrentTrackerError.timeout
            }
            guard let response = try await group.next() else {
                throw TorrentTrackerError.timeout
            }
            group.cancelAll()
            return response
        }
    }

    private static func sendOnce(_ data: Data, to url: URL) async throws -> Data {
        guard let host = url.host,
              let portValue = url.port,
              let port = NWEndpoint.Port(rawValue: UInt16(portValue))
        else {
            throw TorrentTrackerError.invalidRequest("UDP tracker URL must include host and port.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "SwiftGetX.UDPTracker")
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: port,
                using: .udp
            )
            let box = TrackerContinuationBox<Data>()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error {
                            box.resume(continuation, result: .failure(TorrentTrackerError.transport(error.localizedDescription)))
                            connection.cancel()
                            return
                        }
                        connection.receiveMessage { response, _, _, error in
                            if let response, !response.isEmpty {
                                box.resume(continuation, result: .success(response))
                            } else if let error {
                                box.resume(continuation, result: .failure(TorrentTrackerError.transport(error.localizedDescription)))
                            } else {
                                box.resume(continuation, result: .failure(TorrentTrackerError.invalidResponse("UDP tracker returned an empty response.")))
                            }
                            connection.cancel()
                        }
                    })
                case .failed(let error):
                    box.resume(continuation, result: .failure(TorrentTrackerError.transport(error.localizedDescription)))
                    connection.cancel()
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }
}
#else
public struct NetworkTorrentUDPTrackerTransport: TorrentUDPTrackerTransport {
    public init() {}

    public func send(_ data: Data, to url: URL, timeout: Duration) async throws -> Data {
        throw TorrentTrackerError.unsupportedScheme("udp")
    }
}
#endif

public struct TorrentTrackerRetryPolicy: Equatable, Sendable {
    public var maximumRetries: Int
    public var timeout: Duration

    public init(maximumRetries: Int = 1, timeout: Duration = .seconds(8)) {
        self.maximumRetries = max(0, maximumRetries)
        self.timeout = timeout
    }
}

public struct TorrentTrackerRandomSource: Sendable {
    public var nextTransactionID: @Sendable () -> Int32
    public var nextKey: @Sendable () -> UInt32

    public init(
        nextTransactionID: @escaping @Sendable () -> Int32 = { Int32.random(in: Int32.min...Int32.max) },
        nextKey: @escaping @Sendable () -> UInt32 = { UInt32.random(in: UInt32.min...UInt32.max) }
    ) {
        self.nextTransactionID = nextTransactionID
        self.nextKey = nextKey
    }
}

public struct TorrentTrackerClient: Sendable {
    private let httpTransport: any TorrentHTTPTrackerTransport
    private let udpTransport: any TorrentUDPTrackerTransport
    private let retryPolicy: TorrentTrackerRetryPolicy
    private let randomSource: TorrentTrackerRandomSource

    public init(
        httpTransport: any TorrentHTTPTrackerTransport = URLSessionTorrentHTTPTrackerTransport(),
        udpTransport: any TorrentUDPTrackerTransport = NetworkTorrentUDPTrackerTransport(),
        retryPolicy: TorrentTrackerRetryPolicy = TorrentTrackerRetryPolicy(),
        randomSource: TorrentTrackerRandomSource = TorrentTrackerRandomSource()
    ) {
        self.httpTransport = httpTransport
        self.udpTransport = udpTransport
        self.retryPolicy = retryPolicy
        self.randomSource = randomSource
    }

    public func announce(_ request: TorrentTrackerAnnounceRequest) async throws -> TorrentTrackerAnnounceResult {
        switch request.trackerURL.scheme?.lowercased() {
        case "http", "https":
            return try await httpAnnounce(request)
        case "udp":
            return try await udpAnnounce(request)
        case let scheme?:
            throw TorrentTrackerError.unsupportedScheme(scheme)
        case nil:
            throw TorrentTrackerError.invalidRequest("Tracker URL is missing a scheme.")
        }
    }

    private func httpAnnounce(_ request: TorrentTrackerAnnounceRequest) async throws -> TorrentTrackerAnnounceResult {
        var attempt = 0
        while true {
            do {
                let data = try await httpTransport.load(request.httpURLRequest(timeout: retryPolicy.timeout))
                return try TorrentHTTPTrackerResponse.parse(data: data).announceResult
            } catch {
                if attempt >= retryPolicy.maximumRetries {
                    throw error
                }
                attempt += 1
            }
        }
    }

    private func udpAnnounce(_ request: TorrentTrackerAnnounceRequest) async throws -> TorrentTrackerAnnounceResult {
        let key = request.key == 0 ? randomSource.nextKey() : request.key
        var attempt = 0
        while true {
            do {
                return try await udpAnnounceOnce(request, key: key)
            } catch {
                if attempt >= retryPolicy.maximumRetries {
                    throw error
                }
                attempt += 1
            }
        }
    }

    private func udpAnnounceOnce(
        _ request: TorrentTrackerAnnounceRequest,
        key: UInt32
    ) async throws -> TorrentTrackerAnnounceResult {
        let connectTransactionID = randomSource.nextTransactionID()
        let connectRequest = TorrentUDPTrackerPacket.connectRequest(transactionID: connectTransactionID)
        let connectResponse = try await udpTransport.send(
            connectRequest,
            to: request.trackerURL,
            timeout: retryPolicy.timeout
        )
        let connectionID = try TorrentUDPTrackerPacket.parseConnectResponse(
            connectResponse,
            expectedTransactionID: connectTransactionID
        )

        let announceTransactionID = randomSource.nextTransactionID()
        var announceRequest = request
        announceRequest.key = key
        let announcePacket = TorrentUDPTrackerPacket.announceRequest(
            announceRequest,
            connectionID: connectionID,
            transactionID: announceTransactionID
        )
        let announceResponse = try await udpTransport.send(
            announcePacket,
            to: request.trackerURL,
            timeout: retryPolicy.timeout
        )
        return try TorrentUDPTrackerPacket.parseAnnounceResponse(
            announceResponse,
            expectedTransactionID: announceTransactionID
        )
    }
}

public struct TorrentHTTPTrackerResponse: Equatable, Sendable {
    public var interval: Int
    public var minInterval: Int?
    public var peers: [TorrentPeerEndpoint]
    public var seedCount: Int
    public var leecherCount: Int
    public var downloadedCount: Int
    public var warningMessage: String?

    public var announceResult: TorrentTrackerAnnounceResult {
        TorrentTrackerAnnounceResult(
            interval: interval,
            minInterval: minInterval,
            peers: peers,
            seedCount: seedCount,
            leecherCount: leecherCount,
            downloadedCount: downloadedCount,
            warningMessage: warningMessage
        )
    }

    public static func parse(data: Data) throws -> TorrentHTTPTrackerResponse {
        let value: BencodeValue
        do {
            value = try BencodeParser(data: data).parse()
        } catch let error as BencodeError {
            throw TorrentTrackerError.invalidResponse(error.localizedDescription)
        }

        guard case .dictionary(let dictionary) = value else {
            throw TorrentTrackerError.invalidResponse("HTTP tracker response must be a dictionary.")
        }
        if let failure = dictionary[stringKey("failure reason")]?.stringValue {
            throw TorrentTrackerError.trackerFailure(failure)
        }
        guard let interval = dictionary[stringKey("interval")]?.integerValue, interval >= 0 else {
            throw TorrentTrackerError.invalidResponse("HTTP tracker response is missing a valid interval.")
        }

        return TorrentHTTPTrackerResponse(
            interval: Int(interval),
            minInterval: dictionary[stringKey("min interval")]?.integerValue.map(Int.init),
            peers: try peers(from: dictionary[stringKey("peers")]),
            seedCount: dictionary[stringKey("complete")]?.integerValue.map(Int.init) ?? -1,
            leecherCount: dictionary[stringKey("incomplete")]?.integerValue.map(Int.init) ?? -1,
            downloadedCount: dictionary[stringKey("downloaded")]?.integerValue.map(Int.init) ?? -1,
            warningMessage: dictionary[stringKey("warning message")]?.stringValue
        )
    }

    private static func peers(from value: BencodeValue?) throws -> [TorrentPeerEndpoint] {
        switch value {
        case .data(let data):
            return try TorrentPeerEndpoint.compactIPv4Peers(from: data)
        case .list(let peerValues):
            return try peerValues.map { value in
                guard case .dictionary(let peerDictionary) = value,
                      let host = peerDictionary[stringKey("ip")]?.stringValue,
                      let port = peerDictionary[stringKey("port")]?.integerValue,
                      port >= 0,
                      port <= UInt16.max
                else {
                    throw TorrentTrackerError.invalidResponse("Invalid non-compact peer entry.")
                }
                let peerID = peerDictionary[stringKey("peer id")]?.dataValue?.hexEncodedString
                return TorrentPeerEndpoint(host: host, port: Int(port), peerID: peerID)
            }
        case nil:
            return []
        default:
            throw TorrentTrackerError.invalidResponse("HTTP tracker peers must be compact data or a peer list.")
        }
    }
}

public enum TorrentUDPTrackerPacket {
    private static let protocolConnectionID: Int64 = 0x41727101980
    private static let actionConnect: UInt32 = 0
    private static let actionAnnounce: UInt32 = 1
    private static let actionError: UInt32 = 3

    public static func connectRequest(transactionID: Int32) -> Data {
        var data = Data()
        data.appendInt64(protocolConnectionID)
        data.appendUInt32(actionConnect)
        data.appendInt32(transactionID)
        return data
    }

    public static func announceRequest(
        _ request: TorrentTrackerAnnounceRequest,
        connectionID: Int64,
        transactionID: Int32
    ) -> Data {
        var data = Data()
        data.appendInt64(connectionID)
        data.appendUInt32(actionAnnounce)
        data.appendInt32(transactionID)
        data.append(request.infoHash)
        data.append(request.peerID)
        data.appendInt64(request.downloaded)
        data.appendInt64(request.left)
        data.appendInt64(request.uploaded)
        data.appendUInt32(request.event.udpValue)
        data.appendUInt32(0)
        data.appendUInt32(request.key)
        data.appendInt32(request.numWant)
        data.appendUInt16(request.port)
        return data
    }

    public static func parseConnectResponse(_ data: Data, expectedTransactionID: Int32) throws -> Int64 {
        let bytes = [UInt8](data)
        guard bytes.count >= 16 else {
            throw TorrentTrackerError.invalidResponse("UDP tracker connect response is too short.")
        }
        try validateAction(bytes, expectedAction: actionConnect)
        let transactionID = bytes.int32(at: 4)
        guard transactionID == expectedTransactionID else {
            throw TorrentTrackerError.transactionIDMismatch(expected: expectedTransactionID, actual: transactionID)
        }
        return bytes.int64(at: 8)
    }

    public static func parseAnnounceResponse(_ data: Data, expectedTransactionID: Int32) throws -> TorrentTrackerAnnounceResult {
        let bytes = [UInt8](data)
        guard bytes.count >= 20 else {
            throw TorrentTrackerError.invalidResponse("UDP tracker announce response is too short.")
        }
        if bytes.uint32(at: 0) == actionError {
            let message = String(data: Data(bytes.dropFirst(8)), encoding: .utf8) ?? "UDP tracker error."
            throw TorrentTrackerError.trackerFailure(message)
        }
        try validateAction(bytes, expectedAction: actionAnnounce)
        let transactionID = bytes.int32(at: 4)
        guard transactionID == expectedTransactionID else {
            throw TorrentTrackerError.transactionIDMismatch(expected: expectedTransactionID, actual: transactionID)
        }
        let peerBytes = Data(bytes.dropFirst(20))
        return TorrentTrackerAnnounceResult(
            interval: Int(bytes.int32(at: 8)),
            peers: try TorrentPeerEndpoint.compactIPv4Peers(from: peerBytes),
            seedCount: Int(bytes.int32(at: 16)),
            leecherCount: Int(bytes.int32(at: 12))
        )
    }

    private static func validateAction(_ bytes: [UInt8], expectedAction: UInt32) throws {
        let action = bytes.uint32(at: 0)
        guard action == expectedAction else {
            throw TorrentTrackerError.invalidResponse("Unexpected UDP tracker action \(action).")
        }
    }
}

public struct TorrentTrackerDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var url: String
    public var tier: Int

    public var id: String { "\(tier)-\(url)" }

    public init(url: String, tier: Int) {
        self.url = url
        self.tier = max(0, tier)
    }
}

public struct TorrentTrackerScheduleState: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable {
        case waiting
        case announcing
        case working
        case failed
    }

    public var descriptor: TorrentTrackerDescriptor
    public var status: Status
    public var failureCount: Int
    public var lastAnnounceDate: Date?
    public var nextAnnounceDate: Date?
    public var seedCount: Int
    public var leecherCount: Int
    public var downloadedCount: Int
    public var lastError: String?

    public var id: String { descriptor.id }

    public init(
        descriptor: TorrentTrackerDescriptor,
        status: Status = .waiting,
        failureCount: Int = 0,
        lastAnnounceDate: Date? = nil,
        nextAnnounceDate: Date? = nil,
        seedCount: Int = -1,
        leecherCount: Int = -1,
        downloadedCount: Int = -1,
        lastError: String? = nil
    ) {
        self.descriptor = descriptor
        self.status = status
        self.failureCount = max(0, failureCount)
        self.lastAnnounceDate = lastAnnounceDate
        self.nextAnnounceDate = nextAnnounceDate
        self.seedCount = seedCount
        self.leecherCount = leecherCount
        self.downloadedCount = downloadedCount
        self.lastError = lastError
    }
}

public struct TorrentTrackerScheduler: Equatable, Sendable {
    public private(set) var states: [TorrentTrackerScheduleState]
    public var baseBackoffSeconds: TimeInterval

    public init(
        trackers: [TorrentTrackerDescriptor],
        baseBackoffSeconds: TimeInterval = 30
    ) {
        var seen = Set<String>()
        self.states = trackers
            .filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { seen.insert("\($0.tier)-\($0.url)").inserted }
            .map { TorrentTrackerScheduleState(descriptor: $0) }
        self.baseBackoffSeconds = max(1, baseBackoffSeconds)
    }

    public init(
        announce: String?,
        announceList: [[String]],
        baseBackoffSeconds: TimeInterval = 30
    ) {
        var descriptors = [TorrentTrackerDescriptor]()
        if let announce, !announce.isEmpty {
            descriptors.append(TorrentTrackerDescriptor(url: announce, tier: 0))
        }
        descriptors.append(contentsOf: announceList.enumerated().flatMap { tier, trackers in
            trackers.map { TorrentTrackerDescriptor(url: $0, tier: tier) }
        })
        self.init(trackers: descriptors, baseBackoffSeconds: baseBackoffSeconds)
    }

    public mutating func add(_ descriptor: TorrentTrackerDescriptor) {
        guard !states.contains(where: { $0.descriptor == descriptor }) else { return }
        states.append(TorrentTrackerScheduleState(descriptor: descriptor))
    }

    public mutating func remove(url: String) {
        states.removeAll { $0.descriptor.url == url }
    }

    public mutating func nextCandidate(now: Date = Date()) -> TorrentTrackerDescriptor? {
        guard let minimumTier = states
            .filter({ $0.nextAnnounceDate.map { $0 <= now } ?? true })
            .map(\.descriptor.tier)
            .min()
        else {
            return nil
        }
        let candidates = states.enumerated()
            .filter { $0.element.descriptor.tier == minimumTier }
            .filter { $0.element.nextAnnounceDate.map { $0 <= now } ?? true }
            .sorted { lhs, rhs in
                if lhs.element.status != rhs.element.status {
                    return lhs.element.status == .working
                }
                if lhs.element.failureCount != rhs.element.failureCount {
                    return lhs.element.failureCount < rhs.element.failureCount
                }
                switch (lhs.element.lastAnnounceDate, rhs.element.lastAnnounceDate) {
                case let (left?, right?):
                    if left != right {
                        return left < right
                    }
                case (nil, .some):
                    return true
                case (.some, nil):
                    return false
                default:
                    break
                }
                return lhs.offset < rhs.offset
            }
        guard let candidate = candidates.first else { return nil }
        states[candidate.offset].status = .announcing
        states[candidate.offset].lastError = nil
        return states[candidate.offset].descriptor
    }

    public mutating func recordSuccess(
        url: String,
        result: TorrentTrackerAnnounceResult,
        now: Date = Date()
    ) {
        guard let index = states.firstIndex(where: { $0.descriptor.url == url }) else { return }
        states[index].status = .working
        states[index].failureCount = 0
        states[index].lastAnnounceDate = now
        states[index].nextAnnounceDate = result.nextAnnounceDate(from: now)
        states[index].seedCount = result.seedCount
        states[index].leecherCount = result.leecherCount
        states[index].downloadedCount = result.downloadedCount
        states[index].lastError = nil
    }

    public mutating func recordFailure(
        url: String,
        error: Error,
        now: Date = Date()
    ) {
        guard let index = states.firstIndex(where: { $0.descriptor.url == url }) else { return }
        let failureCount = states[index].failureCount + 1
        states[index].status = .failed
        states[index].failureCount = failureCount
        states[index].lastAnnounceDate = now
        states[index].nextAnnounceDate = now.addingTimeInterval(backoffSeconds(failureCount: failureCount))
        states[index].lastError = error.localizedDescription
    }

    private func backoffSeconds(failureCount: Int) -> TimeInterval {
        let exponent = min(max(0, failureCount - 1), 6)
        return baseBackoffSeconds * TimeInterval(1 << exponent)
    }
}

public struct TorrentTrackerScrapeResult: Equatable, Sendable {
    public var complete: Int
    public var downloaded: Int
    public var incomplete: Int

    public init(complete: Int, downloaded: Int, incomplete: Int) {
        self.complete = complete
        self.downloaded = downloaded
        self.incomplete = incomplete
    }
}

public enum TorrentTrackerScrape {
    public static func scrapeURL(from announceURL: URL) -> URL? {
        guard var components = URLComponents(url: announceURL, resolvingAgainstBaseURL: false),
              components.path.contains("announce")
        else {
            return nil
        }
        components.path = components.path.replacingOccurrences(of: "announce", with: "scrape")
        return components.url
    }

    public static func parse(data: Data, infoHash: Data) throws -> TorrentTrackerScrapeResult? {
        let value: BencodeValue
        do {
            value = try BencodeParser(data: data).parse()
        } catch let error as BencodeError {
            throw TorrentTrackerError.invalidResponse(error.localizedDescription)
        }
        guard case .dictionary(let root) = value,
              case .dictionary(let files)? = root[stringKey("files")],
              case .dictionary(let scrape)? = files[infoHash]
        else {
            return nil
        }
        return TorrentTrackerScrapeResult(
            complete: scrape[stringKey("complete")]?.integerValue.map(Int.init) ?? -1,
            downloaded: scrape[stringKey("downloaded")]?.integerValue.map(Int.init) ?? -1,
            incomplete: scrape[stringKey("incomplete")]?.integerValue.map(Int.init) ?? -1
        )
    }
}

private final class TrackerContinuationBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(
        _ continuation: CheckedContinuation<Value, any Error>,
        result: Result<Value, any Error>
    ) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private extension BencodeValue {
    var dataValue: Data? {
        guard case .data(let data) = self else { return nil }
        return data
    }
}

private func stringKey(_ key: String) -> Data {
    Data(key.utf8)
}

private extension TorrentPeerEndpoint {
    static func compactIPv4Peers(from data: Data) throws -> [TorrentPeerEndpoint] {
        guard data.count.isMultiple(of: 6) else {
            throw TorrentTrackerError.invalidResponse("Compact peer list length must be a multiple of 6 bytes.")
        }
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count, by: 6).map { offset in
            TorrentPeerEndpoint(
                host: "\(bytes[offset]).\(bytes[offset + 1]).\(bytes[offset + 2]).\(bytes[offset + 3])",
                port: Int(bytes.uint16(at: offset + 4))
            )
        }
    }
}

private extension UInt8 {
    var isTrackerQueryUnreserved: Bool {
        switch self {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"),
             UInt8(ascii: "."),
             UInt8(ascii: "_"),
             UInt8(ascii: "~"):
            true
        default:
            false
        }
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendInt32(_ value: Int32) {
        appendUInt32(UInt32(bitPattern: value))
    }

    mutating func appendInt64(_ value: Int64) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    var hexEncodedString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension Array where Element == UInt8 {
    func uint16(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8)
            | UInt16(self[offset + 1])
    }

    func uint32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    func int32(at offset: Int) -> Int32 {
        Int32(bitPattern: uint32(at: offset))
    }

    func int64(at offset: Int) -> Int64 {
        let value = (UInt64(self[offset]) << 56)
            | (UInt64(self[offset + 1]) << 48)
            | (UInt64(self[offset + 2]) << 40)
            | (UInt64(self[offset + 3]) << 32)
            | (UInt64(self[offset + 4]) << 24)
            | (UInt64(self[offset + 5]) << 16)
            | (UInt64(self[offset + 6]) << 8)
            | UInt64(self[offset + 7])
        return Int64(bitPattern: value)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
