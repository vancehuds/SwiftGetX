import Foundation

struct DownloadDraft: Equatable, Sendable {
    var source: String
    var suggestedFilename: String?
    var browser: String?
    var handoffSource: String?
    var sourcePageTitle: String?
    var sourcePageUrl: String?

    var isBrowserTakeover: Bool {
        handoffSource == "download-takeover"
    }
}
