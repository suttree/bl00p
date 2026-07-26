// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "bl00p",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "bl00p", targets: ["Bl00p"])
    ],
    targets: [
        .executableTarget(
            name: "Bl00p",
            path: "Sources/Bl00p"
        ),
        .testTarget(
            name: "Bl00pTests",
            dependencies: ["Bl00p"],
            path: "Tests/Bl00pTests"
        )
    ]
)
