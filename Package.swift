// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v27)],
    targets: [
        .target(name: "UsageCore", resources: [.copy("Resources/prices.json")]),
        .executableTarget(name: "ClaudeUsageBar", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ]
)
