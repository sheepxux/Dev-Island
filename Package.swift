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
        .library(name: "IslandAppLib", targets: ["IslandAppLib"]),
        .library(name: "IslandCore", targets: ["IslandCore"]),
    ],
    targets: [
        // Tiny exec shim: @main + AppDelegate. All view code lives in
        // IslandAppLib so SwiftUI Previews work under Xcode 26 (executable
        // targets require ENABLE_DEBUG_DYLIB which SPM does not expose).
        .executableTarget(
            name: "IslandApp",
            dependencies: ["IslandAppLib", "IslandCore"],
            path: "IslandApp",
            swiftSettings: appSettings
        ),
        .target(
            name: "IslandAppLib",
            dependencies: ["IslandCore"],
            path: "IslandAppLib",
            swiftSettings: appSettings
        ),
        .target(
            name: "IslandCore",
            path: "IslandCore/Sources/IslandCore",
            swiftSettings: appSettings
        ),
    ]
)
