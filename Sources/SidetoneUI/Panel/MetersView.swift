import SwiftUI
import SidetoneCore

/// The two channel meters, visible only while capturing.
struct MetersView: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            LevelMeter(label: "Them", source: "system audio", level: model.desktopLevel)
            if model.sessionUsesMic {
                LevelMeter(label: "You", source: "microphone", level: model.micLevel)
            }
        }
        .padding(.horizontal, DS.Space.s)
    }
}
