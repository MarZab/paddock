// swift-tools-version: 6.0
import PackageDescription

// PaddockShell: a reusable sandbox terminal (backlog doc PaddockShell). PaddockShellCore has no UI
// and builds on Linux; PaddockShellUI wraps SwiftTerm and is macOS only.
let package = Package(
    name: "PaddockShell",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PaddockShellCore", targets: ["PaddockShellCore"]),
        .library(name: "PaddockShellUI", targets: ["PaddockShellUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", .upToNextMinor(from: "1.20.0")),
    ],
    targets: [
        // The pseudo-terminal calls, in C because glibc only declares them behind feature macros.
        .target(name: "CPaddockPTY"),
        .target(name: "PaddockShellCore", dependencies: ["CPaddockPTY"]),
        .target(
            name: "PaddockShellUI",
            dependencies: [
                "PaddockShellCore",
                .product(name: "SwiftTerm", package: "SwiftTerm", condition: .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(name: "PaddockShellCoreTests", dependencies: ["PaddockShellCore"]),
    ]
)
