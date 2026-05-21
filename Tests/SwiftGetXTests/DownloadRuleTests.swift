import Foundation
import Testing
import SwiftGetXCore
@testable import SwiftGetX

@Suite("Download Rules")
struct DownloadRuleTests {
    @Test("parses rules, filters sensitive headers, and renders filename templates")
    func parsesRulesAndRendersTemplates() throws {
        let text = """
        # comments are ignored
        domain=*.Example.com | ext=zip,dmg | min=10MB | max=2GB | dir=/tmp/SwiftGetX Apps | segments=12 | retries=5 | autoStart=false | template={date}/{domain}/{basename}.{ext} | header=Accept-Language: en-US | header=Authorization: Bearer secret
        """

        let rule = try #require(DownloadRuleTextFormat.parse(text).first)
        let date = Date(timeIntervalSince1970: 1_735_084_800)
        let plannedURL = rule.plannedSaveURL(
            fallbackURL: URL(fileURLWithPath: "/tmp/fallback/archive.zip"),
            source: "https://downloads.example.com/releases/archive.zip",
            filename: "archive.zip",
            date: date
        )

        #expect(rule.domains == ["example.com"])
        #expect(rule.fileExtensions == ["zip", "dmg"])
        #expect(rule.minSizeBytes == Int64(10 * 1_024 * 1_024))
        #expect(rule.maxSizeBytes == Int64(2 * 1_024 * 1_024 * 1_024))
        #expect(rule.segmentCount == 12)
        #expect(rule.retryLimit == 5)
        #expect(rule.autoStart == false)
        #expect(rule.headers == [BrowserDownloadHeader(name: "Accept-Language", value: "en-US")])
        #expect(rule.matches(
            source: "https://downloads.example.com/releases/archive.zip",
            kind: .http,
            filename: "archive.zip",
            totalBytes: 42 * 1_024 * 1_024
        ))
        #expect(!rule.matches(
            source: "https://downloads.example.com/releases/archive.txt",
            kind: .http,
            filename: "archive.txt",
            totalBytes: 42 * 1_024 * 1_024
        ))
        #expect(plannedURL.path == "/tmp/SwiftGetX Apps/2024-12-25/downloads.example.com/archive.zip")
    }

    @Test("browser takeover host policy blocks and allowlists hosts")
    func browserTakeoverHostPolicyDecisions() {
        #expect(BrowserTakeoverPolicy.decision(
            for: "https://cdn.example.com/file.zip",
            allowedHosts: [],
            blockedHosts: ["example.com"]
        ) == .rejected(reason: "blockedByHostPolicy"))

        #expect(BrowserTakeoverPolicy.decision(
            for: "https://cdn.example.com/file.zip",
            allowedHosts: ["example.com"],
            blockedHosts: []
        ) == .allowed)

        #expect(BrowserTakeoverPolicy.decision(
            for: "https://blocked.example.net/file.zip",
            allowedHosts: ["example.com"],
            blockedHosts: []
        ) == .rejected(reason: "notAllowedByHostPolicy"))

        #expect(BrowserTakeoverPolicy.decision(
            for: "https://badexample.com/file.zip",
            allowedHosts: [],
            blockedHosts: ["example.com"]
        ) == .allowed)
    }
}
