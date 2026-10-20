import SwiftUI
import SidetoneCore

/// The last few recordings on disk, with a shortcut to the full folder.
struct RecentRecordingsSection: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            SectionHeader(title: "Recent") {
                Button("Show all") { model.openRecordingsFolder() }
                    .buttonStyle(QuietButtonStyle())
                    .padding(.trailing, -DS.Space.s)
            }

            VStack(spacing: 0) {
                ForEach(model.recentRecordings) { entry in
                    RecordingRow(entry: entry)
                }
            }
        }
    }
}
