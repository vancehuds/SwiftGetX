import Testing
@testable import SwiftGetX
@testable import SwiftGetXCore

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

    @Test("task persists only safe browser context")
    func persistsOnlySafeBrowserContext() {
        let rawContext = BrowserDownloadContext(
            referrer: "https://example.com/downloads?token=secret&ok=1",
            userAgent: "ExampleBrowser/1.0",
            method: "GET",
            headers: [
                BrowserDownloadHeader(name: "Authorization", value: "Bearer secret", sensitive: true),
                BrowserDownloadHeader(name: "Cookie", value: "session=secret"),
                BrowserDownloadHeader(name: "Accept-Language", value: "en-US")
            ],
            finalURL: "https://cdn.example.com/file.zip?signature=abc&file=1",
            originalURL: "https://example.com/file.zip?auth=secret",
            suggestedFilename: "file.zip",
            sourcePageTitle: "Downloads",
            sourcePageURL: "https://example.com/downloads?token=secret",
            handoffSource: "download-takeover",
            handoffSourceText: "https://example.com/file.zip?token=secret\nhttps://example.com/other.zip"
        )

        let task = DownloadTask(
            name: "file.zip",
            source: "https://example.com/file.zip?token=secret",
            kind: .http,
            savePath: "/tmp/file.zip",
            browserContext: rawContext.persistable
        )

        #expect(task.browserContext?.headers == [
            BrowserDownloadHeader(name: "Accept-Language", value: "en-US")
        ])
        #expect(task.browserContext?.referrer == "https://example.com/downloads?token=%3Credacted%3E&ok=1")
        #expect(task.browserContext?.finalURL == "https://cdn.example.com/file.zip?signature=%3Credacted%3E&file=1")
        #expect(task.browserContext?.originalURL == "https://example.com/file.zip?auth=%3Credacted%3E")
        #expect(task.browserContext?.handoffSourceText == nil)
        #expect(task.displaySource == "https://cdn.example.com/file.zip?signature=%3Credacted%3E&file=1")
        #expect(task.browserContextJSON?.contains("Bearer secret") == false)
        #expect(task.browserContextJSON?.contains("session=secret") == false)
        #expect(task.browserContextJSON?.contains("other.zip") == false)
    }

    @Test("task persists HTTP response metadata as json")
    func persistsHTTPResponseMetadata() {
        let metadata = HTTPResponseMetadata(
            originalURL: "https://example.com/download?token=secret",
            finalURL: "https://cdn.example.com/file.zip?signature=secret&file=1",
            sourcePageURL: "https://example.com/releases?auth=secret",
            mimeType: "application/zip",
            contentDisposition: "attachment; filename=file.zip",
            suggestedFilename: "file.zip",
            server: "SwiftGetXTest",
            supportsResume: true,
            contentLength: 42,
            eTag: "\"test\"",
            lastModified: "Wed, 21 Oct 2015 07:28:00 GMT",
            redirects: [
                HTTPRedirectMetadata(
                    statusCode: 302,
                    fromURL: "https://example.com/download?token=secret",
                    toURL: "https://cdn.example.com/file.zip?signature=secret&file=1"
                )
            ]
        )
        let task = DownloadTask(
            name: "file.zip",
            source: "https://example.com/download?token=secret",
            kind: .http,
            savePath: "/tmp/file.zip",
            httpResponseMetadata: metadata
        )

        #expect(task.httpResponseMetadata?.finalURL == "https://cdn.example.com/file.zip?signature=%3Credacted%3E&file=1")
        #expect(task.httpResponseMetadata?.sourcePageURL == "https://example.com/releases?auth=%3Credacted%3E")
        #expect(task.httpResponseMetadata?.suggestedFilename == "file.zip")
        #expect(task.httpResponseMetadata?.redirects.first?.fromURL == "https://example.com/download?token=%3Credacted%3E")
        #expect(task.displaySource == "https://cdn.example.com/file.zip?signature=%3Credacted%3E&file=1")
        #expect(task.httpResponseMetadataJSON?.contains("secret") == false)
    }
}
