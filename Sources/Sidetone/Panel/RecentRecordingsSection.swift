import SwiftUI
import SidetoneCore

/// The last few recordings on disk, with a shortcut to the full folder.
struct RecentRecordingsSection: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent recordings")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Show all") { model.openRecordingsFolder() }
                    .buttonStyle(.link)
                    .font(.caption)
            }

            VStack(spacing: 2) {
                ForEach(model.recentRecordings) { entry in
                    RecordingRow(entry: entry)
                }
            }
        }
    }
}
