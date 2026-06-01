import Foundation
import Testing

@Suite("AppKit migration")
struct AppKitMigrationTests {
    @Test("app UI source no longer declares SwiftUI views")
    func appUISourceNoLongerDeclaresSwiftUIViews() throws {
        let root = try repositoryRoot()
        let appSourceRoot = root.appendingPathComponent("Sources/SwiftGetX")
        let uiRoot = appSourceRoot.appendingPathComponent("UI")
        let swiftFiles = try swiftFiles(in: uiRoot)
            + [appSourceRoot.appendingPathComponent("Services/SoftwareUpdater.swift")]
            + [appSourceRoot.appendingPathComponent("Utilities/L10n.swift")]
            + [uiRoot.appendingPathComponent("DownloadDropSourceLoader.swift")]

        var violations = [String]()
        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            if source.contains("import SwiftUI") {
                violations.append("\(relativePath): imports SwiftUI")
            }
            if source.range(of: #"struct\s+\w+\s*:\s*View"#, options: .regularExpression) != nil {
                violations.append("\(relativePath): declares a SwiftUI View")
            }
            if source.contains("CheckForUpdatesView") {
                violations.append("\(relativePath): still declares CheckForUpdatesView")
            }
        }

        #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "\n")))
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls = [URL]()
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            urls.append(fileURL)
        }
        return urls
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let candidate = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw AppKitMigrationTestError.repositoryRootNotFound
    }
}

private enum AppKitMigrationTestError: Error {
    case repositoryRootNotFound
}
