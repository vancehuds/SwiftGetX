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
}
