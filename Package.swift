// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Sidetone",
    platforms: [
        // macOS 15+: the Synchronization module's `Atomic` (used by the
        // realtime-safe ring buffer in the system-audio tap) requires it.
        .macOS("15")
    ],
    products: [
        .executable(name: "Sidetone", targets: ["Sidetone"]),
        .executable(name: "SidetoneCheck", targets: ["SidetoneCheck"])
    ],
    targets: [
        .target(
            name: "SidetoneCore",
            path: "Sources/SidetoneCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "Sidetone",
            dependencies: ["SidetoneCore"],
            path: "Sources/Sidetone",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        // Command Line Tools ship neither XCTest nor TestingMacros, so checks
        // run as a plain executable: `swift run SidetoneCheck`.
        .executableTarget(
            name: "SidetoneCheck",
            dependencies: ["SidetoneCore"],
            path: "Tests/SidetoneCheck",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
