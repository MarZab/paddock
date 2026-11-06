// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaddockCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PaddockCore", targets: ["PaddockCore"]),
    ],
    dependencies: [
        // SHA-256 for config approval hashes; re-exports CryptoKit on Apple platforms.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.0"),
        // ModelGateway: HTTP server and the upstream client for llmman.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.100.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.36.0"),
        // Markdown for native show tabs (cmark-gfm underneath; backlog doc Browser).
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.0"),
        // Reads paddock.yaml, a project's sbxenv.yaml, and v3 kit descriptors.
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0"),
    ],
    targets: [
        .target(
            name: "PaddockCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Yams", package: "Yams"),
            ],
            // The OpenUI Lang reference agents get (tools/tasks/vendor/openui.sh).
            resources: [.copy("Resources/openui-reference.md")]
        ),
        .testTarget(
            name: "PaddockCoreTests",
            dependencies: [
                "PaddockCore",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ],
            resources: [
                .copy("Fixtures/sbx"),
                .copy("Fixtures/llmman"),
                .copy("Fixtures/config"),
                .copy("Fixtures/lsof"),
                .copy("Fixtures/sandboxd"),
                .copy("Fixtures/host"),
                .copy("Fixtures/sandbox"),
                .copy("Fixtures/voice"),
                .copy("Fixtures/agent"),
                .copy("Fixtures/markdown"),
            ]
        ),
    ]
)
