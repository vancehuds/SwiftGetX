import Foundation

public enum DeepLinkBuilder {
    public static func downloadURL(for source: String) -> URL? {
        var components = URLComponents()
        components.scheme = "swiftgetx"
        components.host = "download"
        components.queryItems = [
            URLQueryItem(name: "url", value: source)
        ]
        return components.url
    }
}
