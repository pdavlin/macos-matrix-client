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
    targets: [
        .target(name: "TimelineSpikeCore"),
        .executableTarget(
            name: "TimelineSpikeApp",
            dependencies: ["TimelineSpikeCore"]
        ),
        .testTarget(
            name: "TimelineSpikeCoreTests",
            dependencies: ["TimelineSpikeCore"]
        )
    ]
)
