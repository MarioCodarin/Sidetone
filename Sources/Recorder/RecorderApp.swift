import SwiftUI

@main
struct RecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            RecorderPanel()
                .environment(appDelegate.model)
        } label: {
            RecorderMenuLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)

        // The dedicated Preferences window is an AppKit-managed NSWindow rather than
        // a SwiftUI `Settings` scene — see PreferencesWindowController for why that's
        // more reliable from a menu-bar–only (.accessory) app. It's opened from the
        // panel's "Settings…" button / ⌘,.
    }
}

/// Separate view so Observation tracks `model.state` and the menu-bar glyph updates.
private struct RecorderMenuLabel: View {
    var model: RecorderModel

    var body: some View {
        Image(systemName: symbol)
    }

    /// Menu-bar glyph: a microphone at rest, the record dot while recording,
    /// the pause glyph while paused.
    private var symbol: String {
        switch model.state {
        case .idle:      return "mic.fill"
        case .recording: return "record.circle.fill"
        case .paused:    return "pause.circle.fill"
        }
    }
}
