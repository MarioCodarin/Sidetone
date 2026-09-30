import SwiftUI
import SidetoneCore

/// Recordings folder · Settings · Quit.
struct FooterView: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Button {
                model.openRecordingsFolder()
            } label: {
                Label("Recordings", systemImage: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open ~/Documents/Recordings in Finder")

            Spacer()

            Button {
                PreferencesWindowController.shared.show(model: model)
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: [.command])
            .help("Open Preferences")

            Button {
                model.quit()
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}
