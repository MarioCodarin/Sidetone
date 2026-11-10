import SwiftUI
import SidetoneCore

/// Nearby calendar meetings, each with a record button.
struct MeetingsSection: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            SectionHeader(title: "Meetings") {
                Button {
                    model.refreshMeetings()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .accessibilityLabel("Refresh meetings")
                }
                .buttonStyle(IconButtonStyle(size: 20))
                .help("Refresh meetings")
            }

            if model.meetings.isEmpty {
                Text(model.calendarPermission == .granted ? "No meetings nearby" : "Calendar access is off")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textMuted)
                    .padding(.horizontal, DS.Space.s + DS.Space.xs)
                    .padding(.vertical, DS.Space.s)
            } else {
                // Tick so the "in progress" highlight follows the clock while the panel stays open.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 0) {
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
