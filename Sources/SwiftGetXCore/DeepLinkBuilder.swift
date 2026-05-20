import Foundation

public enum DeepLinkBuilder {
    public static func downloadURL(
        for source: String,
        browser: String? = nil,
        suggestedFilename: String? = nil,
        handoffSource: String? = nil,
        sourcePageTitle: String? = nil,
        sourcePageUrl: String? = nil,
        handoffAck: NativeHandoffAck? = nil,
        requiresPayloadSource: Bool = false
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "swiftgetx"
        components.host = "download"
        components.queryItems = [
            URLQueryItem(name: "url", value: source)
        ]
        appendQueryItem("browser", value: browser, to: &components)
        appendQueryItem("filename", value: suggestedFilename, to: &components)
        appendQueryItem("source", value: handoffSource, to: &components)
        appendQueryItem("sourcePageTitle", value: sourcePageTitle, to: &components)
        appendQueryItem("sourcePageUrl", value: sourcePageUrl, to: &components)
        if requiresPayloadSource {
            appendQueryItem("payloadSource", value: "1", to: &components)
        }
        if let handoffAck {
            appendQueryItem("ackRequestID", value: handoffAck.requestID, to: &components)
            appendQueryItem("ackToken", value: handoffAck.token, to: &components)
            appendQueryItem("ackPort", value: String(handoffAck.port), to: &components)
            if let expiresAt = handoffAck.expiresAt {
                appendQueryItem(
                    "ackExpiresAt",
                    value: String(expiresAt.timeIntervalSince1970),
                    to: &components
                )
            }
        }
        return components.url
    }

    private static func appendQueryItem(_ name: String, value: String?, to components: inout URLComponents) {
        guard let value, !value.isEmpty else { return }
        components.queryItems?.append(URLQueryItem(name: name, value: value))
    }
}
