import AppKit
import SwiftUI
import SidetoneCore

/// Owns the dedicated **Preferences window** for this menu-bar (`.accessory`) app.
///
/// We manage the window directly with AppKit instead of using SwiftUI's `Settings`
/// scene. Opening a `Settings` window reliably from an LSUIElement / `.accessory`
/// app is a long-standing pain point — it tends to open *behind* other apps or
/// never takes key focus. A hand-rolled `NSWindow` hosting the SwiftUI
/// `PreferencesView`, brought front with `makeKeyAndOrderFront` right after
/// `NSApp.activate`, is the dependable pattern and needs no policy juggling.
@MainActor
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    static let shared = PreferencesWindowController()

    private var window: NSWindow?

    private override init() { super.init() }

    /// Bring the Preferences window to the front, creating it if necessary.
    func show(model: SidetoneModel) {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: PreferencesView().environment(model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Sidetone Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
