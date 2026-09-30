import SwiftUI
import SidetoneCore

/// The two channel meters, visible only while capturing.
struct MetersView: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LevelMeter(label: "Them", caption: "desktop · L", level: model.desktopLevel, tint: .green)
            LevelMeter(label: "You", caption: "mic · R", level: model.micLevel, tint: .blue)
        }
    }
}
