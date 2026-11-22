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
        // Runs the same assertions as LibertyCoreTests without XCTest, which
        // Command Line Tools does not ship. CI still runs `swift test`; this is
        // so work can be verified on a machine with no Xcode.
        .executableTarget(name: "liberty-check", dependencies: ["LibertyCore"]),
    ]
)
