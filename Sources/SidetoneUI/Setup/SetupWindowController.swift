import AppKit
import SwiftUI
import SidetoneCore

/// Owns the first-run setup window.
///
/// Same pattern as `PreferencesWindowController`: a hand-rolled `NSWindow` hosting the SwiftUI
/// view, because a `Settings`/`Window` scene is unreliable from an `.accessory` menu-bar app.
/// Closing the window counts as finishing (it never nags on the next launch).
@MainActor
public final class SetupWindowController: NSObject, NSWindowDelegate {
    public static let shared = SetupWindowController()
    public static let windowTitle = "Sidetone Setup"

    private var window: NSWindow?
    private weak var model: SidetoneModel?

    private override init() { super.init() }

    /// Bring setup to the front, creating it if necessary, and refresh what it shows.
    public func show(model: SidetoneModel) {
        self.model = model
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SetupView().environment(model))
        hosting.view.layoutSubtreeIfNeeded()
        let size = hosting.view.fittingSize

        let window = SetupWindow(contentViewController: hosting)
        window.title = Self.windowTitle
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(size)
        window.center()
        // A menu-bar app may be launched while another app owns a full-screen Space; bring
        // setup to whatever Space is active instead of leaving it behind.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        self.window = window
        window.makeKeyAndOrderFront(nil)
        Log.app.notice("setup window shown")
    }

    public func close() {
        window?.close()
    }

    public func windowWillClose(_ notification: Notification) {
        Log.app.notice("setup window closed")
        window = nil
    }

    /// Called for a user close (red button, ⌘W, Esc) — not for app termination. Closing without
    /// pressing a button is still a decision, so setup does not open again next launch.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        model?.completeSetup()
        return true
    }
}

/// An accessory app has no main menu, so ⌘W and Esc would do nothing.
private final class SetupWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }
}
