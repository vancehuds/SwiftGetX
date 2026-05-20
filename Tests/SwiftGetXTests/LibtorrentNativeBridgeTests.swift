import Foundation
import Testing

#if canImport(CSwiftGetXLibtorrent)
import CSwiftGetXLibtorrent

@Suite("Native libtorrent bridge")
struct LibtorrentNativeBridgeTests {
    @Test("adds torrent file, applies controls, and saves resume data")
    func addsTorrentFileAppliesControlsAndSavesResumeData() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        try Self.singleFileTorrentData(name: "payload.bin", length: 42).write(to: torrentURL)
        let saveURL = directory.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveURL, withIntermediateDirectories: true)
        let resumeURL = directory.appendingPathComponent("fixture.fastresume")

        let session = try #require(sgx_libtorrent_session_create())
        defer {
            sgx_libtorrent_session_destroy(session)
        }

        let handleID = torrentURL.path.withCString { torrentPath in
            saveURL.path.withCString { savePath in
                resumeURL.path.withCString { resumePath in
                    sgx_libtorrent_add_torrent_file_with_options(
                        session,
                        torrentPath,
                        savePath,
                        nil,
                        -1,
                        nil,
                        nil,
                        0,
                        resumePath,
                        0,
                        1,
                        1,
                        1
                    )
                }
            }
        }

        #expect(handleID >= 0)

        var status = SGXTorrentStatus()
        #expect(sgx_libtorrent_get_status(session, handleID, &status) == 1)
        #expect(status.has_metadata == 1)

        sgx_libtorrent_set_file_priority(session, handleID, 0, 7)
        sgx_libtorrent_set_file_selection(session, handleID, nil, 0)
        sgx_libtorrent_set_sequential_download(session, handleID, 1)
        "udp://tracker.example:80".withCString {
            sgx_libtorrent_add_tracker(session, handleID, $0)
        }
        sgx_libtorrent_force_reannounce(session, handleID)
        sgx_libtorrent_pause(session, handleID)
        sgx_libtorrent_resume(session, handleID)

        #expect(sgx_libtorrent_get_status(session, handleID, &status) == 1)
        #expect(status.is_sequential_download == 1)

        #expect(sgx_libtorrent_save_resume_data(session, handleID, resumeURL.path) == 1)
        #expect(FileManager.default.fileExists(atPath: resumeURL.path))

        sgx_libtorrent_remove(session, handleID, 1)
        #expect(sgx_libtorrent_get_status(session, handleID, &status) == 0)
    }

    @Test("reports resume data parse errors before falling back")
    func reportsResumeDataParseErrorsBeforeFallingBack() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let torrentURL = directory.appendingPathComponent("fixture.torrent")
        try Self.singleFileTorrentData(name: "payload.bin", length: 42).write(to: torrentURL)
        let saveURL = directory.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: saveURL, withIntermediateDirectories: true)
        let brokenResumeURL = directory.appendingPathComponent("broken.fastresume")
        try Data().write(to: brokenResumeURL)

        let session = try #require(sgx_libtorrent_session_create())
        defer {
            sgx_libtorrent_session_destroy(session)
        }

        let handleID = torrentURL.path.withCString { torrentPath in
            saveURL.path.withCString { savePath in
                brokenResumeURL.path.withCString { resumePath in
                    sgx_libtorrent_add_torrent_file_with_options(
                        session,
                        torrentPath,
                        savePath,
                        nil,
                        -1,
                        nil,
                        nil,
                        0,
                        resumePath,
                        0,
                        1,
                        1,
                        1
                    )
                }
            }
        }
        defer {
            if handleID >= 0 {
                sgx_libtorrent_remove(session, handleID, 1)
            }
        }

        #expect(handleID >= 0)
        let lastError = try #require(sgx_libtorrent_last_error(session))
        #expect(String(cString: lastError).contains("Resume data is empty"))
    }

    @Test("rejects invalid magnet with native error text")
    func rejectsInvalidMagnetWithNativeErrorText() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let session = try #require(sgx_libtorrent_session_create())
        defer {
            sgx_libtorrent_session_destroy(session)
        }

        let handleID = "magnet:?xt=urn:btih:not-a-valid-hash".withCString { magnet in
            directory.path.withCString { savePath in
                sgx_libtorrent_add_magnet(session, magnet, savePath, nil, -1)
            }
        }

        #expect(handleID < 0)
        let lastError = try #require(sgx_libtorrent_last_error(session))
        #expect(!String(cString: lastError).isEmpty)
    }

    private static func singleFileTorrentData(name: String, length: Int) -> Data {
        let pieceHash = String(repeating: "0", count: 20)
        return Data(
            "d4:infod6:lengthi\(length)e4:name\(name.count):\(name)12:piece lengthi16384e6:pieces20:\(pieceHash)ee".utf8
        )
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
#endif
