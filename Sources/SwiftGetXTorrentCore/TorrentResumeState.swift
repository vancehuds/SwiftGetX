import Foundation

public enum TorrentResumeStateError: Error, Equatable, Sendable, LocalizedError {
    case invalidPieceCount
    case invalidPieceIndex(Int)
    case invalidBlockRange(pieceIndex: Int)
    case duplicatePartialBlock(pieceIndex: Int, offset: Int)
    case unsupportedVersion(Int)
    case invalidInfoHash(String)
    case invalidLayoutTotalLength
    case invalidFileCheck(fileIndex: Int)
    case invalidTracker(String)
    case invalidPeerBan(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPieceCount:
            "Torrent resume state has an invalid piece count."
        case .invalidPieceIndex(let index):
            "Torrent resume state references invalid piece index \(index)."
        case .invalidBlockRange(let pieceIndex):
            "Torrent resume state has an invalid block range for piece \(pieceIndex)."
        case .duplicatePartialBlock(let pieceIndex, let offset):
            "Torrent resume state has a duplicate partial block at piece \(pieceIndex), offset \(offset)."
        case .unsupportedVersion(let version):
            "Torrent resume state version \(version) is not supported."
        case .invalidInfoHash(let infoHash):
            "Torrent resume state has an invalid v1 info hash: \(infoHash)."
        case .invalidLayoutTotalLength:
            "Torrent resume state has an invalid layout total length."
        case .invalidFileCheck(let fileIndex):
            "Torrent resume state has an invalid file check for file \(fileIndex)."
        case .invalidTracker(let url):
            "Torrent resume state has an invalid tracker URL: \(url)."
        case .invalidPeerBan(let address):
            "Torrent resume state has an invalid banned peer: \(address)."
        }
    }
}

public struct TorrentResumeBitfield: Codable, Equatable, Sendable {
    public var pieceCount: Int
    public var completedPieceIndexes: [Int]

    public init(pieceCount: Int, completedPieceIndexes: [Int] = []) throws {
        guard pieceCount > 0 else {
            throw TorrentResumeStateError.invalidPieceCount
        }
        let uniqueIndexes = Set(completedPieceIndexes)
        for index in uniqueIndexes {
            guard index >= 0, index < pieceCount else {
                throw TorrentResumeStateError.invalidPieceIndex(index)
            }
        }
        self.pieceCount = pieceCount
        self.completedPieceIndexes = uniqueIndexes.sorted()
    }

    public func contains(_ pieceIndex: Int) -> Bool {
        completedPieceIndexes.binarySearch(pieceIndex)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pieceCount = try container.decode(Int.self, forKey: .pieceCount)
        let completedPieceIndexes = try container.decode([Int].self, forKey: .completedPieceIndexes)
        try self.init(pieceCount: pieceCount, completedPieceIndexes: completedPieceIndexes)
    }
}

public struct TorrentResumePartialBlock: Codable, Equatable, Sendable {
    public var pieceIndex: Int
    public var offset: Int
    public var length: Int
    public var checksumSHA1Hex: String?

    public init(
        pieceIndex: Int,
        offset: Int,
        length: Int,
        checksumSHA1Hex: String? = nil
    ) throws {
        guard pieceIndex >= 0 else {
            throw TorrentResumeStateError.invalidPieceIndex(pieceIndex)
        }
        guard offset >= 0, length > 0 else {
            throw TorrentResumeStateError.invalidBlockRange(pieceIndex: pieceIndex)
        }
        self.pieceIndex = pieceIndex
        self.offset = offset
        self.length = length
        self.checksumSHA1Hex = checksumSHA1Hex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            pieceIndex: container.decode(Int.self, forKey: .pieceIndex),
            offset: container.decode(Int.self, forKey: .offset),
            length: container.decode(Int.self, forKey: .length),
            checksumSHA1Hex: container.decodeIfPresent(String.self, forKey: .checksumSHA1Hex)
        )
    }
}

public struct TorrentResumeFileCheck: Codable, Equatable, Sendable {
    public var fileIndex: Int
    public var path: String
    public var length: Int64
    public var modificationDate: Date?
    public var contentFingerprint: String?

    public init(
        fileIndex: Int,
        path: String,
        length: Int64,
        modificationDate: Date? = nil,
        contentFingerprint: String? = nil
    ) throws {
        guard fileIndex >= 0, length >= 0, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TorrentResumeStateError.invalidFileCheck(fileIndex: fileIndex)
        }
        self.fileIndex = fileIndex
        self.path = path
        self.length = length
        self.modificationDate = modificationDate
        self.contentFingerprint = contentFingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            fileIndex: container.decode(Int.self, forKey: .fileIndex),
            path: container.decode(String.self, forKey: .path),
            length: container.decode(Int64.self, forKey: .length),
            modificationDate: container.decodeIfPresent(Date.self, forKey: .modificationDate),
            contentFingerprint: container.decodeIfPresent(String.self, forKey: .contentFingerprint)
        )
    }
}

public struct TorrentResumeTrackerState: Codable, Equatable, Sendable {
    public var url: String
    public var tier: Int
    public var lastAnnounceDate: Date?
    public var nextAnnounceDate: Date?
    public var failureCount: Int
    public var lastError: String?

    public init(
        url: String,
        tier: Int,
        lastAnnounceDate: Date? = nil,
        nextAnnounceDate: Date? = nil,
        failureCount: Int = 0,
        lastError: String? = nil
    ) throws {
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, tier >= 0, failureCount >= 0 else {
            throw TorrentResumeStateError.invalidTracker(url)
        }
        self.url = url
        self.tier = tier
        self.lastAnnounceDate = lastAnnounceDate
        self.nextAnnounceDate = nextAnnounceDate
        self.failureCount = failureCount
        self.lastError = lastError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            url: try container.decode(String.self, forKey: .url),
            tier: try container.decode(Int.self, forKey: .tier),
            lastAnnounceDate: try container.decodeIfPresent(Date.self, forKey: .lastAnnounceDate),
            nextAnnounceDate: try container.decodeIfPresent(Date.self, forKey: .nextAnnounceDate),
            failureCount: try container.decode(Int.self, forKey: .failureCount),
            lastError: try container.decodeIfPresent(String.self, forKey: .lastError)
        )
    }
}

public struct TorrentResumePeerBan: Codable, Equatable, Sendable {
    public var peerID: String?
    public var address: String
    public var reason: String
    public var bannedUntil: Date?

    public init(peerID: String? = nil, address: String, reason: String, bannedUntil: Date? = nil) throws {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw TorrentResumeStateError.invalidPeerBan(address)
        }
        self.peerID = peerID
        self.address = address
        self.reason = reason
        self.bannedUntil = bannedUntil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            peerID: container.decodeIfPresent(String.self, forKey: .peerID),
            address: container.decode(String.self, forKey: .address),
            reason: container.decode(String.self, forKey: .reason),
            bannedUntil: container.decodeIfPresent(Date.self, forKey: .bannedUntil)
        )
    }
}

public struct TorrentCoreResumeState: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var version: Int
    public var infoHashV1Hex: String
    public var layoutTotalLength: Int64
    public var completedPieces: TorrentResumeBitfield
    public var partialBlocks: [TorrentResumePartialBlock]
    public var fileChecks: [TorrentResumeFileCheck]
    public var trackerStates: [TorrentResumeTrackerState]
    public var peerBans: [TorrentResumePeerBan]
    public var updatedAt: Date

    public init(
        infoHashV1Hex: String,
        pieceCount: Int,
        layoutTotalLength: Int64,
        completedPieceIndexes: [Int] = [],
        partialBlocks: [TorrentResumePartialBlock] = [],
        fileChecks: [TorrentResumeFileCheck] = [],
        trackerStates: [TorrentResumeTrackerState] = [],
        peerBans: [TorrentResumePeerBan] = [],
        updatedAt: Date = Date()
    ) throws {
        try Self.validateVersion(Self.schemaVersion)
        try Self.validateInfoHash(infoHashV1Hex)
        guard layoutTotalLength >= 0 else {
            throw TorrentResumeStateError.invalidLayoutTotalLength
        }
        self.version = Self.schemaVersion
        self.infoHashV1Hex = infoHashV1Hex.lowercased()
        self.layoutTotalLength = layoutTotalLength
        self.completedPieces = try TorrentResumeBitfield(
            pieceCount: pieceCount,
            completedPieceIndexes: completedPieceIndexes
        )
        self.partialBlocks = try Self.validatedPartialBlocks(partialBlocks, pieceCount: pieceCount)
        self.fileChecks = fileChecks
        self.trackerStates = trackerStates
        self.peerBans = peerBans
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        infoHashV1Hex = try container.decode(String.self, forKey: .infoHashV1Hex).lowercased()
        layoutTotalLength = try container.decode(Int64.self, forKey: .layoutTotalLength)
        completedPieces = try container.decode(TorrentResumeBitfield.self, forKey: .completedPieces)
        partialBlocks = try Self.validatedPartialBlocks(
            container.decode([TorrentResumePartialBlock].self, forKey: .partialBlocks),
            pieceCount: completedPieces.pieceCount
        )
        fileChecks = try container.decode([TorrentResumeFileCheck].self, forKey: .fileChecks)
        trackerStates = try container.decode([TorrentResumeTrackerState].self, forKey: .trackerStates)
        peerBans = try container.decode([TorrentResumePeerBan].self, forKey: .peerBans)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        try Self.validateVersion(version)
        try Self.validateInfoHash(infoHashV1Hex)
        guard layoutTotalLength >= 0 else {
            throw TorrentResumeStateError.invalidLayoutTotalLength
        }
    }

    public static func empty(
        for metainfo: TorrentMetainfo,
        layout: TorrentContentLayout,
        updatedAt: Date = Date()
    ) throws -> TorrentCoreResumeState {
        try TorrentCoreResumeState(
            infoHashV1Hex: metainfo.infoHashV1Hex,
            pieceCount: metainfo.pieces.count,
            layoutTotalLength: layout.totalLength,
            fileChecks: layout.files.map {
                try TorrentResumeFileCheck(
                    fileIndex: $0.index,
                    path: $0.relativePath,
                    length: $0.length
                )
            },
            trackerStates: try metainfo.announceList.enumerated().flatMap { tier, trackers in
                try trackers.map { tracker in
                    try TorrentResumeTrackerState(url: tracker, tier: tier)
                }
            },
            updatedAt: updatedAt
        )
    }

    public func validate(
        expectedInfoHashV1Hex: String? = nil,
        expectedLayout: TorrentContentLayout? = nil
    ) throws {
        try Self.validateVersion(version)
        try Self.validateInfoHash(infoHashV1Hex)
        if let expectedInfoHashV1Hex, infoHashV1Hex != expectedInfoHashV1Hex.lowercased() {
            throw TorrentResumeStateError.invalidInfoHash(infoHashV1Hex)
        }
        guard layoutTotalLength >= 0 else {
            throw TorrentResumeStateError.invalidLayoutTotalLength
        }
        _ = try TorrentResumeBitfield(
            pieceCount: completedPieces.pieceCount,
            completedPieceIndexes: completedPieces.completedPieceIndexes
        )
        _ = try Self.validatedPartialBlocks(
            partialBlocks,
            pieceCount: completedPieces.pieceCount
        )
        if let expectedLayout {
            guard layoutTotalLength == expectedLayout.totalLength,
                  fileChecks.count == expectedLayout.files.count
            else {
                throw TorrentResumeStateError.invalidLayoutTotalLength
            }
            for file in fileChecks {
                guard let layoutFile = expectedLayout.files.first(where: { $0.index == file.fileIndex }),
                      layoutFile.relativePath == file.path,
                      layoutFile.length == file.length
                else {
                    throw TorrentResumeStateError.invalidFileCheck(fileIndex: file.fileIndex)
                }
            }
        }
    }

    public func encodedJSON(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decodeJSON(
        _ data: Data,
        expectedInfoHashV1Hex: String? = nil,
        expectedLayout: TorrentContentLayout? = nil
    ) throws -> TorrentCoreResumeState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(TorrentCoreResumeState.self, from: data)
        try state.validate(
            expectedInfoHashV1Hex: expectedInfoHashV1Hex,
            expectedLayout: expectedLayout
        )
        return state
    }

    private static func validatedPartialBlocks(
        _ partialBlocks: [TorrentResumePartialBlock],
        pieceCount: Int
    ) throws -> [TorrentResumePartialBlock] {
        var seen = Set<String>()
        for block in partialBlocks {
            guard block.pieceIndex < pieceCount else {
                throw TorrentResumeStateError.invalidPieceIndex(block.pieceIndex)
            }
            let key = "\(block.pieceIndex):\(block.offset)"
            guard seen.insert(key).inserted else {
                throw TorrentResumeStateError.duplicatePartialBlock(
                    pieceIndex: block.pieceIndex,
                    offset: block.offset
                )
            }
        }
        return partialBlocks.sorted {
            if $0.pieceIndex == $1.pieceIndex {
                return $0.offset < $1.offset
            }
            return $0.pieceIndex < $1.pieceIndex
        }
    }

    private static func validateVersion(_ version: Int) throws {
        guard version == schemaVersion else {
            throw TorrentResumeStateError.unsupportedVersion(version)
        }
    }

    private static func validateInfoHash(_ infoHash: String) throws {
        guard infoHash.count == 40, infoHash.allSatisfy(\.isHexDigit) else {
            throw TorrentResumeStateError.invalidInfoHash(infoHash)
        }
    }
}

private extension Array where Element == Int {
    func binarySearch(_ value: Int) -> Bool {
        var lower = startIndex
        var upper = endIndex
        while lower < upper {
            let middle = lower + distance(from: lower, to: upper) / 2
            if self[middle] == value {
                return true
            }
            if self[middle] < value {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return false
    }
}
