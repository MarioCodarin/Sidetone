import SwiftUI
import SidetoneCore

/// One calendar meeting: title, time range, record button. Tinted while in progress.
struct MeetingRow: View {
    let meeting: Meeting
    let inProgress: Bool
    let canStart: Bool
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s) {
            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title)
                    .font(DS.Typo.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                subtitle
                    .font(DS.Typo.secondary)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: DS.Space.xs)

            Button(action: onRecord) {
                Image(systemName: inProgress ? "record.circle.fill" : "record.circle")
                    .accessibilityLabel("Record \(meeting.title)")
            }
            .buttonStyle(IconButtonStyle(hoverTint: DS.Palette.record, restTint: inProgress ? DS.Palette.record : nil))
            .disabled(!canStart)
            .help("Record this meeting")
        }
        .listRow(highlight: inProgress ? DS.Palette.record.opacity(0.08) : nil)
        .accessibilityElement(children: .contain)
    }

    private var subtitle: Text {
        let range = "\(meeting.start.formatted(.dateTime.hour().minute())) – \(meeting.end.formatted(.dateTime.hour().minute()))"
        guard inProgress else { return Text(range) }
        return Text("Now").fontWeight(.semibold).foregroundStyle(.primary)
            + Text(" · until \(meeting.end.formatted(.dateTime.hour().minute()))")
    }
}
