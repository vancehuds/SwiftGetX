import Testing
@testable import SwiftGetX

@Suite("SourceParser")
struct SourceParserTests {
    @Test("extracts supported sources from mixed text")
    func extractsSources() {
        let sources = SourceParser.extractSources(
            from: """
            https://example.com/file.zip
            not-a-link
            magnet:?xt=urn:btih:abcdef&dn=Ubuntu
            https://example.com/demo.torrent
            """
        )

        #expect(sources.count == 3)
        #expect(sources[0] == "https://example.com/file.zip")
        #expect(sources[1].hasPrefix("magnet:"))
        #expect(sources[2].hasSuffix(".torrent"))
    }

    @Test("detects task kinds")
    func detectsKinds() {
        #expect(SourceParser.kind(for: "https://example.com/file.zip") == .http)
        #expect(SourceParser.kind(for: "magnet:?xt=urn:btih:abcdef") == .torrentMagnet)
        #expect(SourceParser.kind(for: "https://example.com/file.torrent") == .torrentFile)
    }

    @Test("uses magnet display name")
    func magnetName() {
        let name = SourceParser.displayName(
            for: "magnet:?xt=urn:btih:abcdef&dn=SwiftGetX%20Demo",
            kind: .torrentMagnet
        )

        #expect(name == "SwiftGetX Demo")
    }

    @Test("sanitizes unsafe filename characters")
    func sanitizesUnsafeFilenameCharacters() {
        let name = SourceParser.displayName(
            for: "magnet:?xt=urn:btih:abcdef&dn=bad/name%3Afile",
            kind: .torrentMagnet
        )

        #expect(name == "bad-name-file")
    }
}
