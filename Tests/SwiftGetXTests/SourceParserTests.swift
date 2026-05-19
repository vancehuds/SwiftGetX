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

    @Test("extracts markdown links and trims punctuation")
    func extractsMarkdownLinksAndTrimsPunctuation() {
        let sources = SourceParser.extractSources(
            from: """
            [release](https://example.com/releases/app.zip), and
            <https://example.com/build.tar.gz>.
            """
        )

        #expect(sources == [
            "https://example.com/releases/app.zip",
            "https://example.com/build.tar.gz"
        ])
    }

    @Test("normalizes GitHub Actions artifact page links")
    func normalizesGitHubActionsArtifactPageLinks() {
        let sources = SourceParser.extractSources(
            from: "[vancehuds/SwiftGetX](https://github.com/vancehuds/SwiftGetX/actions/runs/26096865299/artifacts/7083295315)"
        )

        #expect(sources == [
            "https://api.github.com/repos/vancehuds/SwiftGetX/actions/artifacts/7083295315/zip"
        ])
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

    @Test("names GitHub Actions artifact archives")
    func namesGitHubActionsArtifactArchives() {
        let name = SourceParser.displayName(
            for: "https://api.github.com/repos/vancehuds/SwiftGetX/actions/artifacts/7083295315/zip",
            kind: .http
        )

        #expect(name == "SwiftGetX-artifact-7083295315.zip")
    }
}
