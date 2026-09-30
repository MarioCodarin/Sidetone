import SwiftUI
import SidetoneCore

/// Nearby calendar meetings, each with a record button.
struct MeetingsSection: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Meetings")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    model.refreshMeetings()
                } label: {
                    Label("Refresh meetings", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Refresh meetings")
            }

            if model.meetings.isEmpty {
                Text("No meetings nearby.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            } else {
                // Tick so the "in progress" highlight follows the clock while the panel stays open.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 4) {
                        ForEach(model.meetings) { meeting in
                            MeetingRow(
                                meeting: meeting,
                                inProgress: meeting.isInProgress(context.date),
                                canStart: model.state == .idle,
                                onRecord: { model.startRecording(meeting: meeting) }
                            )
                        }
                    }
                }
            }
        }
    }
}
