import SwiftUI
import SidetoneCore

/// Recordings folder · Settings · Quit.
struct FooterView: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Button {
                model.openRecordingsFolder()
            } label: {
                Label("Recordings", systemImage: "folder")
            }
            .buttonStyle(QuietButtonStyle())
            .help("Open ~/Documents/Recordings in Finder")

            Spacer()

            Button {
                PreferencesWindowController.shared.show(model: model)
            } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel("Settings")
            }
            .buttonStyle(IconButtonStyle())
            .keyboardShortcut(",", modifiers: [.command])
            .help("Settings  ⌘,")

            Button {
                model.quit()
            } label: {
                Image(systemName: "power")
                    .accessibilityLabel("Quit Sidetone")
            }
            .buttonStyle(IconButtonStyle())
            .keyboardShortcut("q", modifiers: [.command])
            .help("Quit Sidetone  ⌘Q")
        }
    }
}
