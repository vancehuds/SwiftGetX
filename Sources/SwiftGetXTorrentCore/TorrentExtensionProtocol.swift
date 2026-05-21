import CryptoKit
import Foundation

public struct TorrentPeerExtensionHandshake: Equatable, Sendable {
    public static let handshakeExtendedID: UInt8 = 0
    public static let defaultLocalMetadataMessageID: UInt8 = 1

    public var utMetadataMessageID: UInt8?
    public var metadataSize: Int?

    public init(utMetadataMessageID: UInt8? = defaultLocalMetadataMessageID, metadataSize: Int? = nil) throws {
        if let utMetadataMessageID, utMetadataMessageID == Self.handshakeExtendedID {
            throw TorrentPeerWireError.invalidExtendedMessage
        }
        if let metadataSize, metadataSize <= 0 {
            throw TorrentPeerWireError.invalidMetadataSize(metadataSize)
        }
        self.utMetadataMessageID = utMetadataMessageID
        self.metadataSize = metadataSize
    }

    public func encodedPayload() -> Data {
        var extensions = [Data: BencodeValue]()
        if let utMetadataMessageID {
            extensions[key("ut_metadata")] = .integer(Int64(utMetadataMessageID))
        }
        var root: [Data: BencodeValue] = [
            key("m"): .dictionary(extensions)
        ]
        if let metadataSize {
            root[key("metadata_size")] = .integer(Int64(metadataSize))
        }
        return BencodeValue.dictionary(root).encoded()
    }

    public static func decode(_ payload: Data) throws -> TorrentPeerExtensionHandshake {
        let value = try parseBencodePrefix(payload).value
        guard case .dictionary(let root) = value else {
            throw TorrentPeerWireError.invalidExtendedMessage
        }
        let metadataSize = root[key("metadata_size")]?.integerValue.map(Int.init)
        if let metadataSize, metadataSize <= 0 {
            throw TorrentPeerWireError.invalidMetadataSize(metadataSize)
        }
        let utMetadataMessageID: UInt8?
        if case .dictionary(let extensions)? = root[key("m")],
           let rawMessageID = extensions[key("ut_metadata")]?.integerValue
        {
            guard rawMessageID > 0, rawMessageID <= Int64(UInt8.max) else {
                throw TorrentPeerWireError.invalidExtendedMessage
            }
            utMetadataMessageID = UInt8(rawMessageID)
        } else {
            utMetadataMessageID = nil
        }
        return try TorrentPeerExtensionHandshake(
            utMetadataMessageID: utMetadataMessageID,
            metadataSize: metadataSize
        )
    }
}

public enum TorrentMetadataExtensionMessage: Equatable, Sendable {
    public static let pieceLength = 16_384

    case request(pieceIndex: Int)
    case data(pieceIndex: Int, totalSize: Int?, metadata: Data)
    case reject(pieceIndex: Int)

    public func encodedPayload() throws -> Data {
        var dictionary = [Data: BencodeValue]()
        switch self {
        case .request(let pieceIndex):
            try Self.validatePieceIndex(pieceIndex)
            dictionary[key("msg_type")] = .integer(0)
            dictionary[key("piece")] = .integer(Int64(pieceIndex))
            return BencodeValue.dictionary(dictionary).encoded()
        case .data(let pieceIndex, let totalSize, let metadata):
            try Self.validatePieceIndex(pieceIndex)
            if let totalSize, totalSize <= 0 {
                throw TorrentPeerWireError.invalidMetadataSize(totalSize)
            }
            dictionary[key("msg_type")] = .integer(1)
            dictionary[key("piece")] = .integer(Int64(pieceIndex))
            if let totalSize {
                dictionary[key("total_size")] = .integer(Int64(totalSize))
            }
            var payload = BencodeValue.dictionary(dictionary).encoded()
            payload.append(metadata)
            return payload
        case .reject(let pieceIndex):
            try Self.validatePieceIndex(pieceIndex)
            dictionary[key("msg_type")] = .integer(2)
            dictionary[key("piece")] = .integer(Int64(pieceIndex))
            return BencodeValue.dictionary(dictionary).encoded()
        }
    }

    public static func decode(_ payload: Data) throws -> TorrentMetadataExtensionMessage {
        let parsed = try parseBencodePrefix(payload)
        guard case .dictionary(let dictionary) = parsed.value,
              let rawType = dictionary[key("msg_type")]?.integerValue,
              let rawPiece = dictionary[key("piece")]?.integerValue,
              rawPiece >= 0,
              rawPiece <= Int64(Int.max)
        else {
            throw TorrentPeerWireError.invalidExtendedMessage
        }
        let pieceIndex = Int(rawPiece)
        switch rawType {
        case 0:
            guard parsed.trailingData.isEmpty else {
                throw TorrentPeerWireError.invalidExtendedMessage
            }
            return .request(pieceIndex: pieceIndex)
        case 1:
            let totalSize = dictionary[key("total_size")]?.integerValue.map(Int.init)
            if let totalSize, totalSize <= 0 {
                throw TorrentPeerWireError.invalidMetadataSize(totalSize)
            }
            return .data(pieceIndex: pieceIndex, totalSize: totalSize, metadata: parsed.trailingData)
        case 2:
            guard parsed.trailingData.isEmpty else {
                throw TorrentPeerWireError.invalidExtendedMessage
            }
            return .reject(pieceIndex: pieceIndex)
        default:
            throw TorrentPeerWireError.invalidExtendedMessage
        }
    }

    private static func validatePieceIndex(_ pieceIndex: Int) throws {
        guard pieceIndex >= 0 else {
            throw TorrentPeerWireError.invalidPieceIndex(pieceIndex)
        }
    }
}

public actor TorrentMagnetMetadataSession {
    private let infoHash: Data
    private let trackers: [String]
    private let transport: any TorrentPeerWireTransport
    private let peerID: Data
    private let maximumMetadataSize: Int
    private var bufferedBytes = Data()

    public init(
        infoHash: Data,
        trackers: [String],
        transport: any TorrentPeerWireTransport,
        peerID: Data = Data("-SGX0001-00000000000".utf8),
        maximumMetadataSize: Int = 16 * 1024 * 1024
    ) throws {
        guard infoHash.count == 20, peerID.count == 20 else {
            throw TorrentPeerWireError.invalidHandshakeLength(infoHash.count + peerID.count)
        }
        self.infoHash = infoHash
        self.trackers = trackers
        self.transport = transport
        self.peerID = peerID
        self.maximumMetadataSize = max(TorrentMetadataExtensionMessage.pieceLength, maximumMetadataSize)
    }

    public func fetchMetadata() async throws -> TorrentMetainfo {
        try await performHandshake()
        try await sendExtensionHandshake()
        let remoteHandshake = try await readExtensionHandshake()
        guard let remoteMetadataID = remoteHandshake.utMetadataMessageID else {
            throw TorrentPeerWireError.metadataExtensionUnavailable
        }
        guard let metadataSize = remoteHandshake.metadataSize else {
            throw TorrentPeerWireError.invalidMetadataSize(0)
        }
        guard metadataSize > 0, metadataSize <= maximumMetadataSize else {
            throw TorrentPeerWireError.invalidMetadataSize(metadataSize)
        }

        let metadata = try await fetchMetadataPieces(
            metadataSize: metadataSize,
            remoteMetadataID: remoteMetadataID
        )
        let actualHash = Data(Insecure.SHA1.hash(data: metadata))
        guard actualHash == infoHash else {
            throw TorrentPeerWireError.invalidMetadataHash(
                expected: infoHash.hexEncodedString,
                actual: actualHash.hexEncodedString
            )
        }
        return try TorrentMetainfo.parseInfoDictionary(
            data: metadata,
            announce: trackers.first,
            announceList: trackers.map { [$0] }
        )
    }

    private func performHandshake() async throws {
        let handshake = try TorrentPeerWireHandshake(
            infoHash: infoHash,
            peerID: peerID,
            reserved: TorrentPeerWireHandshake.extensionProtocolReservedBytes
        )
        try await transport.send(handshake.encodedData())
        let responseData = try await readExact(TorrentPeerWireHandshake.handshakeLength)
        let response = try TorrentPeerWireHandshake.decode(responseData, expectedInfoHash: infoHash)
        guard response.supportsExtensionProtocol else {
            throw TorrentPeerWireError.extensionProtocolUnavailable
        }
    }

    private func sendExtensionHandshake() async throws {
        let handshake = try TorrentPeerExtensionHandshake()
        try await transport.send(
            TorrentPeerWireMessage.extended(
                extendedID: TorrentPeerExtensionHandshake.handshakeExtendedID,
                payload: handshake.encodedPayload()
            ).encodedData()
        )
    }

    private func readExtensionHandshake() async throws -> TorrentPeerExtensionHandshake {
        while true {
            try Task.checkCancellation()
            switch try await readMessage() {
            case .extended(let extendedID, let payload) where extendedID == TorrentPeerExtensionHandshake.handshakeExtendedID:
                return try TorrentPeerExtensionHandshake.decode(payload)
            case .keepAlive, .choke, .unchoke, .interested, .notInterested, .have, .bitfield, .request, .piece, .cancel, .port, .extended, .unknown:
                continue
            }
        }
    }

    private func fetchMetadataPieces(
        metadataSize: Int,
        remoteMetadataID: UInt8
    ) async throws -> Data {
        let pieceCount = (metadataSize + TorrentMetadataExtensionMessage.pieceLength - 1)
            / TorrentMetadataExtensionMessage.pieceLength
        var pieces = [Int: Data]()

        for pieceIndex in 0..<pieceCount {
            try Task.checkCancellation()
            try await transport.send(
                TorrentPeerWireMessage.extended(
                    extendedID: remoteMetadataID,
                    payload: TorrentMetadataExtensionMessage.request(pieceIndex: pieceIndex).encodedPayload()
                ).encodedData()
            )
            pieces[pieceIndex] = try await readMetadataPiece(
                pieceIndex: pieceIndex,
                metadataSize: metadataSize,
                remoteMetadataID: remoteMetadataID
            )
        }

        var metadata = Data()
        for pieceIndex in 0..<pieceCount {
            guard let piece = pieces[pieceIndex] else {
                throw TorrentPeerWireError.invalidExtendedMessage
            }
            metadata.append(piece)
        }
        guard metadata.count == metadataSize else {
            throw TorrentPeerWireError.invalidMetadataSize(metadata.count)
        }
        return metadata
    }

    private func readMetadataPiece(
        pieceIndex: Int,
        metadataSize: Int,
        remoteMetadataID: UInt8
    ) async throws -> Data {
        while true {
            try Task.checkCancellation()
            switch try await readMessage() {
            case .extended(let extendedID, let payload) where extendedID == remoteMetadataID:
                switch try TorrentMetadataExtensionMessage.decode(payload) {
                case .data(let returnedPiece, let totalSize, let metadata) where returnedPiece == pieceIndex:
                    if let totalSize, totalSize != metadataSize {
                        throw TorrentPeerWireError.invalidMetadataSize(totalSize)
                    }
                    let expectedLength = expectedPieceLength(
                        pieceIndex: pieceIndex,
                        metadataSize: metadataSize
                    )
                    guard metadata.count == expectedLength else {
                        throw TorrentPeerWireError.invalidMetadataSize(metadata.count)
                    }
                    return metadata
                case .reject(let returnedPiece) where returnedPiece == pieceIndex:
                    throw TorrentPeerWireError.metadataRejected(pieceIndex: pieceIndex)
                default:
                    continue
                }
            case .extended(let extendedID, let payload) where extendedID == TorrentPeerExtensionHandshake.handshakeExtendedID:
                _ = try TorrentPeerExtensionHandshake.decode(payload)
                continue
            case .keepAlive, .choke, .unchoke, .interested, .notInterested, .have, .bitfield, .request, .piece, .cancel, .port, .extended, .unknown:
                continue
            }
        }
    }

    private func expectedPieceLength(pieceIndex: Int, metadataSize: Int) -> Int {
        let start = pieceIndex * TorrentMetadataExtensionMessage.pieceLength
        return min(TorrentMetadataExtensionMessage.pieceLength, metadataSize - start)
    }

    private func readMessage() async throws -> TorrentPeerWireMessage {
        let frame = try await readFrame()
        return try TorrentPeerWireMessage.decodeFrame(frame)
    }

    private func readFrame() async throws -> Data {
        let lengthData = try await readExact(4)
        let length = Int(lengthData.uint32(at: 0))
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
}

private func parseBencodePrefix(_ data: Data) throws -> (value: BencodeValue, trailingData: Data) {
    var cursor = BencodeCursor(bytes: Array(data), limits: .default)
    do {
        let value = try cursor.parseValue(depth: 0)
        let bytes = Array(data)
        return (value, Data(bytes[cursor.offset...]))
    } catch let error as BencodeError {
        throw TorrentCoreError.invalidBencode(error)
    }
}

private func key(_ value: String) -> Data {
    Data(value.utf8)
}

private extension Data {
    func uint32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    var hexEncodedString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
