import CryptoKit
import Foundation
import Testing
@testable import SwiftGetXTorrentCore

@Suite("Torrent peer wire")
struct TorrentPeerWireTests {
    @Test("encodes and decodes peer wire handshakes and messages")
    func encodesAndDecodesPeerWireHandshakesAndMessages() throws {
        let infoHash = Data((0..<20).map(UInt8.init))
        let peerID = Data((20..<40).map(UInt8.init))
        let handshake = try TorrentPeerWireHandshake(infoHash: infoHash, peerID: peerID)
        let decodedHandshake = try TorrentPeerWireHandshake.decode(
            handshake.encodedData(),
            expectedInfoHash: infoHash
        )

        #expect(decodedHandshake == handshake)

        let messages: [TorrentPeerWireMessage] = [
            .keepAlive,
            .choke,
            .unchoke,
            .interested,
            .notInterested,
            .have(3),
            .bitfield(Data([0b1010_0000])),
            .request(pieceIndex: 2, begin: 16_384, length: 8_192),
            .piece(pieceIndex: 2, begin: 16_384, block: Data([1, 2, 3])),
            .cancel(pieceIndex: 2, begin: 16_384, length: 8_192),
            .port(6_881)
        ]
        for message in messages {
            #expect(try TorrentPeerWireMessage.decodeFrame(message.encodedData()) == message)
        }
        let extended = TorrentPeerWireMessage.extended(
            extendedID: 3,
            payload: Data([1, 2, 3])
        )
        #expect(try TorrentPeerWireMessage.decodeFrame(extended.encodedData()) == extended)
        #expect(throws: TorrentPeerWireError.invalidMessageLength) {
            try TorrentPeerWireMessage.decodeFrame(oversizedFrameHeader())
        }

        let blockPlanner = try TorrentPeerBlockPlanner.requests(pieceLength: 20, maximumBlockLength: 8)
        #expect(blockPlanner.map(\.begin) == [0, 8, 16])
        #expect(blockPlanner.map(\.length) == [8, 8, 4])
        #expect(throws: TorrentPeerWireError.invalidBlockLength(pieceIndex: 0, begin: 0, length: 0)) {
            try TorrentPeerBlockPlanner.requests(
                pieceLength: 20,
                maximumBlockLength: TorrentPeerBlockPlanner.defaultMaximumBlockLength + 1
            )
        }
        #expect(throws: TorrentPeerWireError.invalidBlockLength(
            pieceIndex: 0,
            begin: 0,
            length: Int(TorrentPeerBlockPlanner.defaultMaximumBlockLength) + 1
        )) {
            try TorrentPeerWireMessage.request(
                pieceIndex: 0,
                begin: 0,
                length: Int(TorrentPeerBlockPlanner.defaultMaximumBlockLength) + 1
            ).encodedData()
        }
    }

    @Test("selects pieces sequentially before rarest availability is known")
    func selectsPiecesSequentiallyBeforeRarestAvailabilityIsKnown() throws {
        #expect(try TorrentPieceSelector.nextPieceIndex(
            pieceCount: 4,
            completedPieceIndexes: [0]
        ) == 1)
        #expect(try TorrentPieceSelector.nextPieceIndex(
            pieceCount: 4,
            completedPieceIndexes: [0],
            availability: [1: 3, 2: 1, 3: 2]
        ) == 2)
        #expect(try TorrentPieceSelector.nextPieceIndex(
            pieceCount: 2,
            completedPieceIndexes: [0, 1]
        ) == nil)
        #expect(try TorrentPieceSelector.orderedPieceIndexes(
            pieceCount: 4,
            completedPieceIndexes: [0],
            availability: [1: 3, 2: 1, 3: 2],
            mode: .sequential
        ) == [1, 2, 3])
        #expect(TorrentPieceSelector.isEndgame(
            pieceCount: 4,
            completedPieceIndexes: [0, 1],
            activePeerCount: 2
        ))
        #expect(!TorrentPieceSelector.isEndgame(
            pieceCount: 4,
            completedPieceIndexes: [0],
            activePeerCount: 2
        ))
    }

    @Test("encodes BEP 10 and BEP 9 metadata messages")
    func encodesBEP10AndBEP9MetadataMessages() throws {
        let handshake = try TorrentPeerExtensionHandshake(utMetadataMessageID: 7, metadataSize: 32_768)
        #expect(try TorrentPeerExtensionHandshake.decode(handshake.encodedPayload()) == handshake)

        let request = TorrentMetadataExtensionMessage.request(pieceIndex: 2)
        #expect(try TorrentMetadataExtensionMessage.decode(request.encodedPayload()) == request)

        let metadata = Data((0..<12).map(UInt8.init))
        let data = TorrentMetadataExtensionMessage.data(pieceIndex: 1, totalSize: 20_000, metadata: metadata)
        #expect(try TorrentMetadataExtensionMessage.decode(data.encodedPayload()) == data)

        let reject = TorrentMetadataExtensionMessage.reject(pieceIndex: 3)
        #expect(try TorrentMetadataExtensionMessage.decode(reject.encodedPayload()) == reject)
    }

    @Test("fetches magnet metadata through an extended peer")
    func fetchesMagnetMetadataThroughExtendedPeer() async throws {
        let info = bencodeDictionary([
            ("length", bencodeInteger(20)),
            ("name", bencodeString("demo.bin")),
            ("piece length", bencodeInteger(20)),
            ("pieces", bencodeData(Data(Insecure.SHA1.hash(data: Data((0..<20).map(UInt8.init))))))
        ])
        let infoHash = Data(Insecure.SHA1.hash(data: info))
        let metadataMessageID: UInt8 = 4
        let transport = MockTorrentPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: infoHash,
                    peerID: Data((60..<80).map(UInt8.init)),
                    reserved: TorrentPeerWireHandshake.extensionProtocolReservedBytes
                ).encodedData(),
                try TorrentPeerWireMessage.extended(
                    extendedID: TorrentPeerExtensionHandshake.handshakeExtendedID,
                    payload: TorrentPeerExtensionHandshake(
                        utMetadataMessageID: metadataMessageID,
                        metadataSize: info.count
                    ).encodedPayload()
                ).encodedData(),
                try TorrentPeerWireMessage.extended(
                    extendedID: metadataMessageID,
                    payload: TorrentMetadataExtensionMessage.data(
                        pieceIndex: 0,
                        totalSize: info.count,
                        metadata: info
                    ).encodedPayload()
                ).encodedData()
            ]
        )
        let session = try TorrentMagnetMetadataSession(
            infoHash: infoHash,
            trackers: ["http://tracker.example/announce"],
            transport: transport,
            peerID: Data((40..<60).map(UInt8.init))
        )

        let metainfo = try await session.fetchMetadata()

        #expect(metainfo.name == "demo.bin")
        #expect(metainfo.infoHashV1 == infoHash)
        #expect(metainfo.trackerURLs == ["http://tracker.example/announce"])

        let sentFrames = await transport.sentFrames
        #expect(sentFrames.count == 3)
        let sentHandshake = try TorrentPeerWireHandshake.decode(sentFrames[0], expectedInfoHash: infoHash)
        #expect(sentHandshake.supportsExtensionProtocol)
        guard case .extended(let handshakeID, _) = try TorrentPeerWireMessage.decodeFrame(sentFrames[1]) else {
            Issue.record("Expected a local extension handshake.")
            return
        }
        #expect(handshakeID == TorrentPeerExtensionHandshake.handshakeExtendedID)
        #expect(
            try TorrentPeerWireMessage.decodeFrame(sentFrames[2]) == .extended(
                extendedID: metadataMessageID,
                payload: TorrentMetadataExtensionMessage.request(pieceIndex: 0).encodedPayload()
            )
        )
    }

    @Test("rejects magnet metadata when the info hash does not match")
    func rejectsMagnetMetadataWhenInfoHashDoesNotMatch() async throws {
        let info = bencodeDictionary([
            ("length", bencodeInteger(20)),
            ("name", bencodeString("demo.bin")),
            ("piece length", bencodeInteger(20)),
            ("pieces", bencodeData(Data(Insecure.SHA1.hash(data: Data((0..<20).map(UInt8.init))))))
        ])
        let expectedInfoHash = Data(repeating: 7, count: 20)
        let metadataMessageID: UInt8 = 5
        let transport = MockTorrentPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: expectedInfoHash,
                    peerID: Data((60..<80).map(UInt8.init)),
                    reserved: TorrentPeerWireHandshake.extensionProtocolReservedBytes
                ).encodedData(),
                try TorrentPeerWireMessage.extended(
                    extendedID: TorrentPeerExtensionHandshake.handshakeExtendedID,
                    payload: TorrentPeerExtensionHandshake(
                        utMetadataMessageID: metadataMessageID,
                        metadataSize: info.count
                    ).encodedPayload()
                ).encodedData(),
                try TorrentPeerWireMessage.extended(
                    extendedID: metadataMessageID,
                    payload: TorrentMetadataExtensionMessage.data(
                        pieceIndex: 0,
                        totalSize: info.count,
                        metadata: info
                    ).encodedPayload()
                ).encodedData()
            ]
        )
        let session = try TorrentMagnetMetadataSession(
            infoHash: expectedInfoHash,
            trackers: [],
            transport: transport
        )

        do {
            _ = try await session.fetchMetadata()
            Issue.record("Expected metadata hash validation to fail.")
        } catch TorrentPeerWireError.invalidMetadataHash(let expected, let actual) {
            #expect(expected == expectedInfoHash.map { String(format: "%02x", $0) }.joined())
            #expect(actual == Data(Insecure.SHA1.hash(data: info)).map { String(format: "%02x", $0) }.joined())
        } catch {
            Issue.record("Expected an invalid metadata hash error.")
        }
    }

    @Test("rejects oversized peer wire frames before reading payload")
    func rejectsOversizedPeerWireFramesBeforeReadingPayload() async throws {
        let saveDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: saveDirectory) }

        let contents = Data((0..<8).map(UInt8.init))
        let metainfo = try TorrentMetainfo.parse(
            data: torrentData(
                announce: nil,
                info: bencodeDictionary([
                    ("length", bencodeInteger(Int64(contents.count))),
                    ("name", bencodeString("demo.bin")),
                    ("piece length", bencodeInteger(Int64(contents.count))),
                    ("pieces", bencodeData(Data(Insecure.SHA1.hash(data: contents))))
                ])
            )
        )
        let layout = try TorrentContentLayout(metainfo: metainfo, saveDirectory: saveDirectory)
        let workspace = TorrentPeerWorkspace(
            metainfo: metainfo,
            layout: layout,
            resumeStateURL: saveDirectory.appendingPathComponent("demo.resume.json")
        )
        let transport = MockTorrentPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: metainfo.infoHashV1,
                    peerID: Data((60..<80).map(UInt8.init))
                ).encodedData(),
                try TorrentPeerWireMessage.unchoke.encodedData(),
                oversizedFrameHeader()
            ]
        )
        let session = TorrentPeerWireSession(
            metainfo: metainfo,
            layout: layout,
            workspace: workspace,
            transport: transport,
            peerID: Data((40..<60).map(UInt8.init)),
            maximumBlockLength: 8,
            pipelineLimit: 1
        )

        do {
            _ = try await session.downloadPiece(0)
            Issue.record("Expected oversized frame rejection.")
        } catch TorrentPeerWireError.invalidMessageLength {
        } catch {
            Issue.record("Expected invalidMessageLength for oversized frame.")
        }
    }

    @Test("rejects oversized extended metadata frames before reading payload")
    func rejectsOversizedExtendedMetadataFramesBeforeReadingPayload() async throws {
        let info = bencodeDictionary([
            ("length", bencodeInteger(8)),
            ("name", bencodeString("demo.bin")),
            ("piece length", bencodeInteger(8)),
            ("pieces", bencodeData(Data(Insecure.SHA1.hash(data: Data((0..<8).map(UInt8.init))))))
        ])
        let infoHash = Data(Insecure.SHA1.hash(data: info))
        let transport = MockTorrentPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(
                    infoHash: infoHash,
                    peerID: Data((60..<80).map(UInt8.init)),
                    reserved: TorrentPeerWireHandshake.extensionProtocolReservedBytes
                ).encodedData(),
                oversizedFrameHeader()
            ]
        )
        let session = try TorrentMagnetMetadataSession(
            infoHash: infoHash,
            trackers: [],
            transport: transport
        )

        do {
            _ = try await session.fetchMetadata()
            Issue.record("Expected oversized extended frame rejection.")
        } catch TorrentPeerWireError.invalidMessageLength {
        } catch {
            Issue.record("Expected invalidMessageLength for oversized extended frame.")
        }
    }

    @Test("writes single-file torrent content")
    func writesSingleFileTorrentContent() throws {
        let saveDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: saveDirectory) }
        let layout = try TorrentContentLayout(
            files: [
                TorrentFileInfo(index: 0, path: "demo.bin", length: 4)
            ],
            saveDirectory: saveDirectory
        )
        let storage = TorrentContentStorage(layout: layout)

        try storage.write(piece: Data([1, 2, 3, 4]), pieceIndex: 0, pieceLength: 4)

        #expect(try Data(contentsOf: try #require(layout.finalFileURL)) == Data([1, 2, 3, 4]))
    }

    @Test("writes torrent content across layout boundaries")
    func writesTorrentContentAcrossLayoutBoundaries() throws {
        let saveDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: saveDirectory) }

        let layout = try TorrentContentLayout(
            files: [
                TorrentFileInfo(index: 0, path: "album/a.bin", length: 10, pathComponents: ["album", "a.bin"]),
                TorrentFileInfo(index: 1, path: "album/b.bin", length: 20, pathComponents: ["album", "b.bin"])
            ],
            saveDirectory: saveDirectory,
            isMultiFile: true
        )
        let storage = TorrentContentStorage(layout: layout)
        let contents = Data((0..<30).map(UInt8.init))

        try storage.write(piece: Data(contents.prefix(12)), pieceIndex: 0, pieceLength: 12)
        try storage.write(piece: Data(contents.dropFirst(12).prefix(12)), pieceIndex: 1, pieceLength: 12)
        try storage.write(piece: Data(contents.dropFirst(24)), pieceIndex: 2, pieceLength: 12)

        let firstFile = try Data(contentsOf: layout.files[0].fileURL)
        let secondFile = try Data(contentsOf: layout.files[1].fileURL)

        #expect(firstFile == contents.prefix(10))
        #expect(secondFile == Data(contents.dropFirst(10)))
    }

    @Test("downloads a piece through the peer wire session and validates its hash")
    func downloadsAPieceThroughThePeerWireSessionAndValidatesItsHash() async throws {
        let saveDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: saveDirectory) }

        let contents = Data((0..<20).map(UInt8.init))
        let metainfo = try TorrentMetainfo.parse(
            data: torrentData(
                announce: nil,
                info: bencodeDictionary([
                    ("length", bencodeInteger(Int64(contents.count))),
                    ("name", bencodeString("demo.bin")),
                    ("piece length", bencodeInteger(Int64(contents.count))),
                    ("pieces", bencodeData(Data(Insecure.SHA1.hash(data: contents))))
                ])
            )
        )
        let layout = try TorrentContentLayout(metainfo: metainfo, saveDirectory: saveDirectory)
        let resumeURL = saveDirectory.appendingPathComponent("demo.resume.json")
        let workspace = TorrentPeerWorkspace(
            metainfo: metainfo,
            layout: layout,
            resumeStateURL: resumeURL
        )
        let localPeerID = Data((40..<60).map(UInt8.init))
        let remotePeerID = Data((60..<80).map(UInt8.init))
        let transport = MockTorrentPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(infoHash: metainfo.infoHashV1, peerID: remotePeerID).encodedData(),
                try TorrentPeerWireMessage.unchoke.encodedData(),
                try TorrentPeerWireMessage.piece(pieceIndex: 0, begin: 0, block: contents.prefix(8)).encodedData(),
                try TorrentPeerWireMessage.piece(pieceIndex: 0, begin: 8, block: contents.dropFirst(8).prefix(8)).encodedData(),
                try TorrentPeerWireMessage.piece(pieceIndex: 0, begin: 16, block: contents.dropFirst(16)).encodedData()
            ]
        )
        let session = TorrentPeerWireSession(
            metainfo: metainfo,
            layout: layout,
            workspace: workspace,
            transport: transport,
            peerID: localPeerID,
            maximumBlockLength: 8,
            pipelineLimit: 2
        )

        let result = try await session.downloadPiece(0)
        let writtenData = try Data(contentsOf: layout.files[0].fileURL)

        #expect(result.pieceIndex == 0)
        #expect(result.bytesWritten == Int64(contents.count))
        #expect(result.resumeState.completedPieces.completedPieceIndexes == [0])
        #expect(writtenData == contents)

        let sentFrames = await transport.sentFrames
        #expect(sentFrames.count == 5)
        #expect(try TorrentPeerWireHandshake.decode(sentFrames[0], expectedInfoHash: metainfo.infoHashV1).peerID == localPeerID)
        #expect(try TorrentPeerWireMessage.decodeFrame(sentFrames[1]) == .interested)
        #expect(try TorrentPeerWireMessage.decodeFrame(sentFrames[2]) == .request(pieceIndex: 0, begin: 0, length: 8))
        #expect(try TorrentPeerWireMessage.decodeFrame(sentFrames[3]) == .request(pieceIndex: 0, begin: 8, length: 8))
        #expect(try TorrentPeerWireMessage.decodeFrame(sentFrames[4]) == .request(pieceIndex: 0, begin: 16, length: 4))

        let savedState = try #require(try workspace.loadResumeState())
        #expect(savedState.completedPieces.completedPieceIndexes == [0])
    }

    @Test("resends outstanding requests after peer receive timeout")
    func resendsOutstandingRequestsAfterPeerReceiveTimeout() async throws {
        let saveDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: saveDirectory) }

        let contents = Data((0..<8).map(UInt8.init))
        let metainfo = try TorrentMetainfo.parse(
            data: torrentData(
                announce: nil,
                info: bencodeDictionary([
                    ("length", bencodeInteger(Int64(contents.count))),
                    ("name", bencodeString("demo.bin")),
                    ("piece length", bencodeInteger(Int64(contents.count))),
                    ("pieces", bencodeData(Data(Insecure.SHA1.hash(data: contents))))
                ])
            )
        )
        let layout = try TorrentContentLayout(metainfo: metainfo, saveDirectory: saveDirectory)
        let workspace = TorrentPeerWorkspace(
            metainfo: metainfo,
            layout: layout,
            resumeStateURL: saveDirectory.appendingPathComponent("demo.resume.json")
        )
        let transport = TimeoutThenMockPeerWireTransport(
            events: [
                .data(try TorrentPeerWireHandshake(
                    infoHash: metainfo.infoHashV1,
                    peerID: Data((60..<80).map(UInt8.init))
                ).encodedData()),
                .data(try TorrentPeerWireMessage.unchoke.encodedData()),
                .timeout,
                .data(try TorrentPeerWireMessage.piece(pieceIndex: 0, begin: 0, block: contents).encodedData())
            ]
        )
        let session = TorrentPeerWireSession(
            metainfo: metainfo,
            layout: layout,
            workspace: workspace,
            transport: transport,
            peerID: Data((40..<60).map(UInt8.init)),
            maximumBlockLength: 8,
            pipelineLimit: 1,
            maximumTimeoutResends: 1
        )

        _ = try await session.downloadPiece(0)

        let sentFrames = await transport.sentFrames
        #expect(sentFrames.count == 4)
        #expect(try TorrentPeerWireMessage.decodeFrame(sentFrames[2]) == .request(pieceIndex: 0, begin: 0, length: 8))
        #expect(try TorrentPeerWireMessage.decodeFrame(sentFrames[3]) == .request(pieceIndex: 0, begin: 0, length: 8))
    }

    @Test("rejects invalid peer piece hashes and preserves pause resume state")
    func rejectsInvalidPeerPieceHashesAndPreservesPauseResumeState() async throws {
        let saveDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: saveDirectory) }

        let contents = Data((0..<20).map(UInt8.init))
        let metainfo = try TorrentMetainfo.parse(
            data: torrentData(
                announce: nil,
                info: bencodeDictionary([
                    ("length", bencodeInteger(Int64(contents.count))),
                    ("name", bencodeString("demo.bin")),
                    ("piece length", bencodeInteger(Int64(contents.count))),
                    ("pieces", bencodeData(Data(Insecure.SHA1.hash(data: contents))))
                ])
            )
        )
        let layout = try TorrentContentLayout(metainfo: metainfo, saveDirectory: saveDirectory)
        let resumeURL = saveDirectory.appendingPathComponent("demo.resume.json")
        let workspace = TorrentPeerWorkspace(
            metainfo: metainfo,
            layout: layout,
            resumeStateURL: resumeURL
        )
        let transport = MockTorrentPeerWireTransport(
            responses: [
                try TorrentPeerWireHandshake(infoHash: metainfo.infoHashV1, peerID: Data((60..<80).map(UInt8.init))).encodedData(),
                try TorrentPeerWireMessage.unchoke.encodedData(),
                try TorrentPeerWireMessage.piece(pieceIndex: 0, begin: 0, block: Data(repeating: 0, count: 20)).encodedData()
            ]
        )
        let session = TorrentPeerWireSession(
            metainfo: metainfo,
            layout: layout,
            workspace: workspace,
            transport: transport,
            peerID: Data((40..<60).map(UInt8.init)),
            maximumBlockLength: 20,
            pipelineLimit: 1
        )

        do {
            _ = try await session.downloadPiece(0)
            #expect(Bool(false), "Expected an invalid piece hash error.")
        } catch let error as TorrentPeerWireError {
            #expect(error == .invalidPieceHash(pieceIndex: 0))
        } catch {
            #expect(Bool(false), "Expected a torrent peer-wire error.")
        }
        #expect(!FileManager.default.fileExists(atPath: layout.files[0].fileURL.path))

        let pausedState = try await session.pause()
        #expect(pausedState.completedPieces.completedPieceIndexes.isEmpty)
        #expect(try await session.resume() != nil)
        try await session.deletePartialData()
        #expect(!FileManager.default.fileExists(atPath: resumeURL.path))
        #expect(!FileManager.default.fileExists(atPath: layout.files[0].fileURL.path))
    }

    private func torrentData(announce: String?, info: Data) -> Data {
        var fields = [(String, Data)]()
        if let announce {
            fields.append(("announce", bencodeString(announce)))
        }
        fields.append(("info", info))
        return bencodeDictionary(fields)
    }

    private func bencodeDictionary(_ fields: [(String, Data)]) -> Data {
        var data = Data("d".utf8)
        for (key, value) in fields.sorted(by: { Array($0.0.utf8).lexicographicallyPrecedes(Array($1.0.utf8)) }) {
            data.append(bencodeString(key))
            data.append(value)
        }
        data.append(UInt8(ascii: "e"))
        return data
    }

    private func bencodeString(_ value: String) -> Data {
        bencodeData(Data(value.utf8))
    }

    private func bencodeData(_ value: Data) -> Data {
        var data = Data("\(value.count):".utf8)
        data.append(value)
        return data
    }

    private func bencodeInteger(_ value: Int64) -> Data {
        Data("i\(value)e".utf8)
    }

    private func oversizedFrameHeader() -> Data {
        let length = UInt32(TorrentPeerWireMessage.maximumFrameLength + 1)
        return Data([
            UInt8((length >> 24) & 0xff),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff)
        ])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor MockTorrentPeerWireTransport: TorrentPeerWireTransport {
    private var responses: [Data]
    private(set) var sentFrames = [Data]()

    init(responses: [Data]) {
        self.responses = responses
    }

    func send(_ data: Data) async throws {
        sentFrames.append(data)
    }

    func receive(maximumLength: Int) async throws -> Data {
        guard !responses.isEmpty else {
            return Data()
        }
        var next = responses.removeFirst()
        if next.count <= maximumLength {
            return next
        }
        let chunk = next.prefix(maximumLength)
        next.removeFirst(maximumLength)
        responses.insert(next, at: 0)
        return Data(chunk)
    }
}

private enum MockPeerWireEvent {
    case data(Data)
    case timeout
}

private actor TimeoutThenMockPeerWireTransport: TorrentPeerWireTransport {
    private var events: [MockPeerWireEvent]
    private(set) var sentFrames = [Data]()

    init(events: [MockPeerWireEvent]) {
        self.events = events
    }

    func send(_ data: Data) async throws {
        sentFrames.append(data)
    }

    func receive(maximumLength: Int) async throws -> Data {
        guard !events.isEmpty else {
            return Data()
        }
        switch events.removeFirst() {
        case .data(let data):
            if data.count <= maximumLength {
                return data
            }
            let chunk = data.prefix(maximumLength)
            events.insert(.data(Data(data.dropFirst(maximumLength))), at: 0)
            return Data(chunk)
        case .timeout:
            throw TorrentPeerWireError.timeout
        }
    }
}
