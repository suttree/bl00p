// swift-tools-version: 6.0

import PackageDescription

// bl00p-linux keeps the upstream macOS build working while making Linux the
// primary target. Package.swift is ordinary Swift evaluated on the host, so
// each platform gets only the dependencies it can actually resolve: Sparkle
// is macOS-only, and the GTK4 backend only exists on Linux.

#if os(macOS)

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
            // main.swift is the Linux entry point; top-level code cannot
            // coexist with the @main attribute used on macOS.
            exclude: ["main.swift"],
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

#else

let package = Package(
    name: "bl00p",
    products: [
        .executable(name: "bl00p", targets: ["Bl00p"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/codelynx/SwiftOpenUI",
            branch: "develop"
        )
    ],
    targets: [
        .executableTarget(
            name: "Bl00p",
            dependencies: [
                .product(name: "SwiftOpenUI", package: "SwiftOpenUI"),
                .product(name: "BackendGTK4", package: "SwiftOpenUI")
            ],
            path: "Sources/Bl00p",
            // The macOS entry point carries @main, which conflicts with the
            // top-level code in main.swift.
            exclude: ["Platform/MacEntry.swift"]
        ),
        .testTarget(
            name: "Bl00pTests",
            dependencies: ["Bl00p"],
            path: "Tests/Bl00pTests"
        )
    ]
)

#endif
