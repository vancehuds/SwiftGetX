import Foundation
import Testing
@testable import SwiftGetX

@Suite("Torrent UX support")
@MainActor
struct TorrentUXSupportTests {
    @Test("tracker batch validation deduplicates and reports invalid entries")
    func trackerBatchValidationDeduplicatesAndReportsInvalidEntries() {
        let validation = TorrentTrackerBatchParser.validate(
            """
            udp://tracker.example:80/announce
            https://tracker.example/announce
            udp://tracker.example:80/announce
            ftp://tracker.example/announce
            not-a-url
            http://existing.example/announce
            """,
            existingURLs: ["http://existing.example/announce"]
        )

        #expect(validation.validURLs == [
            "udp://tracker.example:80/announce",
            "https://tracker.example/announce",
            "http://existing.example/announce"
        ])
        #expect(validation.newURLs == [
            "udp://tracker.example:80/announce",
            "https://tracker.example/announce"
        ])
        #expect(validation.duplicateURLs == [
            "udp://tracker.example:80/announce",
            "http://existing.example/announce"
        ])
        #expect(validation.invalidEntries == [
            "ftp://tracker.example/announce",
            "not-a-url"
        ])
        #expect(validation.hasUsableAdditions)
    }

    @Test("file tree helpers filter files and apply bulk priorities")
    func fileTreeHelpersFilterFilesAndApplyBulkPriorities() {
        let files = [
            TorrentFile(index: 0, path: "Show/Season 1/episode.mkv", size: 100),
            TorrentFile(index: 1, path: "Show/Season 1/subtitle.srt", size: 10),
            TorrentFile(index: 2, path: "Show/extras/readme.txt", size: 5)
        ]

        let folders = TorrentFileUX.folderGroups(in: files)
        #expect(folders.map(\.path) == [
            "Show",
            "Show/Season 1",
            "Show/extras"
        ])
        #expect(folders.first?.fileIndexes == [0, 1, 2])

        #expect(TorrentFileUX.filteredFiles(files, searchText: "season").map(\.index) == [0, 1])
        #expect(TorrentFileUX.fileIndexes(in: files, matchingExtensions: ".mkv, srt") == [0, 1])

        let plan = TorrentFileUX.apply(
            priority: .skip,
            to: [1, 2],
            files: files,
            selectedFileIndexes: [0, 1, 2],
            priorities: [
                0: .normal,
                1: .normal,
                2: .normal
            ]
        )

        #expect(plan.selectedFileIndexes == [0])
        #expect(plan.priorities[1] == .skip)
        #expect(plan.priorities[2] == .skip)
    }

    @Test("torrent advice calls out missing resume data and recovery logging")
    func torrentAdviceCallsOutMissingResumeDataAndRecoveryLogging() {
        let task = DownloadTask(
            name: "Demo",
            source: "magnet:?xt=urn:btih:0123456789012345678901234567890123456789",
            kind: .torrentMagnet,
            status: .paused,
            savePath: "/tmp",
            downloadedBytes: 10,
            supportsResume: true
        )

        let messages = TorrentStatusAdvice.messages(for: task)
        #expect(messages.contains(L10n.string("torrent_advice_resume_missing")))
        #expect(TorrentStatusAdvice.restartRecoveryMessages(for: task) == [
            L10n.string("log_torrent_resume_data_missing_recheck")
        ])

        task.torrentResumeState = TorrentResumeState(
            resumeDataPath: "/tmp/demo.resume.json",
            status: .saved
        )

        #expect(TorrentStatusAdvice.restartRecoveryMessages(for: task) == [
            L10n.string("log_torrent_resume_data_available")
        ])
    }
}
