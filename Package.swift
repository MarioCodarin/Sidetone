// swift-tools-version:6.0
import PackageDescription

// Module graph (arrows point at dependencies):
//
//   Sidetone (app) ──► SidetoneServices ──► SidetoneCore
//        │                                      ▲
//        └──────────► SidetoneAudio ────────────┘
//
// SidetoneCore imports only Foundation/Observation, so its state machine is testable with
// fakes. Everything that touches hardware or a system framework lives in Audio or Services.

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Sidetone",
    platforms: [
        // macOS 15+: the Synchronization module's `Atomic` (used by the
        // realtime-safe ring buffer and the file writer) requires it.
        .macOS("15")
    ],
    products: [
        .executable(name: "Sidetone", targets: ["Sidetone"]),
        .executable(name: "SidetoneCheck", targets: ["SidetoneCheck"])
    ],
    targets: [
        // Domain types, ports (protocols) and the `SidetoneModel` state machine.
        .target(name: "SidetoneCore", path: "Sources/SidetoneCore", swiftSettings: swift5),

        // Realtime capture (system tap, mic), lock-free ring, file writer, streaming stereo mixer.
        .target(
            name: "SidetoneAudio",
            dependencies: ["SidetoneCore"],
            path: "Sources/SidetoneAudio",
            swiftSettings: swift5
        ),

        // Adapters for macOS services: EventKit, UserNotifications, permissions, AppKit actions.
        .target(
            name: "SidetoneServices",
            dependencies: ["SidetoneCore"],
            path: "Sources/SidetoneServices",
            swiftSettings: swift5
        ),

        // The menu-bar app: composition root + SwiftUI views.
        .executableTarget(
            name: "Sidetone",
            dependencies: ["SidetoneCore", "SidetoneAudio", "SidetoneServices"],
            path: "Sources/Sidetone",
            swiftSettings: swift5
        ),

        // Command Line Tools ship neither XCTest nor TestingMacros, so checks
        // run as a plain executable: `swift run SidetoneCheck`.
        .executableTarget(
            name: "SidetoneCheck",
            dependencies: ["SidetoneCore", "SidetoneAudio"],
            path: "Tests/SidetoneCheck",
            swiftSettings: swift5
        )
    ]
)
