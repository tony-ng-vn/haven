// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "graph",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // Without an explicit product, Xcode's package graph resolution (App/project.yml's
        // local package dependency) cannot see GraphCore at all ("Missing package product
        // GraphCore"), even though `swift build`/`swift test` never needed one.
        .library(name: "GraphCore", targets: ["GraphCore"])
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
