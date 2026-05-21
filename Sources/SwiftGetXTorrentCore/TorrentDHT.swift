import Foundation
#if canImport(Network)
import Network
#endif

public enum TorrentPeerDiscoverySource: String, Codable, CaseIterable, Sendable {
    case tracker
    case dht
    case pex
    case lsd
}

public struct TorrentDiscoveredPeer: Codable, Equatable, Hashable, Sendable {
    public var endpoint: TorrentPeerEndpoint
    public var source: TorrentPeerDiscoverySource

    public init(endpoint: TorrentPeerEndpoint, source: TorrentPeerDiscoverySource) {
        self.endpoint = endpoint
        self.source = source
    }
}

public enum TorrentDHTError: Error, Equatable, Sendable, LocalizedError {
    case invalidNodeID
    case invalidInfoHash
    case invalidTransactionID
    case invalidResponse(String)
    case transport(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .invalidNodeID:
            "DHT node id must be 20 bytes."
        case .invalidInfoHash:
            "DHT lookup requires a 20-byte v1 info hash."
        case .invalidTransactionID:
            "DHT response transaction id did not match the request."
        case .invalidResponse(let message):
            message
        case .transport(let message):
            message
        case .timeout:
            "DHT request timed out."
        }
    }
}

public struct TorrentDHTNode: Codable, Equatable, Hashable, Sendable {
    public var id: Data?
    public var host: String
    public var port: Int
    public var lastSeen: Date?
    public var failureCount: Int

    public init(
        id: Data? = nil,
        host: String,
        port: Int,
        lastSeen: Date? = nil,
        failureCount: Int = 0
    ) throws {
        if let id, id.count != 20 {
            throw TorrentDHTError.invalidNodeID
        }
        self.id = id
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
        self.lastSeen = lastSeen
        self.failureCount = max(0, failureCount)
    }

    public var address: String {
        "\(host):\(port)"
    }

    public var isUsable: Bool {
        !host.isEmpty && port > 0 && port <= Int(UInt16.max)
    }
}

public struct TorrentDHTRoutingTable: Codable, Equatable, Sendable {
    public private(set) var nodes: [TorrentDHTNode]

    public init(nodes: [TorrentDHTNode] = []) {
        self.nodes = []
        add(contentsOf: nodes)
    }

    public mutating func add(_ node: TorrentDHTNode, now: Date = Date()) {
        guard node.isUsable else { return }
        var updated = node
        updated.lastSeen = node.lastSeen ?? now
        if let index = nodes.firstIndex(where: { $0.address == node.address }) {
            nodes[index] = updated
        } else {
            nodes.append(updated)
        }
        nodes.sort { lhs, rhs in
            if lhs.failureCount != rhs.failureCount {
                return lhs.failureCount < rhs.failureCount
            }
            return lhs.address < rhs.address
        }
        if nodes.count > 256 {
            nodes.removeLast(nodes.count - 256)
        }
    }

    public mutating func add(contentsOf nodes: [TorrentDHTNode], now: Date = Date()) {
        for node in nodes {
            add(node, now: now)
        }
    }

    public mutating func recordFailure(for node: TorrentDHTNode) {
        guard let index = nodes.firstIndex(where: { $0.address == node.address }) else { return }
        nodes[index].failureCount += 1
    }

    public func closestNodes(to target: Data, limit: Int) -> [TorrentDHTNode] {
        nodes
            .filter(\.isUsable)
            .sorted { lhs, rhs in
                let lhsDistance = lhs.distance(to: target)
                let rhsDistance = rhs.distance(to: target)
                if lhsDistance != rhsDistance {
                    return lhsDistance.lexicographicallyPrecedes(rhsDistance)
                }
                if lhs.failureCount != rhs.failureCount {
                    return lhs.failureCount < rhs.failureCount
                }
                return lhs.address < rhs.address
            }
            .prefix(max(0, limit))
            .map { $0 }
    }
}

public struct TorrentDHTNodeStore: @unchecked Sendable {
    public var url: URL
    private let fileManager: FileManager

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    public func load() throws -> [TorrentDHTNode] {
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([TorrentDHTNode].self, from: data)
            .filter(\.isUsable)
    }

    public func save(_ nodes: [TorrentDHTNode]) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(nodes.filter(\.isUsable))
        try data.write(to: url, options: .atomic)
    }
}

public struct TorrentDHTKRPCResponse: Equatable, Sendable {
    public var transactionID: Data
    public var responderID: Data?
    public var nodes: [TorrentDHTNode]
    public var peers: [TorrentPeerEndpoint]
    public var token: Data?

    public init(
        transactionID: Data,
        responderID: Data? = nil,
        nodes: [TorrentDHTNode] = [],
        peers: [TorrentPeerEndpoint] = [],
        token: Data? = nil
    ) {
        self.transactionID = transactionID
        self.responderID = responderID
        self.nodes = nodes
        self.peers = peers
        self.token = token
    }
}

public enum TorrentDHTKRPC {
    public static func pingRequest(transactionID: Data, nodeID: Data) throws -> Data {
        try queryRequest(
            transactionID: transactionID,
            query: "ping",
            arguments: [
                "id": .data(validNodeID(nodeID))
            ]
        )
    }

    public static func findNodeRequest(
        transactionID: Data,
        nodeID: Data,
        target: Data
    ) throws -> Data {
        try queryRequest(
            transactionID: transactionID,
            query: "find_node",
            arguments: [
                "id": .data(validNodeID(nodeID)),
                "target": .data(validNodeID(target))
            ]
        )
    }

    public static func getPeersRequest(
        transactionID: Data,
        nodeID: Data,
        infoHash: Data
    ) throws -> Data {
        try queryRequest(
            transactionID: transactionID,
            query: "get_peers",
            arguments: [
                "id": .data(validNodeID(nodeID)),
                "info_hash": .data(validInfoHash(infoHash))
            ]
        )
    }

    public static func announcePeerRequest(
        transactionID: Data,
        nodeID: Data,
        infoHash: Data,
        port: UInt16,
        token: Data,
        impliedPort: Bool = false
    ) throws -> Data {
        try queryRequest(
            transactionID: transactionID,
            query: "announce_peer",
            arguments: [
                "id": .data(validNodeID(nodeID)),
                "implied_port": .integer(impliedPort ? 1 : 0),
                "info_hash": .data(validInfoHash(infoHash)),
                "port": .integer(Int64(port)),
                "token": .data(token)
            ]
        )
    }

    public static func response(
        transactionID: Data,
        nodeID: Data,
        nodes: [TorrentDHTNode] = [],
        peers: [TorrentPeerEndpoint] = [],
        token: Data? = nil
    ) throws -> Data {
        var response: [String: BencodeValue] = [
            "id": .data(try validNodeID(nodeID))
        ]
        if !nodes.isEmpty {
            response["nodes"] = .data(compactNodes(nodes))
        }
        if !peers.isEmpty {
            response["values"] = .list([.data(compactPeers(peers))])
        }
        if let token {
            response["token"] = .data(token)
        }
        return BencodeValue.dictionary([
            key("r"): .dictionary(dictionary(response)),
            key("t"): .data(transactionID),
            key("y"): .data(Data("r".utf8))
        ]).encoded()
    }

    public static func parseResponse(_ data: Data, expectedTransactionID: Data) throws -> TorrentDHTKRPCResponse {
        let value: BencodeValue
        do {
            value = try BencodeParser(
                data: data,
                limits: BencodeLimits(maximumInputBytes: 64 * 1024, maximumDepth: 16)
            ).parse()
        } catch let error as BencodeError {
            throw TorrentDHTError.invalidResponse(error.localizedDescription)
        }
        guard case .dictionary(let root) = value else {
            throw TorrentDHTError.invalidResponse("DHT response root must be a dictionary.")
        }
        guard let transactionID = root[key("t")]?.dataValue,
              transactionID == expectedTransactionID
        else {
            throw TorrentDHTError.invalidTransactionID
        }
        guard let type = root[key("y")]?.stringValue else {
            throw TorrentDHTError.invalidResponse("DHT response is missing message type.")
        }
        if type == "e" {
            let message = root[key("e")]?.listValue?.last?.stringValue ?? "DHT query failed."
            throw TorrentDHTError.invalidResponse(message)
        }
        guard type == "r",
              let response = root[key("r")]?.dictionaryValue
        else {
            throw TorrentDHTError.invalidResponse("DHT response must contain an r dictionary.")
        }
        let responderID = response[key("id")]?.dataValue
        if let responderID, responderID.count != 20 {
            throw TorrentDHTError.invalidResponse("DHT responder id must be 20 bytes.")
        }
        let nodes = try response[key("nodes")]?.dataValue.map(compactNodes) ?? []
        let peers = try compactPeers(from: response[key("values")])
        return TorrentDHTKRPCResponse(
            transactionID: transactionID,
            responderID: responderID,
            nodes: nodes,
            peers: peers,
            token: response[key("token")]?.dataValue
        )
    }

    public static func compactNodes(_ nodes: [TorrentDHTNode]) -> Data {
        var data = Data()
        for node in nodes where node.id?.count == 20 && node.isUsable {
            data.append(node.id ?? Data())
            data.append(compactIPv4(host: node.host) ?? Data())
            data.appendUInt16(UInt16(node.port))
        }
        return data
    }

    public static func compactPeers(_ peers: [TorrentPeerEndpoint]) -> Data {
        var data = Data()
        for peer in peers {
            guard let host = compactIPv4(host: peer.host),
                  peer.port > 0,
                  peer.port <= Int(UInt16.max)
            else {
                continue
            }
            data.append(host)
            data.appendUInt16(UInt16(peer.port))
        }
        return data
    }

    public static func compactNodes(_ data: Data) throws -> [TorrentDHTNode] {
        guard data.count.isMultiple(of: 26) else {
            throw TorrentDHTError.invalidResponse("Compact DHT node list length must be a multiple of 26 bytes.")
        }
        let bytes = [UInt8](data)
        return try stride(from: 0, to: bytes.count, by: 26).map { offset in
            try TorrentDHTNode(
                id: Data(bytes[offset..<offset + 20]),
                host: "\(bytes[offset + 20]).\(bytes[offset + 21]).\(bytes[offset + 22]).\(bytes[offset + 23])",
                port: Int(bytes.uint16(at: offset + 24))
            )
        }
        .filter(\.isUsable)
    }

    public static func compactPeers(_ data: Data) throws -> [TorrentPeerEndpoint] {
        guard data.count.isMultiple(of: 6) else {
            throw TorrentDHTError.invalidResponse("Compact peer list length must be a multiple of 6 bytes.")
        }
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count, by: 6).compactMap { offset in
            let port = Int(bytes.uint16(at: offset + 4))
            guard port > 0 else { return nil }
            return TorrentPeerEndpoint(
                host: "\(bytes[offset]).\(bytes[offset + 1]).\(bytes[offset + 2]).\(bytes[offset + 3])",
                port: port
            )
        }
    }

    private static func compactPeers(from value: BencodeValue?) throws -> [TorrentPeerEndpoint] {
        guard let value else { return [] }
        guard let values = value.listValue else {
            throw TorrentDHTError.invalidResponse("DHT values field must be a list.")
        }
        return try values.flatMap { value in
            guard let data = value.dataValue else {
                throw TorrentDHTError.invalidResponse("DHT peer values must be compact byte strings.")
            }
            return try compactPeers(data)
        }
    }

    private static func queryRequest(
        transactionID: Data,
        query: String,
        arguments: [String: BencodeValue]
    ) throws -> Data {
        BencodeValue.dictionary([
            key("a"): .dictionary(dictionary(arguments)),
            key("q"): .data(Data(query.utf8)),
            key("t"): .data(transactionID),
            key("y"): .data(Data("q".utf8))
        ]).encoded()
    }

    private static func validNodeID(_ nodeID: Data) throws -> Data {
        guard nodeID.count == 20 else {
            throw TorrentDHTError.invalidNodeID
        }
        return nodeID
    }

    private static func validInfoHash(_ infoHash: Data) throws -> Data {
        guard infoHash.count == 20 else {
            throw TorrentDHTError.invalidInfoHash
        }
        return infoHash
    }

    private static func dictionary(_ fields: [String: BencodeValue]) -> [Data: BencodeValue] {
        Dictionary(uniqueKeysWithValues: fields.map { (key($0.key), $0.value) })
    }

    private static func key(_ value: String) -> Data {
        Data(value.utf8)
    }

    private static func compactIPv4(host: String) -> Data? {
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return nil }
        return Data(octets)
    }
}

public struct TorrentDHTDiscoveryResult: Sendable, Equatable {
    public var peers: [TorrentDiscoveredPeer]
    public var routingTable: TorrentDHTRoutingTable
    public var queriedNodeCount: Int
    public var failedNodeCount: Int
    public var announcedNodeCount: Int
    public var lastError: String?

    public init(
        peers: [TorrentDiscoveredPeer],
        routingTable: TorrentDHTRoutingTable,
        queriedNodeCount: Int = 0,
        failedNodeCount: Int = 0,
        announcedNodeCount: Int = 0,
        lastError: String? = nil
    ) {
        self.peers = peers
        self.routingTable = routingTable
        self.queriedNodeCount = max(0, queriedNodeCount)
        self.failedNodeCount = max(0, failedNodeCount)
        self.announcedNodeCount = max(0, announcedNodeCount)
        self.lastError = lastError
    }
}

public protocol TorrentDHTTransport: Sendable {
    func send(_ data: Data, to node: TorrentDHTNode, timeout: Duration) async throws -> Data
}

public struct TorrentDHTClient: Sendable {
    public var localNodeID: Data
    public var timeout: Duration
    public var transactionIDSource: @Sendable () -> Data
    private let transport: any TorrentDHTTransport

    public init(
        localNodeID: Data = TorrentDHTClient.randomNodeID(),
        timeout: Duration = .seconds(3),
        transport: any TorrentDHTTransport,
        transactionIDSource: @escaping @Sendable () -> Data = TorrentDHTClient.randomTransactionID
    ) throws {
        guard localNodeID.count == 20 else {
            throw TorrentDHTError.invalidNodeID
        }
        self.localNodeID = localNodeID
        self.timeout = timeout
        self.transport = transport
        self.transactionIDSource = transactionIDSource
    }

    public func discoverPeers(
        infoHash: Data,
        bootstrapNodes: [TorrentDHTNode],
        announcePort: UInt16? = nil,
        maxPeers: Int = 50
    ) async throws -> TorrentDHTDiscoveryResult {
        guard infoHash.count == 20 else {
            throw TorrentDHTError.invalidInfoHash
        }
        var routingTable = TorrentDHTRoutingTable(nodes: bootstrapNodes)
        var peersByAddress = [String: TorrentDiscoveredPeer]()
        var queriedNodes = Set<String>()
        var queriedNodeCount = 0
        var failedNodeCount = 0
        var announcedNodeCount = 0
        var lastError: String?

        let bootstrapCandidates = routingTable.closestNodes(to: infoHash, limit: 8)
        for node in bootstrapCandidates {
            do {
                queriedNodes.insert("find:\(node.address)")
                queriedNodeCount += 1
                let transactionID = transactionIDSource()
                let request = try TorrentDHTKRPC.findNodeRequest(
                    transactionID: transactionID,
                    nodeID: localNodeID,
                    target: infoHash
                )
                let response = try await transport.send(request, to: node, timeout: timeout)
                let parsed = try TorrentDHTKRPC.parseResponse(response, expectedTransactionID: transactionID)
                routingTable.add(contentsOf: parsed.nodes)
            } catch {
                failedNodeCount += 1
                routingTable.recordFailure(for: node)
                lastError = error.localizedDescription
            }
        }

        while peersByAddress.count < max(1, maxPeers) {
            let candidates = routingTable
                .closestNodes(to: infoHash, limit: 16)
                .filter { !queriedNodes.contains("get:\($0.address)") }
            guard let node = candidates.first else { break }
            queriedNodes.insert("get:\(node.address)")
            queriedNodeCount += 1

            do {
                let transactionID = transactionIDSource()
                let request = try TorrentDHTKRPC.getPeersRequest(
                    transactionID: transactionID,
                    nodeID: localNodeID,
                    infoHash: infoHash
                )
                let response = try await transport.send(request, to: node, timeout: timeout)
                let parsed = try TorrentDHTKRPC.parseResponse(response, expectedTransactionID: transactionID)
                routingTable.add(contentsOf: parsed.nodes)
                for peer in parsed.peers {
                    peersByAddress[peer.address] = TorrentDiscoveredPeer(endpoint: peer, source: .dht)
                }
                if let announcePort,
                   let token = parsed.token,
                   announcePort > 0 {
                    do {
                        let announceTransactionID = transactionIDSource()
                        let announceRequest = try TorrentDHTKRPC.announcePeerRequest(
                            transactionID: announceTransactionID,
                            nodeID: localNodeID,
                            infoHash: infoHash,
                            port: announcePort,
                            token: token
                        )
                        let announceResponse = try await transport.send(
                            announceRequest,
                            to: node,
                            timeout: timeout
                        )
                        _ = try TorrentDHTKRPC.parseResponse(
                            announceResponse,
                            expectedTransactionID: announceTransactionID
                        )
                        announcedNodeCount += 1
                    } catch {
                        lastError = error.localizedDescription
                    }
                }
            } catch {
                failedNodeCount += 1
                routingTable.recordFailure(for: node)
                lastError = error.localizedDescription
            }
        }

        return TorrentDHTDiscoveryResult(
            peers: Array(peersByAddress.values).sorted { $0.endpoint.address < $1.endpoint.address },
            routingTable: routingTable,
            queriedNodeCount: queriedNodeCount,
            failedNodeCount: failedNodeCount,
            announcedNodeCount: announcedNodeCount,
            lastError: lastError
        )
    }

    public static func randomNodeID() -> Data {
        Data((0..<20).map { _ in UInt8.random(in: 0...255) })
    }

    public static func randomTransactionID() -> Data {
        Data((0..<2).map { _ in UInt8.random(in: 0...255) })
    }
}

#if canImport(Network)
public struct NetworkTorrentDHTTransport: TorrentDHTTransport {
    public init() {}

    public func send(_ data: Data, to node: TorrentDHTNode, timeout: Duration) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await Self.sendOnce(data, to: node)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TorrentDHTError.timeout
            }
            guard let response = try await group.next() else {
                throw TorrentDHTError.timeout
            }
            group.cancelAll()
            return response
        }
    }

    private static func sendOnce(_ data: Data, to node: TorrentDHTNode) async throws -> Data {
        guard let port = NWEndpoint.Port(rawValue: UInt16(node.port)) else {
            throw TorrentDHTError.transport("Invalid DHT node port.")
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(node.host),
            port: port,
            using: .udp
        )
        return try await withCheckedThrowingContinuation { continuation in
            let box = DHTContinuationBox<Data>()
            connection.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    box.resume(
                        continuation,
                        result: .failure(TorrentDHTError.transport(error.localizedDescription))
                    )
                    connection.cancel()
                }
            }
            connection.start(queue: .global())
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    box.resume(
                        continuation,
                        result: .failure(TorrentDHTError.transport(error.localizedDescription))
                    )
                    connection.cancel()
                    return
                }
                connection.receiveMessage { data, _, _, error in
                    defer { connection.cancel() }
                    if let error {
                        box.resume(
                            continuation,
                            result: .failure(TorrentDHTError.transport(error.localizedDescription))
                        )
                    } else if let data {
                        box.resume(continuation, result: .success(data))
                    } else {
                        box.resume(
                            continuation,
                            result: .failure(TorrentDHTError.invalidResponse("DHT node returned no data."))
                        )
                    }
                }
            })
        }
    }
}
#endif

public enum TorrentPeerExchangeMessage {
    public static func parse(_ payload: Data) throws -> [TorrentDiscoveredPeer] {
        let value: BencodeValue
        do {
            value = try BencodeParser(
                data: payload,
                limits: BencodeLimits(maximumInputBytes: 256 * 1024, maximumDepth: 8)
            ).parse()
        } catch let error as BencodeError {
            throw TorrentDHTError.invalidResponse(error.localizedDescription)
        }
        guard case .dictionary(let dictionary) = value else {
            throw TorrentDHTError.invalidResponse("PEX payload must be a bencoded dictionary.")
        }
        let added = try dictionary[key("added")]?.dataValue.map(TorrentDHTKRPC.compactPeers) ?? []
        return added.map { TorrentDiscoveredPeer(endpoint: $0, source: .pex) }
    }
}

public enum TorrentLocalServiceDiscovery {
    public static let multicastHost = "239.192.152.143"
    public static let multicastPort: UInt16 = 6_771

    public static func searchMessage(infoHash: Data, port: UInt16) throws -> Data {
        guard infoHash.count == 20 else {
            throw TorrentDHTError.invalidInfoHash
        }
        let message = """
        BT-SEARCH * HTTP/1.1\r
        Host: \(multicastHost):\(multicastPort)\r
        Port: \(port)\r
        Infohash: \(infoHash.hexEncodedString.uppercased())\r
        \r
        """
        return Data(message.utf8)
    }

    public static func parseSearchMessage(
        _ data: Data,
        sourceHost: String,
        expectedInfoHash: Data
    ) throws -> TorrentDiscoveredPeer? {
        guard expectedInfoHash.count == 20 else {
            throw TorrentDHTError.invalidInfoHash
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw TorrentDHTError.invalidResponse("LSD message must be UTF-8 text.")
        }
        let lines = text.components(separatedBy: "\r\n")
        guard lines.first == "BT-SEARCH * HTTP/1.1" else {
            return nil
        }
        var headers = [String: String]()
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            headers[String(name)] = value
        }
        guard headers["infohash"]?.lowercased() == expectedInfoHash.hexEncodedString,
              let portText = headers["port"],
              let port = Int(portText),
              port > 0,
              port <= Int(UInt16.max)
        else {
            return nil
        }
        return TorrentDiscoveredPeer(
            endpoint: TorrentPeerEndpoint(host: sourceHost, port: port),
            source: .lsd
        )
    }
}

private final class DHTContinuationBox<Value: Sendable>: @unchecked Sendable {
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

private extension TorrentDHTNode {
    func distance(to target: Data) -> [UInt8] {
        guard let id, id.count == target.count else {
            return Array(repeating: UInt8.max, count: max(1, target.count))
        }
        return zip(id, target).map { $0 ^ $1 }
    }
}

private extension BencodeValue {
    var dataValue: Data? {
        guard case .data(let data) = self else { return nil }
        return data
    }
}

private func key(_ value: String) -> Data {
    Data(value.utf8)
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
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
}
