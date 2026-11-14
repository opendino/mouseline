// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MouseLine",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MouseLine", targets: ["MouseLine"]),
        .library(name: "MouseLineCore", targets: ["MouseLineCore"]),
    ],
    targets: [
        // Pure Swift: shape recognition + configuration model. No AppKit, fully unit-tested.
        .target(name: "MouseLineCore"),
        // The menu bar app: event tap, trail overlay, actions, settings UI.
        .executableTarget(
            name: "MouseLine",
            dependencies: ["MouseLineCore"]
        ),
        .testTarget(
            name: "MouseLineCoreTests",
            dependencies: ["MouseLineCore"]
        ),
    ]
)
