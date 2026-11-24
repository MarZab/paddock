// swift-tools-version: 6.0
import PackageDescription

// PaddockA2UI: A2UI tabs rendered natively (PAD-146; backlog doc Browser, interactive tabs). macOS
// only: A2UI's Swift core imports Combine. Paddock's own rules for what crosses between a sandbox
// and a tab (A2UIPolicy, A2UIMedia) are in PaddockCore, which needs no A2UI and is tested on Linux.
let package = Package(
    name: "PaddockA2UI",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PaddockA2UI", targets: ["PaddockA2UI"]),
    ],
    dependencies: [
        .package(path: "../PaddockCore"),
        // A2UI's Swift core and SwiftUI renderer, one exact release (tag v0.12.0+swift; its
        // fixtures are in PaddockCore's Fixtures/a2ui). Its schema plugin needs Trust & Enable in Xcode.
        .package(url: "https://github.com/a2ui-project/a2ui.git", exact: "0.12.0"),
        // OrderedJSON's JSONValue is what A2UI's message processor reads; the same range as A2UI's.
        .package(url: "https://github.com/ajevans99/swift-json-schema", .upToNextMinor(from: "0.13.1")),
    ],
    targets: [
        .target(
            name: "PaddockA2UI",
            dependencies: [
                .product(name: "PaddockCore", package: "PaddockCore"),
                .product(name: "A2UISwiftCore", package: "a2ui"),
                .product(name: "A2UISwiftUI", package: "a2ui"),
                .product(name: "BasicCatalog", package: "a2ui"),
                .product(name: "BasicCatalogSwiftUI", package: "a2ui"),
                .product(name: "OrderedJSON", package: "swift-json-schema"),
            ]
        ),
        .testTarget(
            name: "PaddockA2UITests",
            dependencies: [
                "PaddockA2UI",
                .product(name: "PaddockCore", package: "PaddockCore"),
                .product(name: "A2UISwiftCore", package: "a2ui"),
                .product(name: "A2UISwiftUI", package: "a2ui"),
                .product(name: "BasicCatalog", package: "a2ui"),
                .product(name: "OrderedJSON", package: "swift-json-schema"),
            ]
        ),
    ]
)
