import AppKit
import SidetoneCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here so the SwiftUI `App` does not need `@State` (Command Line
    /// Tools lack the SwiftUIMacros plugin that expands that attribute).
    let model = AppEnvironment.makeModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only agent app: no Dock icon, no app-switcher entry.
        NSApp.setActivationPolicy(.accessory)
        model.launch()
    }

    /// Quitting mid-recording (or mid-mix) must not lose the recording: save it and let the
    /// mix finish before the process exits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.hasWorkInFlight else { return .terminateNow }
        Task { @MainActor in
            await model.finishAllWork()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
