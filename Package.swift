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
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.4"
        )
    ],
    targets: [
        .executableTarget(
            name: "Bl00p",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Bl00p",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "@executable_path/../Frameworks"
                ])
            ]
        ),
        .testTarget(
            name: "Bl00pTests",
            dependencies: ["Bl00p"],
            path: "Tests/Bl00pTests"
        )
    ]
)
