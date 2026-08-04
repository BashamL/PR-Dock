// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PRDock",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "PRDock", targets: ["PRDock"]),
    ],
    targets: [
        .executableTarget(
            name: "PRDock",
            path: "Sources/PRDock"
        ),
    ]
)
