// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "agentmon",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "agentmonCore", targets: ["agentmonCore"]),
        .executable(name: "agentmon", targets: ["agentmon"]),
        .executable(name: "agentmon-hook", targets: ["agentmonHook"]),
    ],
    targets: [
        .target(
            name: "agentmonCore",
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "agentmon",
            dependencies: ["agentmonCore"],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "agentmonHook",
            dependencies: ["agentmonCore"],
            path: "Sources/Hook"
        ),
        .testTarget(
            name: "agentmonCoreTests",
            dependencies: ["agentmonCore"],
            path: "tests",
            exclude: ["README.md", "e2e"],
            sources: ["unit", "integration"]
        ),
    ]
)
