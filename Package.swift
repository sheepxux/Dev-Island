// swift-tools-version: 5.10
import Foundation
import PackageDescription

// `#Preview` macros require the PreviewsMacros plugin shipped with the full
// Xcode app. When only Command Line Tools are present, gate previews behind
// the PREVIEWS flag so `swift build` still succeeds. Xcode builds get them
// automatically.
let hasXcode = FileManager.default.fileExists(atPath: "/Applications/Xcode.app")

// C side: previews under Xcode, suppress preview-related warnings in debug.
let appSettings: [SwiftSetting] = {
    var s: [SwiftSetting] = [
        .unsafeFlags(["-suppress-warnings"], .when(configuration: .debug)),
    ]
    if hasXcode { s.append(.define("PREVIEWS")) }
    return s
}()

// S side: IslandCore opts into strict concurrency.
let coreSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "Island",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "IslandApp",     targets: ["IslandApp"]),
        .library(   name: "IslandAppLib",  targets: ["IslandAppLib"]),
        .library(   name: "IslandCore",    targets: ["IslandCore"]),
        .executable(name: "IslandCoreCLI", targets: ["IslandCoreCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git",        from: "0.15.0"),
    ],
    targets: [
        // ── C 侧：前端 App ────────────────────────────────────────────
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

        // ── S 侧：IslandCore 完整实现 ─────────────────────────────────
        // The cloudflared resource is a placeholder text file; the real
        // binary is not committed. Drop the actual binary at
        // `IslandCore/Sources/IslandCore/Resources/cloudflared` (chmod +x)
        // to enable webhook tunneling. Without it, TunnelManager catches
        // the launch failure and falls back to PollingFallback's 60s loop.
        // The resource declaration is still required so SPM generates
        // `Bundle.module`, which CloudflaredProcess uses to locate the
        // binary at runtime.
        .target(
            name: "IslandCore",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "SQLite",      package: "SQLite.swift"),
            ],
            path: "IslandCore/Sources/IslandCore",
            resources: [
                .copy("Resources/cloudflared"),
            ],
            swiftSettings: coreSettings
        ),

        // ── S 侧：CLI 集成测试工具 ────────────────────────────────────
        .executableTarget(
            name: "IslandCoreCLI",
            dependencies: ["IslandCore"],
            path: "IslandCoreCLI/Sources/IslandCoreCLI"
        ),

        // ── S 侧：单元测试 ────────────────────────────────────────────
        .testTarget(
            name: "IslandCoreTests",
            dependencies: ["IslandCore"],
            path: "IslandCoreTests/Sources/IslandCoreTests"
        ),
    ]
)
