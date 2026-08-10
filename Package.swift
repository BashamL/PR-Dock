// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PRDock",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "PRDock", targets: ["PRDock"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing", "6.2.4" ..< "6.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "PRDock",
            path: "Sources/PRDock"
        ),
        .testTarget(
            name: "PRDockTests",
            dependencies: [
                "PRDock",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/PRDockTests"
        ),
    ]
)
