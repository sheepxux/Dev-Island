// swift-tools-version: 5.9
import PackageDescription

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
            path: "IslandApp"
        ),
        .target(
            name: "IslandCore",
            path: "IslandCore/Sources/IslandCore"
        ),
    ]
)
