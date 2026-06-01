import Foundation
import SwiftGetXCore

enum DownloadLinkTrust: Equatable, Sendable {
    case publicLink
    case trustedNativeHandoff
}

struct DownloadDraft: Equatable, Sendable {
    var source: String
    var suggestedFilename: String?
    var browser: String?
    var handoffSource: String?
    var sourcePageTitle: String?
    var sourcePageUrl: String?
    var handoffAck: NativeHandoffAck?
    var browserContext: BrowserDownloadContext?
    var linkTrust: DownloadLinkTrust = .publicLink
    var sourceCount: Int = 1
    var requiresNativePayloadSource = false
    var prefersTorrentInput = false

    var containsTorrentSource: Bool {
        SourceParser.extractSources(from: source).contains {
            SourceParser.kind(for: $0) == .torrentMagnet || SourceParser.kind(for: $0) == .torrentFile
        }
    }

    var isBrowserTakeover: Bool {
        handoffSource == "download-takeover"
    }

    var isTrustedNativeHandoff: Bool {
        linkTrust == .trustedNativeHandoff
    }

    var requiresUserConfirmation: Bool {
        !isTrustedNativeHandoff || sourceCount > 1 || containsTorrentSource
    }

    var canAcknowledgeNativeHandoff: Bool {
        handoffAck?.expiresAt != nil
    }

    var publicLinkFallback: DownloadDraft {
        var draft = self
        draft.handoffSource = nil
        draft.sourcePageTitle = nil
        draft.sourcePageUrl = nil
        draft.handoffAck = nil
        draft.browserContext = nil
        draft.linkTrust = .publicLink
        draft.requiresNativePayloadSource = false
        return draft
    }
}
