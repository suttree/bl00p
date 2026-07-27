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
        // Points at a fork branch carrying an unmerged fix for a Linux-only
        // GTK4Backend build failure: G_APPLICATION_DEFAULT_FLAGS /
        // G_APPLICATION_FLAGS_NONE aren't imported from GApplicationFlags by
        // Swift's ClangImporter on Linux. See
        // https://github.com/FesterCluck/SwiftOpenUI/tree/fix/gtk4-application-flags-linux-import
        // Revert to the upstream URL once codelynx/SwiftOpenUI merges an
        // equivalent fix.
        .package(
            url: "https://github.com/FesterCluck/SwiftOpenUI",
            branch: "fix/gtk4-application-flags-linux-import"
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
            exclude: ["Platform/MacEntry.swift"],
            // SwiftOpenUI itself declares swift-tools-version 5.10 (Swift 5
            // language mode) and its `App`/`View` protocols are not
            // @MainActor-isolated the way real SwiftUI's are, so a consumer
            // in Swift 6 strict-concurrency mode would need @MainActor and
            // isolated-conformance annotations on every view type that
            // touches the @MainActor AppModel. Matching SwiftOpenUI's own
            // language mode here avoids that framework-wide gap; the tools
            // version stays 6.0 package-wide so SwiftOpenUI itself still
            // resolves correctly.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "Bl00pTests",
            dependencies: ["Bl00p"],
            path: "Tests/Bl00pTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

#endif
