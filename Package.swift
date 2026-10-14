// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MemoryMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MemoryCore",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "MemoryMonitor",
            dependencies: ["MemoryCore"]
        ),
        .testTarget(
            name: "MemoryCoreTests",
            dependencies: ["MemoryCore"]
        ),
    ]
)
