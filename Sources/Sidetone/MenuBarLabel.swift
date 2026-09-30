import SwiftUI
import SidetoneCore

/// The menu-bar glyph. A separate view so Observation tracks `model.state`.
struct MenuBarLabel: View {
    var model: SidetoneModel

    var body: some View {
        Image(systemName: model.state.symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(model.state == .idle ? Color.primary : model.state.tint)
            .accessibilityLabel("Sidetone, \(model.state.label)")
    }
}
