import SwiftUI
import SidetoneCore

@main
struct SidetoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            SidetonePanel()
                .environment(appDelegate.model)
        } label: {
            SidetoneMenuLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Separate view so Observation tracks `model.state` and the menu-bar glyph updates.
private struct SidetoneMenuLabel: View {
    var model: SidetoneModel

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
    }

    /// Split-circle at rest (L/R brand). Record / pause glyphs while capturing.
    private var symbol: String {
        switch model.state {
        case .idle:      return "circle.lefthalf.filled"
        case .recording: return "record.circle.fill"
        case .paused:    return "pause.circle.fill"
        }
    }

    private var tint: Color {
        switch model.state {
        case .idle:      return .primary
        case .recording: return .red
        case .paused:    return .orange
        }
    }
}
