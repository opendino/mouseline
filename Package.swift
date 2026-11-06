// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mgestures",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mgestures", targets: ["mgestures"]),
        .library(name: "MGesturesCore", targets: ["MGesturesCore"]),
    ],
    targets: [
        // Pure Swift: shape recognition + configuration model. No AppKit, fully unit-tested.
        .target(name: "MGesturesCore"),
        // The menu bar app: event tap, trail overlay, actions, settings UI.
        .executableTarget(
            name: "mgestures",
            dependencies: ["MGesturesCore"]
        ),
        .testTarget(
            name: "MGesturesCoreTests",
            dependencies: ["MGesturesCore"]
        ),
    ]
)
