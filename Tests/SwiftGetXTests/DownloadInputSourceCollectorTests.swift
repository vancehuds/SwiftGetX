import Foundation
import AppKit
import Testing
@testable import SwiftGetX

@Suite("DownloadInputSourceCollector")
struct DownloadInputSourceCollectorTests {
    @Test("collects text, URL, magnet, and torrent file sources")
    func collectsDroppedSources() throws {
        let torrentURL = URL(fileURLWithPath: "/tmp/SwiftGetX Demo.torrent")
        let draft = try #require(DownloadInputSourceCollector.draft(
            textFragments: [
                """
                https://example.com/file.zip
                magnet:?xt=urn:btih:abcdef&dn=Demo
                """
            ],
            urls: [
                torrentURL,
                URL(string: "https://example.com/releases/app.dmg")!
            ]
        ))

        let sources = SourceParser.extractSources(from: draft.source)
        #expect(draft.linkTrust == .publicLink)
        #expect(draft.sourceCount == 4)
        #expect(sources == [
            "https://example.com/file.zip",
            "magnet:?xt=urn:btih:abcdef&dn=Demo",
            "/tmp/SwiftGetX Demo.torrent",
            "https://example.com/releases/app.dmg"
        ])
    }

    @Test("deduplicates repeated dropped sources")
    func deduplicatesRepeatedSources() throws {
        let draft = try #require(DownloadInputSourceCollector.draft(
            textFragments: [
                "https://example.com/file.zip\nhttps://example.com/file.zip"
            ],
            urls: [
                URL(string: "https://example.com/file.zip")!
            ]
        ))

        #expect(draft.source == "https://example.com/file.zip")
        #expect(draft.sourceCount == 1)
    }

    @Test("deduplicates local torrent paths and file URLs")
    func deduplicatesLocalTorrentPathsAndFileURLs() throws {
        let draft = try #require(DownloadInputSourceCollector.draft(
            textFragments: [
                "/tmp/SwiftGetX Demo.torrent"
            ],
            urls: [
                URL(fileURLWithPath: "/tmp/SwiftGetX Demo.torrent")
            ]
        ))

        #expect(draft.source == "/tmp/SwiftGetX Demo.torrent")
        #expect(draft.sourceCount == 1)
    }

    @Test("collects Services pasteboard sources")
    func collectsServicesPasteboardSources() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("SwiftGetXTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setString(
            """
            https://example.com/from-text.zip
            magnet:?xt=urn:btih:abcdef&dn=Text
            """,
            forType: .string
        )
        pasteboard.setPropertyList(
            ["/tmp/Service Demo.torrent", "/tmp/ignored.txt"],
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        )

        let draft = try #require(DownloadInputSourceCollector.draft(from: pasteboard))
        let sources = SourceParser.extractSources(from: draft.source)

        #expect(draft.sourceCount == 3)
        #expect(sources == [
            "https://example.com/from-text.zip",
            "magnet:?xt=urn:btih:abcdef&dn=Text",
            "/tmp/Service Demo.torrent"
        ])
    }

    @Test("ignores unsupported dropped content")
    func ignoresUnsupportedDroppedContent() {
        let draft = DownloadInputSourceCollector.draft(
            textFragments: ["mailto:demo@example.com\njust text"],
            urls: [URL(fileURLWithPath: "/tmp/not-a-torrent.txt")]
        )

        #expect(draft == nil)
    }
}
