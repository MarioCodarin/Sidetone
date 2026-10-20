import SwiftUI
import SidetoneCore

/// The menu-bar glyph. A separate view so Observation tracks `model.state`.
public struct MenuBarLabel: View {
    var model: SidetoneModel

    public init(model: SidetoneModel) { self.model = model }

    public var body: some View {
        Image(systemName: model.state.symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(model.state == .idle ? Color.primary : model.state.tint)
            .accessibilityLabel("Sidetone, \(model.state.label)")
    }
}
