import AppKit
import SidetoneCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here so the SwiftUI `App` does not need `@State` (Command Line
    /// Tools lack the SwiftUIMacros plugin that expands that attribute).
    let model = SidetoneModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only agent app: no Dock icon, no app-switcher entry.
        NSApp.setActivationPolicy(.accessory)
        model.onAppear()
    }
}
