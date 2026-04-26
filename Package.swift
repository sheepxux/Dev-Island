// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Island",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "IslandApp",    targets: ["IslandApp"]),
        .library(   name: "IslandAppLib", targets: ["IslandAppLib"]),
        .library(   name: "IslandCore",   targets: ["IslandCore"]),
        .executable(name: "IslandCoreCLI", targets: ["IslandCoreCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git",        from: "0.15.0"),
    ],
    targets: [
        // ── C 侧：前端 App（不动）──────────────────────────────────────
        .executableTarget(
            name: "IslandApp",
            dependencies: ["IslandAppLib", "IslandCore"],
            swiftSettings: appSettings
        ),
        .target(
            name: "IslandAppLib",
            dependencies: ["IslandCore"],
            swiftSettings: appSettings
        ),

        // ── S 侧：IslandCore 完整实现 ─────────────────────────────────
        .target(
            name: "IslandCore",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "SQLite",       package: "SQLite.swift"),
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

// C 侧：debug 下抑制警告（preview 需要）
let appSettings: [SwiftSetting] = [
    .unsafeFlags(["-suppress-warnings"], .when(configuration: .debug)),
]

// S 侧：IslandCore 开启严格并发检查
let coreSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]
