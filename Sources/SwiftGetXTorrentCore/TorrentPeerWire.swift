import CryptoKit
import Darwin
import Foundation

public enum TorrentPeerWireError: Error, Equatable, Sendable, LocalizedError {
    case invalidHandshakeLength(Int)
    case invalidHandshakeProtocol
    case invalidHandshakeInfoHash(expected: String, actual: String)
    case invalidMessageLength
    case invalidMessage
    case unsupportedMessage(UInt8)
    case invalidPieceIndex(Int)
    case invalidBlockLength(pieceIndex: Int, begin: Int, length: Int)
    case invalidPieceHash(pieceIndex: Int)
    case timeout
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHandshakeLength(let length):
            "Torrent peer handshake has an invalid length: \(length)."
        case .invalidHandshakeProtocol:
            "Torrent peer handshake used an unexpected protocol string."
        case .invalidHandshakeInfoHash(let expected, let actual):
            "Torrent peer handshake expected info hash \(expected) but received \(actual)."
        case .invalidMessageLength:
            "Torrent peer message has an invalid length."
        case .invalidMessage:
            "Torrent peer message could not be parsed."
        case .unsupportedMessage(let id):
            "Torrent peer message id \(id) is not supported."
        case .invalidPieceIndex(let index):
            "Torrent peer piece index \(index) is invalid."
        case .invalidBlockLength(let pieceIndex, let begin, let length):
            "Torrent peer piece \(pieceIndex) has an invalid block at \(begin) with length \(length)."
        case .invalidPieceHash(let pieceIndex):
            "Torrent peer piece \(pieceIndex) failed SHA-1 validation."
        case .timeout:
            "Torrent peer timed out while waiting for data."
        case .transport(let message):
            message
        }
    }
}

public struct TorrentPeerWireHandshake: Equatable, Sendable {
    public static let protocolString = "BitTorrent protocol"
    public static let handshakeLength = 68

    public var infoHash: Data
    public var peerID: Data
    public var reserved: Data

    public init(infoHash: Data, peerID: Data, reserved: Data = Data(repeating: 0, count: 8)) throws {
        guard infoHash.count == 20, peerID.count == 20, reserved.count == 8 else {
            throw TorrentPeerWireError.invalidHandshakeLength(infoHash.count + peerID.count + reserved.count)
        }
        self.infoHash = infoHash
        self.peerID = peerID
        self.reserved = reserved
    }

    public func encodedData() -> Data {
        var data = Data()
        data.append(UInt8(Self.protocolString.utf8.count))
        data.append(Data(Self.protocolString.utf8))
        data.append(reserved)
        data.append(infoHash)
        data.append(peerID)
        return data
    }

    public static func decode(_ data: Data, expectedInfoHash: Data? = nil) throws -> TorrentPeerWireHandshake {
        guard data.count == handshakeLength else {
            throw TorrentPeerWireError.invalidHandshakeLength(data.count)
        }
        let bytes = [UInt8](data)
        let protocolLength = Int(bytes[0])
        guard protocolLength == Self.protocolString.utf8.count else {
            throw TorrentPeerWireError.invalidHandshakeProtocol
        }
        let protocolBytes = Data(bytes[1..<(1 + protocolLength)])
        guard String(data: protocolBytes, encoding: .utf8) == Self.protocolString else {
            throw TorrentPeerWireError.invalidHandshakeProtocol
        }
        let reserved = Data(bytes[(1 + protocolLength)..<(1 + protocolLength + 8)])
        let infoHash = Data(bytes[(1 + protocolLength + 8)..<(1 + protocolLength + 8 + 20)])
        let peerID = Data(bytes[(1 + protocolLength + 8 + 20)..<(1 + protocolLength + 8 + 20 + 20)])
        if let expectedInfoHash, expectedInfoHash != infoHash {
            throw TorrentPeerWireError.invalidHandshakeInfoHash(
                expected: expectedInfoHash.hexEncodedString,
                actual: infoHash.hexEncodedString
            )
        }
        return try TorrentPeerWireHandshake(infoHash: infoHash, peerID: peerID, reserved: reserved)
    }
}

public enum TorrentPeerWireMessage: Equatable, Sendable {
    case keepAlive
    case choke
    case unchoke
    case interested
    case notInterested
    case have(Int)
    case bitfield(Data)
    case request(pieceIndex: Int, begin: Int, length: Int)
    case piece(pieceIndex: Int, begin: Int, block: Data)
    case cancel(pieceIndex: Int, begin: Int, length: Int)
    case port(Int)
    case unknown(id: UInt8, payload: Data)

    public func encodedData() throws -> Data {
        switch self {
        case .keepAlive:
            return Data([0, 0, 0, 0])
        case .choke:
            return Self.encodedFrame(messageID: 0, payload: Data())
        case .unchoke:
            return Self.encodedFrame(messageID: 1, payload: Data())
        case .interested:
            return Self.encodedFrame(messageID: 2, payload: Data())
        case .notInterested:
            return Self.encodedFrame(messageID: 3, payload: Data())
        case .have(let pieceIndex):
            guard pieceIndex >= 0 else { throw TorrentPeerWireError.invalidPieceIndex(pieceIndex) }
            return Self.encodedFrame(messageID: 4, payload: Data(Self.encodeInt32(pieceIndex)))
        case .bitfield(let data):
            return Self.encodedFrame(messageID: 5, payload: data)
        case .request(let pieceIndex, let begin, let length):
            try Self.validateBlock(pieceIndex: pieceIndex, begin: begin, length: length)
            var payload = Data()
            payload.append(contentsOf: Self.encodeInt32(pieceIndex))
            payload.append(contentsOf: Self.encodeInt32(begin))
            payload.append(contentsOf: Self.encodeInt32(length))
            return Self.encodedFrame(messageID: 6, payload: payload)
        case .piece(let pieceIndex, let begin, let block):
            try Self.validateBlock(pieceIndex: pieceIndex, begin: begin, length: block.count)
            var payload = Data()
            payload.append(contentsOf: Self.encodeInt32(pieceIndex))
            payload.append(contentsOf: Self.encodeInt32(begin))
            payload.append(block)
            return Self.encodedFrame(messageID: 7, payload: payload)
        case .cancel(let pieceIndex, let begin, let length):
            try Self.validateBlock(pieceIndex: pieceIndex, begin: begin, length: length)
            var payload = Data()
            payload.append(contentsOf: Self.encodeInt32(pieceIndex))
            payload.append(contentsOf: Self.encodeInt32(begin))
            payload.append(contentsOf: Self.encodeInt32(length))
            return Self.encodedFrame(messageID: 8, payload: payload)
        case .port(let port):
            guard (0...Int(UInt16.max)).contains(port) else {
                throw TorrentPeerWireError.invalidMessage
            }
            var payload = Data()
            payload.appendUInt16(UInt16(port))
            return Self.encodedFrame(messageID: 9, payload: payload)
        case .unknown(let id, let payload):
            return Self.encodedFrame(messageID: id, payload: payload)
        }
    }

    public static func decodeFrame(_ data: Data) throws -> TorrentPeerWireMessage {
        guard data.count >= 4 else {
            throw TorrentPeerWireError.invalidMessageLength
        }
        let bytes = [UInt8](data)
        let length = Int(bytes.peerWireUInt32(at: 0))
        guard length == data.count - 4 else {
            throw TorrentPeerWireError.invalidMessageLength
        }
        if length == 0 {
            return .keepAlive
        }
        guard length >= 1 else {
            throw TorrentPeerWireError.invalidMessageLength
        }
        let messageID = bytes[4]
        let payload = Data(bytes[5..<(4 + length)])
        return try decode(messageID: messageID, payload: payload)
    }

    public static func decode(messageID: UInt8, payload: Data) throws -> TorrentPeerWireMessage {
        switch messageID {
        case 0:
            return .choke
        case 1:
            return .unchoke
        case 2:
            return .interested
        case 3:
            return .notInterested
        case 4:
            guard payload.count == 4 else { throw TorrentPeerWireError.invalidMessage }
            let pieceIndex = Int(payload.int32(at: 0))
            guard pieceIndex >= 0 else { throw TorrentPeerWireError.invalidPieceIndex(pieceIndex) }
            return .have(pieceIndex)
        case 5:
            return .bitfield(payload)
        case 6:
            guard payload.count == 12 else { throw TorrentPeerWireError.invalidMessage }
            let pieceIndex = Int(payload.int32(at: 0))
            let begin = Int(payload.int32(at: 4))
            let length = Int(payload.int32(at: 8))
            try validateBlock(pieceIndex: pieceIndex, begin: begin, length: length)
            return .request(pieceIndex: pieceIndex, begin: begin, length: length)
        case 7:
            guard payload.count >= 8 else { throw TorrentPeerWireError.invalidMessage }
            let pieceIndex = Int(payload.int32(at: 0))
            let begin = Int(payload.int32(at: 4))
            let block = Data(payload.dropFirst(8))
            try validateBlock(pieceIndex: pieceIndex, begin: begin, length: block.count)
            return .piece(pieceIndex: pieceIndex, begin: begin, block: block)
        case 8:
            guard payload.count == 12 else { throw TorrentPeerWireError.invalidMessage }
            let pieceIndex = Int(payload.int32(at: 0))
            let begin = Int(payload.int32(at: 4))
            let length = Int(payload.int32(at: 8))
            try validateBlock(pieceIndex: pieceIndex, begin: begin, length: length)
            return .cancel(pieceIndex: pieceIndex, begin: begin, length: length)
        case 9:
            guard payload.count == 2 else { throw TorrentPeerWireError.invalidMessage }
            return .port(Int(payload.uint16(at: 0)))
        default:
            return .unknown(id: messageID, payload: payload)
        }
    }

    private static func encodedFrame(messageID: UInt8, payload: Data) -> Data {
        let length = UInt32(payload.count + 1)
        var data = Data()
        data.appendUInt32(length)
        data.append(messageID)
        data.append(payload)
        return data
    }

    private static func validateBlock(pieceIndex: Int, begin: Int, length: Int) throws {
        guard pieceIndex >= 0 else {
            throw TorrentPeerWireError.invalidPieceIndex(pieceIndex)
        }
        guard begin >= 0, length > 0, length <= Int(TorrentPeerBlockPlanner.defaultMaximumBlockLength) else {
            throw TorrentPeerWireError.invalidBlockLength(
                pieceIndex: pieceIndex,
                begin: begin,
                length: length
            )
        }
    }

    private static func encodeInt32(_ value: Int) -> [UInt8] {
        var bigEndian = Int32(value).bigEndian
        return withUnsafeBytes(of: &bigEndian) { Array($0) }
    }
}

public struct TorrentPeerBlockRequest: Equatable, Sendable, Codable {
    public var pieceIndex: Int
    public var begin: Int
    public var length: Int

    public init(pieceIndex: Int, begin: Int, length: Int) {
        self.pieceIndex = pieceIndex
        self.begin = begin
        self.length = length
    }
}

public enum TorrentPeerBlockPlanner {
    public static let defaultMaximumBlockLength: Int64 = 16_384

    public static func requests(
        pieceLength: Int64,
        maximumBlockLength: Int64 = defaultMaximumBlockLength
    ) throws -> [TorrentPeerBlockRequest] {
        guard pieceLength > 0,
              maximumBlockLength > 0,
              maximumBlockLength <= defaultMaximumBlockLength
        else {
            throw TorrentPeerWireError.invalidBlockLength(pieceIndex: 0, begin: 0, length: 0)
        }
        var requests = [TorrentPeerBlockRequest]()
        requests.reserveCapacity(Int((pieceLength + maximumBlockLength - 1) / maximumBlockLength))
        var begin: Int64 = 0
        while begin < pieceLength {
            let length = min(maximumBlockLength, pieceLength - begin)
            requests.append(
                TorrentPeerBlockRequest(
                    pieceIndex: 0,
                    begin: Int(begin),
                    length: Int(length)
                )
            )
            begin += length
        }
        return requests
    }
}

public enum TorrentPieceSelectionMode: Sendable {
    case sequential
    case rarestFirst
}

public enum TorrentPieceSelector {
    public static func nextPieceIndex(
        pieceCount: Int,
        completedPieceIndexes: Set<Int>,
        availability: [Int: Int] = [:],
        mode: TorrentPieceSelectionMode = .rarestFirst
    ) throws -> Int? {
        try orderedPieceIndexes(
            pieceCount: pieceCount,
            completedPieceIndexes: completedPieceIndexes,
            availability: availability,
            mode: mode
        ).first
    }

    public static func orderedPieceIndexes(
        pieceCount: Int,
        completedPieceIndexes: Set<Int>,
        availability: [Int: Int] = [:],
        mode: TorrentPieceSelectionMode = .rarestFirst
    ) throws -> [Int] {
        guard pieceCount > 0 else {
            throw TorrentPeerWireError.invalidPieceIndex(pieceCount)
        }
        let candidates = (0..<pieceCount).filter { !completedPieceIndexes.contains($0) }
        guard mode == .rarestFirst else {
            return candidates
        }

        let rarestCandidates = candidates.filter { (availability[$0] ?? 0) > 0 }
        guard !rarestCandidates.isEmpty else {
            return candidates
        }
        return rarestCandidates.sorted { lhs, rhs in
            let lhsAvailability = availability[lhs] ?? Int.max
            let rhsAvailability = availability[rhs] ?? Int.max
            if lhsAvailability == rhsAvailability {
                return lhs < rhs
            }
            return lhsAvailability < rhsAvailability
        }
    }

    public static func isEndgame(
        pieceCount: Int,
        completedPieceIndexes: Set<Int>,
        activePeerCount: Int
    ) -> Bool {
        let remaining = max(0, pieceCount - completedPieceIndexes.count)
        return activePeerCount > 1 && remaining > 0 && remaining <= activePeerCount
    }
}

public protocol TorrentPeerWireTransport: Sendable {
    func send(_ data: Data) async throws
    func receive(maximumLength: Int) async throws -> Data
}

public final class TorrentPeerWireTCPTransport: @unchecked Sendable, TorrentPeerWireTransport {
    private let socketDescriptor: Int32

    public convenience init(endpoint: TorrentPeerEndpoint, timeoutSeconds: Int = 10) throws {
        try self.init(host: endpoint.host, port: endpoint.port, timeoutSeconds: timeoutSeconds)
    }

    public init(host: String, port: Int, timeoutSeconds: Int = 10) throws {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              port > 0,
              port <= 65_535
        else {
            throw TorrentPeerWireError.transport("Invalid peer endpoint.")
        }

        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0 else {
            throw TorrentPeerWireError.transport(String(cString: gai_strerror(status)))
        }
        defer { freeaddrinfo(result) }

        var connectedSocket: Int32 = -1
        var lastErrno = errno
        var candidate = result
        while let pointer = candidate {
            let info = pointer.pointee
            let descriptor = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
            if descriptor >= 0 {
                Self.configureTimeout(timeoutSeconds, descriptor: descriptor)
                if Darwin.connect(descriptor, info.ai_addr, info.ai_addrlen) == 0 {
                    connectedSocket = descriptor
                    break
                }
                lastErrno = errno
                close(descriptor)
            }
            candidate = info.ai_next
        }

        guard connectedSocket >= 0 else {
            throw TorrentPeerWireError.transport(String(cString: strerror(lastErrno)))
        }
        socketDescriptor = connectedSocket
    }

    deinit {
        close(socketDescriptor)
    }

    public func send(_ data: Data) async throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var sent = 0
            while sent < buffer.count {
                let result = Darwin.send(
                    socketDescriptor,
                    baseAddress.advanced(by: sent),
                    buffer.count - sent,
                    0
                )
                if result < 0 {
                    try Self.throwSocketError()
                }
                sent += result
            }
        }
    }

    public func receive(maximumLength: Int) async throws -> Data {
        guard maximumLength > 0 else { return Data() }
        var buffer = [UInt8](repeating: 0, count: maximumLength)
        let result = Darwin.recv(socketDescriptor, &buffer, maximumLength, 0)
        if result == 0 {
            return Data()
        }
        if result < 0 {
            try Self.throwSocketError()
        }
        return Data(buffer.prefix(result))
    }

    private static func configureTimeout(_ timeoutSeconds: Int, descriptor: Int32) {
        var timeout = timeval(tv_sec: max(1, timeoutSeconds), tv_usec: 0)
        withUnsafePointer(to: &timeout) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<timeval>.size) { reboundPointer in
                _ = setsockopt(
                    descriptor,
                    SOL_SOCKET,
                    SO_RCVTIMEO,
                    reboundPointer,
                    socklen_t(MemoryLayout<timeval>.size)
                )
                _ = setsockopt(
                    descriptor,
                    SOL_SOCKET,
                    SO_SNDTIMEO,
                    reboundPointer,
                    socklen_t(MemoryLayout<timeval>.size)
                )
            }
        }
    }

    private static func throwSocketError() throws -> Never {
        switch errno {
        case EAGAIN, EWOULDBLOCK, ETIMEDOUT:
            throw TorrentPeerWireError.timeout
        default:
            throw TorrentPeerWireError.transport(String(cString: strerror(errno)))
        }
    }
}

public struct TorrentPeerDownloadResult: Equatable, Sendable {
    public var pieceIndex: Int
    public var pieceLength: Int64
    public var bytesWritten: Int64
    public var resumeState: TorrentCoreResumeState
}

public actor TorrentPeerWireSession {
    private let metainfo: TorrentMetainfo
    private let layout: TorrentContentLayout
    private let workspace: TorrentPeerWorkspace
    private let storage: TorrentContentStorage
    private let transport: any TorrentPeerWireTransport
    private let peerID: Data
    private let maximumBlockLength: Int64
    private let pipelineLimit: Int
    private let maximumTimeoutResends: Int
    private var isConnected = false
    private var isInterested = false
    private var isUnchoked = false
    private var bufferedBytes = Data()

    public init(
        metainfo: TorrentMetainfo,
        layout: TorrentContentLayout,
        workspace: TorrentPeerWorkspace,
        transport: any TorrentPeerWireTransport,
        peerID: Data = Data("-SGX0001-00000000000".utf8),
        maximumBlockLength: Int64 = TorrentPeerBlockPlanner.defaultMaximumBlockLength,
        pipelineLimit: Int = 4,
        maximumTimeoutResends: Int = 3
    ) {
        self.metainfo = metainfo
        self.layout = layout
        self.workspace = workspace
        self.storage = TorrentContentStorage(layout: layout)
        self.transport = transport
        self.peerID = peerID
        self.maximumBlockLength = maximumBlockLength
        self.pipelineLimit = max(1, pipelineLimit)
        self.maximumTimeoutResends = max(0, maximumTimeoutResends)
    }

    public func connect() async throws {
        if isConnected {
            return
        }
        try await performHandshake()
        isConnected = true
    }

    public func downloadPiece(_ pieceIndex: Int) async throws -> TorrentPeerDownloadResult {
        guard pieceIndex >= 0, pieceIndex < metainfo.pieces.count else {
            throw TorrentPeerWireError.invalidPieceIndex(pieceIndex)
        }

        var state = try loadOrCreateResumeState()
        if state.completedPieces.contains(pieceIndex) {
            return TorrentPeerDownloadResult(
                pieceIndex: pieceIndex,
                pieceLength: pieceLength(for: pieceIndex),
                bytesWritten: 0,
                resumeState: state
            )
        }

        try await connect()
        if !isInterested {
            try await transport.send(TorrentPeerWireMessage.interested.encodedData())
            isInterested = true
        }
        try await waitForUnchoke()

        let pieceLength = pieceLength(for: pieceIndex)
        let requests = try TorrentPeerBlockPlanner.requests(
            pieceLength: pieceLength,
            maximumBlockLength: maximumBlockLength
        )
        let requestsWithIndex = requests.enumerated().map { _, request in
            TorrentPeerBlockRequest(pieceIndex: pieceIndex, begin: request.begin, length: request.length)
        }
        var nextRequestIndex = 0
        var expectedBlocks = [Int: Int]()
        var receivedBlocks = [Int: Data]()
        var partialBlocks = state.partialBlocks.filter { $0.pieceIndex != pieceIndex }
        var timeoutResendCount = 0
        func nextRequestToSend() -> TorrentPeerBlockRequest? {
            guard nextRequestIndex < requestsWithIndex.count else { return nil }
            let request = requestsWithIndex[nextRequestIndex]
            nextRequestIndex += 1
            expectedBlocks[request.begin] = request.length
            return request
        }

        for _ in 0..<min(pipelineLimit, requestsWithIndex.count) {
            if let request = nextRequestToSend() {
                try await sendRequest(request)
            }
        }

        do {
            while receivedBlocks.count < requestsWithIndex.count {
                try Task.checkCancellation()
                let message: TorrentPeerWireMessage
                do {
                    message = try await readMessage()
                    timeoutResendCount = 0
                } catch TorrentPeerWireError.timeout {
                    timeoutResendCount += 1
                    guard timeoutResendCount <= maximumTimeoutResends else {
                        throw TorrentPeerWireError.timeout
                    }
                    let outstandingRequests = requestsWithIndex.filter {
                        expectedBlocks[$0.begin] != nil && receivedBlocks[$0.begin] == nil
                    }
                    guard !outstandingRequests.isEmpty else {
                        throw TorrentPeerWireError.timeout
                    }
                    for request in outstandingRequests {
                        try await sendRequest(request)
                    }
                    continue
                }
                switch message {
                case .piece(let returnedIndex, let begin, let block) where returnedIndex == pieceIndex:
                    guard let expectedLength = expectedBlocks[begin] else {
                        throw TorrentPeerWireError.invalidBlockLength(
                            pieceIndex: pieceIndex,
                            begin: begin,
                            length: block.count
                        )
                    }
                    guard block.count == expectedLength else {
                        throw TorrentPeerWireError.invalidBlockLength(
                            pieceIndex: pieceIndex,
                            begin: begin,
                            length: block.count
                        )
                    }
                    if receivedBlocks[begin] == nil {
                        receivedBlocks[begin] = block
                        partialBlocks.removeAll {
                            $0.pieceIndex == pieceIndex && $0.offset == begin
                        }
                        partialBlocks.append(
                            try TorrentResumePartialBlock(
                                pieceIndex: pieceIndex,
                                offset: begin,
                                length: block.count
                            )
                        )
                        if let request = nextRequestToSend() {
                            try await sendRequest(request)
                        }
                    }
                case .choke:
                    isUnchoked = false
                    continue
                case .unchoke:
                    isUnchoked = true
                    continue
                case .keepAlive, .interested, .notInterested, .have, .bitfield, .request, .cancel, .port, .unknown:
                    continue
                case .piece:
                    continue
                }
            }

            let orderedBlocks = requestsWithIndex.sorted { $0.begin < $1.begin }
                .compactMap { receivedBlocks[$0.begin] }
            let pieceData = orderedBlocks.reduce(into: Data()) { partialResult, block in
                partialResult.append(block)
            }
            guard Int64(pieceData.count) == pieceLength else {
                throw TorrentPeerWireError.invalidBlockLength(pieceIndex: pieceIndex, begin: 0, length: pieceData.count)
            }

            let expectedHash = metainfo.pieces[pieceIndex]
            let actualHash = Data(Insecure.SHA1.hash(data: pieceData))
            guard expectedHash == actualHash else {
                throw TorrentPeerWireError.invalidPieceHash(pieceIndex: pieceIndex)
            }

            try storage.write(piece: pieceData, pieceIndex: pieceIndex, pieceLength: metainfo.pieceLength)
            partialBlocks.removeAll { $0.pieceIndex == pieceIndex }
            state = try TorrentCoreResumeState(
                infoHashV1Hex: metainfo.infoHashV1Hex,
                pieceCount: metainfo.pieces.count,
                layoutTotalLength: layout.totalLength,
                completedPieceIndexes: state.completedPieces.completedPieceIndexes + [pieceIndex],
                partialBlocks: partialBlocks,
                fileChecks: state.fileChecks,
                trackerStates: state.trackerStates,
                peerBans: state.peerBans,
                updatedAt: .now
            )
            try workspace.saveResumeState(state)
            return TorrentPeerDownloadResult(
                pieceIndex: pieceIndex,
                pieceLength: pieceLength,
                bytesWritten: Int64(pieceData.count),
                resumeState: state
            )
        } catch is CancellationError {
            state = try TorrentCoreResumeState(
                infoHashV1Hex: metainfo.infoHashV1Hex,
                pieceCount: metainfo.pieces.count,
                layoutTotalLength: layout.totalLength,
                completedPieceIndexes: state.completedPieces.completedPieceIndexes,
                partialBlocks: partialBlocks,
                fileChecks: state.fileChecks,
                trackerStates: state.trackerStates,
                peerBans: state.peerBans,
                updatedAt: .now
            )
            try workspace.saveResumeState(state)
            throw CancellationError()
        } catch {
            partialBlocks.removeAll { $0.pieceIndex == pieceIndex }
            state = try TorrentCoreResumeState(
                infoHashV1Hex: metainfo.infoHashV1Hex,
                pieceCount: metainfo.pieces.count,
                layoutTotalLength: layout.totalLength,
                completedPieceIndexes: state.completedPieces.completedPieceIndexes,
                partialBlocks: partialBlocks,
                fileChecks: state.fileChecks,
                trackerStates: state.trackerStates,
                peerBans: state.peerBans,
                updatedAt: .now
            )
            try? workspace.saveResumeState(state)
            throw error
        }
    }

    public func pause() throws -> TorrentCoreResumeState {
        let state = try loadOrCreateResumeState()
        try workspace.saveResumeState(state)
        return state
    }

    public func resume() throws -> TorrentCoreResumeState? {
        try workspace.loadResumeState()
    }

    public func deletePartialData() throws {
        try workspace.deletePartialData()
    }

    private func performHandshake() async throws {
        let handshake = try TorrentPeerWireHandshake(
            infoHash: metainfo.infoHashV1,
            peerID: peerID
        )
        try await transport.send(handshake.encodedData())
        let responseData = try await readExact(TorrentPeerWireHandshake.handshakeLength)
        _ = try TorrentPeerWireHandshake.decode(responseData, expectedInfoHash: metainfo.infoHashV1)
    }

    private func sendRequest(_ request: TorrentPeerBlockRequest) async throws {
        try await transport.send(
            TorrentPeerWireMessage.request(
                pieceIndex: request.pieceIndex,
                begin: request.begin,
                length: request.length
            ).encodedData()
        )
    }

    private func waitForUnchoke() async throws {
        if isUnchoked {
            return
        }
        while true {
            try Task.checkCancellation()
            switch try await readMessage() {
            case .unchoke:
                isUnchoked = true
                return
            case .choke:
                isUnchoked = false
                continue
            case .keepAlive, .interested, .notInterested, .have, .bitfield, .request, .piece, .cancel, .port, .unknown:
                continue
            }
        }
    }

    private func readMessage() async throws -> TorrentPeerWireMessage {
        let frame = try await readFrame()
        return try TorrentPeerWireMessage.decodeFrame(frame)
    }

    private func readFrame() async throws -> Data {
        let lengthData = try await readExact(4)
        let length = Int(lengthData.uint32(at: 0))
        guard length >= 0 else {
            throw TorrentPeerWireError.invalidMessageLength
        }
        if length == 0 {
            return lengthData
        }
        let payload = try await readExact(length)
        var frame = Data(lengthData)
        frame.append(payload)
        return frame
    }

    private func readExact(_ count: Int) async throws -> Data {
        while bufferedBytes.count < count {
            let chunk = try await transport.receive(maximumLength: max(count - bufferedBytes.count, 1))
            if chunk.isEmpty {
                throw TorrentPeerWireError.invalidMessageLength
            }
            bufferedBytes.append(chunk)
        }
        let prefix = bufferedBytes.prefix(count)
        bufferedBytes.removeFirst(count)
        return Data(prefix)
    }

    private func loadOrCreateResumeState() throws -> TorrentCoreResumeState {
        if let state = try workspace.loadResumeState() {
            return state
        }
        return try workspace.makeEmptyResumeState()
    }

    private func pieceLength(for pieceIndex: Int) -> Int64 {
        let start = Int64(pieceIndex) * metainfo.pieceLength
        let remaining = metainfo.totalLength - start
        return min(metainfo.pieceLength, remaining)
    }
}

private extension Data {
    mutating func appendUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt16(_ value: UInt16) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    func uint32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    func uint16(at offset: Int) -> UInt16 {
        (UInt16(self[offset]) << 8)
            | UInt16(self[offset + 1])
    }

    func int32(at offset: Int) -> Int32 {
        Int32(bitPattern: uint32(at: offset))
    }

    var hexEncodedString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension Array where Element == UInt8 {
    func peerWireUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }
}
