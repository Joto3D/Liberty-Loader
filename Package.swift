// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LibertyLoader",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LibertyLoader", targets: ["LibertyLoader"]),
        .library(name: "LibertyCore", targets: ["LibertyCore"]),
    ],
    targets: [
        // Platform-independent logic: bottle discovery, mods, config files, backups.
        .target(name: "LibertyCore"),
        // SwiftUI macOS app.
        .executableTarget(name: "LibertyLoader", dependencies: ["LibertyCore"]),
        .testTarget(name: "LibertyCoreTests", dependencies: ["LibertyCore"]),
    ]
)
