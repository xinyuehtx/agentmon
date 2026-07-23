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
            path: "Sources/App",
            exclude: ["Resources"]  // AppIcon.icns 由 package.sh / xcodegen 直接打包，不参与 SPM 编译
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
