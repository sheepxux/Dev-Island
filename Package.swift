// swift-tools-version: 5.9
import Foundation
import PackageDescription

// `#Preview` macros require the PreviewsMacros plugin shipped with the full
// Xcode app. When only Command Line Tools are present, gate previews behind
// the PREVIEWS flag so `swift build` still succeeds. Xcode builds get them
// automatically.
let hasXcode = FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
let appSettings: [SwiftSetting] = hasXcode ? [.define("PREVIEWS")] : []

let package = Package(
    name: "Island",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "IslandApp", targets: ["IslandApp"]),
        .library(name: "IslandCore", targets: ["IslandCore"]),
    ],
    targets: [
        .executableTarget(
            name: "IslandApp",
            dependencies: ["IslandCore"],
            path: "IslandApp",
            swiftSettings: appSettings
        ),
        .target(
            name: "IslandCore",
            path: "IslandCore/Sources/IslandCore",
            swiftSettings: appSettings
        ),
    ]
)
