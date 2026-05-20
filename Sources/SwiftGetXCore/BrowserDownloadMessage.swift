import Foundation

public struct BrowserDownloadMessage: Codable, Sendable {
    public var action: String
    public var url: String?
    public var browser: String?
    public var suggestedFilename: String?
    public var sourcePageTitle: String?
    public var sourcePageUrl: String?
    public var source: String?
    public var context: BrowserDownloadContext?

    public init(
        action: String,
        url: String? = nil,
        browser: String? = nil,
        suggestedFilename: String? = nil,
        sourcePageTitle: String? = nil,
        sourcePageUrl: String? = nil,
        source: String? = nil,
        context: BrowserDownloadContext? = nil
    ) {
        self.action = action
        self.url = url
        self.browser = browser
        self.suggestedFilename = suggestedFilename
        self.sourcePageTitle = sourcePageTitle
        self.sourcePageUrl = sourcePageUrl
        self.source = source
        self.context = context
    }
}
