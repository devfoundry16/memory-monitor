// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fresh",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MemoryCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "Fresh",
            dependencies: ["MemoryCore"]
        ),
        .testTarget(
            name: "MemoryCoreTests",
            dependencies: ["MemoryCore"]
        ),
    ]
)
