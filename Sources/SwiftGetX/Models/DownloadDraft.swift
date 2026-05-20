import Foundation
import SwiftGetXCore

struct DownloadDraft: Equatable, Sendable {
    var source: String
    var suggestedFilename: String?
    var browser: String?
    var handoffSource: String?
    var sourcePageTitle: String?
    var sourcePageUrl: String?
    var handoffAck: NativeHandoffAck?
    var browserContext: BrowserDownloadContext?

    var isBrowserTakeover: Bool {
        handoffSource == "download-takeover"
    }
}
