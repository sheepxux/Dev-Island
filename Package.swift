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
            // Info.plist and AppIcon.icns live under IslandApp/Resources/
            // because that's the conventional bundle layout build-app.sh
            // copies into Island.app/Contents/. They are NOT swift-side
            // resources (the SPM binary is wrapped by build-app.sh, not
            // shipped as an SPM bundle), so excluding them silences the
            // "unhandled files" warning and prevents SPM from copying
            // them into the bare executable's resource path.
            exclude: [
                "Resources/Info.plist",
                "Resources/AppIcon.icns",
            ],
            swiftSettings: appSettings
        ),
        .target(
            name: "IslandAppLib",
            dependencies: ["IslandCore"],
            path: "IslandAppLib",
            swiftSettings: appSettings
        ),

        // ── S 侧：IslandCore 完整实现 ─────────────────────────────────
        // cloudflared is no longer a bundled resource. CloudflaredProcess
        // resolves the binary at runtime in this order: bundled (kept as
        // an opt-in path for future use, currently absent), Homebrew
        // standard locations (/opt/homebrew/bin, /usr/local/bin), then
        // `$PATH`. The Cask formula declares
        // `depends_on cask: "cloudflared"` so brew users get the binary
        // at install time. If the binary is missing entirely (manual
        // build, offline machine, etc.), TunnelManager catches the
        // launch failure and PollingFallback's 60s loop takes over.
        .target(
            name: "IslandCore",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "SQLite",      package: "SQLite.swift"),
            ],
            path: "IslandCore/Sources/IslandCore",
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
