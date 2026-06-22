// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoreAIPlayground",
    platforms: [
        // Kept low so the catalog + hardware analyzer build on any modern
        // toolchain. Live Core AI inference is gated behind `@available` +
        // `#if canImport(CoreAI...)` and only lights up on macOS 27 / Xcode 27.
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "CoreAIPlayground",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "CoreAIPlaygroundTests",
            dependencies: ["CoreAIPlayground"]
        )
    ]
)
