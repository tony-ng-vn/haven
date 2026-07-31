// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "graph",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .target(
            name: "GraphCore",
            dependencies: []
        ),
        .executableTarget(
            name: "graph-cli",
            dependencies: ["GraphCore"]
        ),
        .testTarget(
            name: "GraphCoreTests",
            dependencies: ["GraphCore"]
        ),
    ]
)
