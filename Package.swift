// swift-tools-version:6.2
import PackageDescription

// Module graph (arrows point at dependencies):
//
//   Sidetone (app) ──► SidetoneServices ──► SidetoneCore
//        │  │                                   ▲
//        │  └──────► SidetoneAudio ─────────────┤
//        └─────────► SidetoneUI ────────────────┘
//
// SidetoneCore imports only Foundation/Observation, so its state machine is testable with
// fakes. Everything that touches hardware or a system framework lives in Audio or Services.

// Swift 5 language mode: the realtime/CoreAudio code passes raw pointers across callbacks,
// which Swift 6's strict checking models poorly, and the app has no concurrency bugs to chase.
// Tools version 6.2 still gives the newer manifest features and diagnostics.
let languageMode: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Sidetone",
    platforms: [
        // macOS 15+: the Synchronization module's `Atomic` (used by the
        // realtime-safe ring buffer and the file writer) requires it.
        .macOS("15")
    ],
    products: [
        .executable(name: "Sidetone", targets: ["Sidetone"]),
        .executable(name: "SidetoneCheck", targets: ["SidetoneCheck"]),
        .executable(name: "SidetonePreview", targets: ["SidetonePreview"])
    ],
    targets: [
        // Domain types, ports (protocols) and the `SidetoneModel` state machine.
        .target(name: "SidetoneCore", path: "Sources/SidetoneCore", swiftSettings: languageMode),

        // Realtime capture (system tap, mic), lock-free ring, file writer, streaming stereo mixer.
        .target(
            name: "SidetoneAudio",
            dependencies: ["SidetoneCore"],
            path: "Sources/SidetoneAudio",
            swiftSettings: languageMode
        ),

        // Adapters for macOS services: EventKit, UserNotifications, permissions, AppKit actions.
        .target(
            name: "SidetoneServices",
            dependencies: ["SidetoneCore"],
            path: "Sources/SidetoneServices",
            swiftSettings: languageMode
        ),

        // The SwiftUI views (panel, settings, design tokens). Depends only on Core, so a
        // preview harness can host them with fake dependencies.
        .target(
            name: "SidetoneUI",
            dependencies: ["SidetoneCore"],
            path: "Sources/SidetoneUI",
            swiftSettings: languageMode
        ),

        // The menu-bar app: composition root.
        .executableTarget(
            name: "Sidetone",
            dependencies: ["SidetoneCore", "SidetoneAudio", "SidetoneServices", "SidetoneUI"],
            path: "Sources/Sidetone",
            swiftSettings: languageMode
        ),

        // Command Line Tools ship neither XCTest nor TestingMacros, so checks
        // run as a plain executable: `swift run SidetoneCheck`.
        .executableTarget(
            name: "SidetoneCheck",
            dependencies: ["SidetoneCore", "SidetoneAudio"],
            path: "Tests/SidetoneCheck",
            swiftSettings: languageMode
        ),

        // Dev tool: hosts the real views with fixture data and screenshots them in light and
        // dark (`swift run SidetonePreview <out-dir>`). Not part of the shipped app.
        .executableTarget(
            name: "SidetonePreview",
            dependencies: ["SidetoneCore", "SidetoneUI"],
            path: "Tests/SidetonePreview",
            swiftSettings: languageMode
        )
    ]
)
