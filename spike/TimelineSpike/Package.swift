// swift-tools-version: 6.1
import PackageDescription

// Standalone spike package. It is deliberately NOT part of Mactrix.xcodeproj and it
// never builds or links matrix-rust-sdk. See spike/SCENARIOS.md for the measurement
// protocol that S-13 and S-14 must follow.
let package = Package(
    name: "TimelineSpike",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "TimelineSpikeApp", targets: ["TimelineSpikeApp"]),
        .library(name: "TimelineSpikeCore", targets: ["TimelineSpikeCore"])
    ],
    dependencies: [
        // S-39: the shipping row layer (Models, UI, Tokens, Utils). MATRIX-81:
        // MactrixLibrary now declares matrix-rust-components-swift for its Core
        // product. No target here uses Core, so the real SDK is never built.
        .package(path: "../../MactrixLibrary")
    ],
    targets: [
        .target(name: "TimelineSpikeCore"),
        // S-39: the production container's own `import MatrixRustSDK` resolves
        // to this shim, so those files compile inside this package unedited.
        // MATRIX-81: the target cannot be named `MatrixRustSDK` any more, because
        // the real SDK package is now in the graph and target names must be
        // unique. ProductionTimeline aliases the name instead. See the README.
        .target(name: "MatrixRustSDKShim", dependencies: [
            .product(name: "Models", package: "MactrixLibrary")
        ], exclude: ["README.md"]),
        // S-39: the real M1 container, compiled from symlinks to the app's
        // files, plus the shims and the synthetic bridge it needs.
        .target(
            name: "ProductionTimeline",
            dependencies: [
                "TimelineSpikeCore",
                "MatrixRustSDKShim",
                .product(name: "Models", package: "MactrixLibrary"),
                .product(name: "UI", package: "MactrixLibrary"),
                .product(name: "Tokens", package: "MactrixLibrary"),
                .product(name: "Utils", package: "MactrixLibrary")
            ],
            // MATRIX-81: `import MatrixRustSDK` in this target loads the shim.
            swiftSettings: [.unsafeFlags(["-module-alias", "MatrixRustSDK=MatrixRustSDKShim"])]
        ),
        .executableTarget(
            name: "TimelineSpikeApp",
            dependencies: ["TimelineSpikeCore", "ProductionTimeline"]
        ),
        .testTarget(
            name: "TimelineSpikeCoreTests",
            dependencies: ["TimelineSpikeCore"]
        ),
        // The candidates live in the app target, so their pure logic — height arithmetic and
        // scroll-anchor maths — is tested from here.
        .testTarget(
            name: "TimelineSpikeAppTests",
            dependencies: ["TimelineSpikeApp"]
        )
    ]
)
