// swift-tools-version: 6.1
import PackageDescription

// Standalone spike package. It is deliberately NOT part of Mactrix.xcodeproj and it
// has no dependency on matrix-rust-sdk. See spike/SCENARIOS.md for the measurement
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
        // S-39: the shipping row layer (Models, UI, Tokens, Utils). Still no
        // matrix-rust-sdk — MactrixLibrary does not depend on it.
        .package(path: "../../MactrixLibrary")
    ],
    targets: [
        .target(name: "TimelineSpikeCore"),
        // S-39: named `MatrixRustSDK` on purpose, so the production container's
        // own `import MatrixRustSDK` resolves here and those files compile
        // inside this package unedited. See the target's README.
        .target(name: "MatrixRustSDK", dependencies: [
            .product(name: "Models", package: "MactrixLibrary")
        ], path: "Sources/MatrixRustSDKShim", exclude: ["README.md"]),
        // S-39: the real M1 container, compiled from symlinks to the app's
        // files, plus the shims and the synthetic bridge it needs.
        .target(
            name: "ProductionTimeline",
            dependencies: [
                "TimelineSpikeCore",
                "MatrixRustSDK",
                .product(name: "Models", package: "MactrixLibrary"),
                .product(name: "UI", package: "MactrixLibrary"),
                .product(name: "Tokens", package: "MactrixLibrary"),
                .product(name: "Utils", package: "MactrixLibrary")
            ]
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
