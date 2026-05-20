import Testing
@testable import SwiftGetX

@Suite("Torrent files")
struct TorrentFileTests {
    @Test("task persists torrent files as json")
    func persistsTorrentFiles() {
        let task = DownloadTask(
            name: "demo",
            source: "magnet:?xt=urn:btih:abcdef",
            kind: .torrentMagnet,
            savePath: "/tmp/demo"
        )
        task.torrentFiles = [
            TorrentFile(index: 0, path: "a.bin", size: 10, progress: 0.5),
            TorrentFile(index: 1, path: "b.bin", size: 20, progress: 0)
        ]

        #expect(task.torrentFiles == [
            TorrentFile(index: 0, path: "a.bin", size: 10, progress: 0.5),
            TorrentFile(index: 1, path: "b.bin", size: 20, progress: 0)
        ])
    }

    @Test("task persists torrent diagnostics as json")
    func persistsTorrentDiagnostics() {
        let task = DownloadTask(
            name: "demo",
            source: "magnet:?xt=urn:btih:abcdef",
            kind: .torrentMagnet,
            savePath: "/tmp/demo"
        )
        task.torrentRuntimeOptions = TorrentRuntimeOptions(
            isDHTEnabled: false,
            isPEXEnabled: true,
            isLSDEnabled: false,
            isSequentialDownloadEnabled: true,
            magnetMetadataTimeoutSeconds: 30,
            maxConnections: 64,
            maxUploadSlots: 4,
            seedingLimitMode: .neverStop,
            stopSeedingAtRatio: 2
        )
        task.torrentResumeState = TorrentResumeState(
            resumeDataPath: "/tmp/demo.fastresume",
            status: .saved
        )
        task.torrentTrackers = [
            TorrentTrackerInfo(url: "udp://tracker.example:80", tier: 1, status: "working")
        ]
        task.torrentPeers = [
            TorrentPeerInfo(
                address: "127.0.0.1:6881",
                client: "Test",
                progress: 0.5,
                downloadRate: 10,
                uploadRate: 5,
                direction: "out",
                flags: "dht"
            )
        ]
        task.torrentHealth = TorrentHealthInfo(
            nativeEngineAvailable: true,
            hasMetadata: true,
            isSequentialDownload: true,
            needsResumeDataSave: false,
            peerCount: 1,
            connectionCount: 1,
            uploadSlotCount: 1,
            listenPort: 6881,
            dhtNodeCount: 0,
            distributedCopies: 1,
            trackerCount: 1
        )

        #expect(task.torrentRuntimeOptions?.seedingLimitMode == .neverStop)
        #expect(task.torrentRuntimeOptions?.isSequentialDownloadEnabled == true)
        #expect(task.torrentResumeState?.status == .saved)
        #expect(task.torrentTrackers.first?.url == "udp://tracker.example:80")
        #expect(task.torrentPeers.first?.client == "Test")
        #expect(task.torrentHealth?.listenPort == 6881)
    }
}
