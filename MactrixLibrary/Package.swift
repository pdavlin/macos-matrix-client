// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MactrixLibrary",
    platforms: [.macOS("26.0")],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "UI",
            targets: ["UI"]
        ),
        .library(
            name: "Models",
            targets: ["Models"]
        ),
        .library(name: "Utils", targets: ["Utils"]),
        .library(name: "MessageFormatting", targets: ["MessageFormatting"]),
        .library(name: "Tokens", targets: ["Tokens"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ZhgChgLi/ZMarkupParser.git", from: "1.12.0"),
        // .package(url: "https://github.com/matrix-org/matrix-rust-components-swift", from: "25.10.27"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", exact: "1.19.4"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "UI",
            dependencies: ["Models", "Tokens"]
        ),
        .target(name: "Utils"),
        .testTarget(name: "UtilsTests", dependencies: ["Utils"]),
        .testTarget(
            name: "UITests",
            dependencies: [
                "UI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            resources: [.copy("__Snapshots__")]
        ),
        /* .target(
                name: "TimelineUI",
                dependencies: ["Models", .product(name: "MatrixRustSDK", package: "matrix-rust-components-swift")]
            ), */
        .target(
            name: "Models"
        ),
        .testTarget(name: "ModelsTests", dependencies: ["Models"]),
        .target(
            name: "MessageFormatting",
            dependencies: [
                "ZMarkupParser",
                "Tokens",
            ]
        ),
        .target(name: "Tokens"),
        .testTarget(name: "TokensTests", dependencies: ["Tokens"]),
    ]
)
