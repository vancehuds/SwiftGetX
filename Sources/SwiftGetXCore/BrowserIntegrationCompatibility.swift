import Foundation

public struct BrowserIntegrationCompatibilityResult: Equatable, Sendable {
    public var compatible: Bool
    public var message: String?

    public init(compatible: Bool, message: String? = nil) {
        self.compatible = compatible
        self.message = message
    }
}

public enum BrowserIntegrationCompatibility {
    public static let protocolVersion = 1
    public static let nativeHostVersion = "0.2.0"
    public static let minimumChromeExtensionVersion = "0.2.0"
    public static let minimumNativeHostVersion = "0.2.0"

    public static func extensionCompatibility(
        extensionVersion: String?,
        minimumNativeHostVersion: String?,
        protocolVersion: Int?,
        requiresExplicitVersion: Bool
    ) -> BrowserIntegrationCompatibilityResult {
        if requiresExplicitVersion,
           extensionVersion?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            return BrowserIntegrationCompatibilityResult(
                compatible: false,
                message: "SwiftGetX extension version is missing. Reinstall the current extension package."
            )
        }

        if let protocolVersion, protocolVersion != Self.protocolVersion {
            return BrowserIntegrationCompatibilityResult(
                compatible: false,
                message: "SwiftGetX browser protocol \(protocolVersion) is not compatible with protocol \(Self.protocolVersion)."
            )
        } else if requiresExplicitVersion && protocolVersion == nil {
            return BrowserIntegrationCompatibilityResult(
                compatible: false,
                message: "SwiftGetX browser protocol version is missing. Reinstall the current extension package."
            )
        }

        if let extensionVersion,
           !isVersion(extensionVersion, atLeast: minimumChromeExtensionVersion) {
            return BrowserIntegrationCompatibilityResult(
                compatible: false,
                message: "SwiftGetX extension \(extensionVersion) is older than the required \(minimumChromeExtensionVersion)."
            )
        }

        if let minimumNativeHostVersion,
           !isVersion(nativeHostVersion, atLeast: minimumNativeHostVersion) {
            return BrowserIntegrationCompatibilityResult(
                compatible: false,
                message: "SwiftGetX Native Host \(nativeHostVersion) is older than the extension-required \(minimumNativeHostVersion)."
            )
        }

        return BrowserIntegrationCompatibilityResult(compatible: true)
    }

    public static func nativeHostCompatibility(
        nativeHostVersion: String?,
        protocolVersion: Int?
    ) -> BrowserIntegrationCompatibilityResult {
        guard let nativeHostVersion, isVersion(nativeHostVersion, atLeast: minimumNativeHostVersion) else {
            return BrowserIntegrationCompatibilityResult(
                compatible: false,
                message: "SwiftGetX Native Host must be at least \(minimumNativeHostVersion)."
            )
        }

        guard protocolVersion == Self.protocolVersion else {
            let value = protocolVersion.map(String.init) ?? "missing"
            return BrowserIntegrationCompatibilityResult(
                compatible: false,
                message: "SwiftGetX Native Host protocol \(value) is not compatible with protocol \(Self.protocolVersion)."
            )
        }

        return BrowserIntegrationCompatibilityResult(compatible: true)
    }

    public static func isVersion(_ version: String, atLeast minimumVersion: String) -> Bool {
        guard let currentComponents = versionComponents(version),
              let minimumComponents = versionComponents(minimumVersion) else {
            return false
        }
        return currentComponents.lexicographicallyPrecedes(minimumComponents) == false
    }

    private static func versionComponents(_ version: String) -> [Int]? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased().hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let components = normalized
            .split { !$0.isNumber }
            .prefix(3)
            .compactMap { Int($0) }
        guard !components.isEmpty else { return nil }
        return Array(components) + Array(repeating: 0, count: max(0, 3 - components.count))
    }
}
