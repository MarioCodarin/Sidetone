import AppKit
import SidetoneCore
import SidetoneUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owned here so the SwiftUI `App` does not need `@State` (Command Line
    /// Tools lack the SwiftUIMacros plugin that expands that attribute).
    let model = AppEnvironment.makeModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu-bar agent must survive having zero windows. Without this, AppKit treats the
        // app as idle once setup/Settings closes and terminates it — the menu-bar item vanishes.
        ProcessInfo.processInfo.disableAutomaticTermination("Sidetone is a menu-bar app")
        ProcessInfo.processInfo.disableSuddenTermination()

        // Menu-bar-only agent app: no Dock icon, no app-switcher entry.
        NSApp.setActivationPolicy(.accessory)
        model.launch()

        // First run: permissions + where recordings live. Once, then never again.
        if !model.isSetupComplete {
            DispatchQueue.main.async { [model] in
                SetupWindowController.shared.show(model: model)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
