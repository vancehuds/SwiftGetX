import Foundation

enum AppResources {
    static let resourceBundleName = "SwiftGetX_SwiftGetX"

    static var bundle: Bundle {
        resolvedBundle ?? .main
    }

    static func url(forResource name: String, withExtension extensionName: String? = nil) -> URL? {
        if let url = bundle.url(forResource: name, withExtension: extensionName) {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: extensionName)
    }

    private static let resolvedBundle: Bundle? = {
        for url in candidateBundleURLs() {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }

        for url in candidateResourceDirectories() where containsLocalizedStrings(at: url) {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }

        return nil
    }()

    private static func candidateBundleURLs() -> [URL] {
        let bundleFilename = "\(resourceBundleName).bundle"
        var candidates: [URL] = []
        let mainBundleURL = Bundle.main.bundleURL

        candidates.append(mainBundleURL.appendingPathComponent("Contents/Resources/\(bundleFilename)"))
        candidates.append(mainBundleURL.appendingPathComponent(bundleFilename))

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(bundleFilename))
        }

        if let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(executableDirectory.appendingPathComponent(bundleFilename))
            candidates.append(executableDirectory.deletingLastPathComponent().appendingPathComponent(bundleFilename))
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(currentDirectory.appendingPathComponent("Sources/SwiftGetX/Resources"))
        candidates.append(currentDirectory.appendingPathComponent(".build/arm64-apple-macosx/debug/\(bundleFilename)"))
        candidates.append(currentDirectory.appendingPathComponent(".build/arm64-apple-macosx/release/\(bundleFilename)"))

        return deduplicated(candidates)
    }

    private static func candidateResourceDirectories() -> [URL] {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return deduplicated([
            currentDirectory.appendingPathComponent("Sources/SwiftGetX/Resources")
        ])
    }

    private static func containsLocalizedStrings(at url: URL) -> Bool {
        let enStrings = url.appendingPathComponent("en.lproj/Localizable.strings")
        return FileManager.default.fileExists(atPath: enStrings.path)
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let standardizedURL = url.standardizedFileURL
            guard seen.insert(standardizedURL.path).inserted else { continue }
            result.append(standardizedURL)
        }
        return result
    }
}
