// swift-tools-version: 6.0

import PackageDescription
import Foundation

let disableNativeLibtorrent = ProcessInfo.processInfo.environment["SWIFTGETX_DISABLE_LIBTORRENT"] == "1"
let requestNativeLibtorrent = ProcessInfo.processInfo.environment["SWIFTGETX_ENABLE_LIBTORRENT"] == "1"
let enableNativeLibtorrent = requestNativeLibtorrent && !disableNativeLibtorrent
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let homebrewPrefix = ProcessInfo.processInfo.environment["SWIFTGETX_HOMEBREW_PREFIX"] ?? "/opt/homebrew"
let libtorrentArchivePath = "\(packageDirectory)/.build/libtorrent/libtorrent-build/libtorrent-rasterbar.a"

if enableNativeLibtorrent && !FileManager.default.fileExists(atPath: libtorrentArchivePath) {
    fatalError("SwiftGetX native libtorrent builds require \(libtorrentArchivePath). Run Scripts/build-libtorrent.sh first, or unset SWIFTGETX_ENABLE_LIBTORRENT for the lightweight fallback build.")
}

var swiftGetXDependencies: [Target.Dependency] = ["SwiftGetXCore"]
var targets: [Target] = [
    .target(
        name: "SwiftGetXCore",
        path: "Sources/SwiftGetXCore"
    )
]

if enableNativeLibtorrent {
    swiftGetXDependencies.append("CSwiftGetXLibtorrent")
    targets.append(
        .target(
            name: "CSwiftGetXLibtorrent",
            dependencies: [],
            path: "Sources/CSwiftGetXLibtorrent",
            exclude: [
                "module.modulemap"
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../../Vendor/libtorrent/include"),
                .headerSearchPath("../../Vendor/libtorrent/deps/try_signal"),
                .define("BOOST_ASIO_ENABLE_CANCELIO"),
                .define("BOOST_ASIO_NO_DEPRECATED"),
                .define("OPENSSL_NO_DTLS1"),
                .define("OPENSSL_NO_SSL2"),
                .define("OPENSSL_NO_SSL3"),
                .define("OPENSSL_NO_TLS1"),
                .define("OPENSSL_NO_TLS1_1"),
                .define("TORRENT_DISABLE_LOGGING"),
                .define("TORRENT_NO_DEPRECATE"),
                .define("TORRENT_SSL_PEERS"),
                .define("TORRENT_USE_LIBCRYPTO"),
                .define("TORRENT_USE_OPENSSL"),
                .unsafeFlags(["-I\(homebrewPrefix)/include"])
            ],
            linkerSettings: [
                .linkedFramework("SystemConfiguration"),
                .linkedLibrary("crypto"),
                .linkedLibrary("ssl"),
                .unsafeFlags([
                    libtorrentArchivePath,
                    "-L\(homebrewPrefix)/lib"
                ])
            ]
        )
    )
}

let package = Package(
    name: "SwiftGetX",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SwiftGetX", targets: ["SwiftGetX"]),
        .executable(name: "SwiftGetXNativeHost", targets: ["SwiftGetXNativeHost"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: targets + [
        .executableTarget(
            name: "SwiftGetX",
            dependencies: swiftGetXDependencies + [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            exclude: [
                "Resources/Assets/AppIcon.iconset"
            ],
            resources: [
                .copy("Resources/SafariWebExtension"),
                .copy("Resources/ChromeExtension"),
                .copy("Resources/NativeMessaging"),
                .copy("Resources/AppInfo.plist"),
                .copy("Resources/Assets/AppIcon.icns"),
                .copy("Resources/Assets/AppIcon.png"),
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "SwiftGetXNativeHost",
            dependencies: ["SwiftGetXCore"],
            path: "Sources/SwiftGetXNativeHost"
        ),
        .testTarget(
            name: "SwiftGetXTests",
            dependencies: ["SwiftGetX", "SwiftGetXCore"]
        )
    ]
)
