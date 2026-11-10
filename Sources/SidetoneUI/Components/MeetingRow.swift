import SwiftUI
import SidetoneCore

/// One calendar meeting: start time, title, and what it becomes if you record it.
struct MeetingRow: View {
    let meeting: Meeting
    let inProgress: Bool
    let canStart: Bool
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Text(meeting.start.formatted(.dateTime.hour().minute()))
                .font(DS.Typo.mono)
                .foregroundStyle(inProgress ? DS.Palette.textPrimary : DS.Palette.textMuted)
                .frame(width: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title)
                    .font(DS.Typo.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                subtitle
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }

            Spacer(minLength: DS.Space.xs)

            Button(action: onRecord) {
                Image(systemName: inProgress ? "record.circle.fill" : "record.circle")
                    .foregroundStyle(inProgress ? DS.Palette.record : DS.Palette.textSecondary)
                    .accessibilityLabel("Record \(meeting.title)")
            }
            .buttonStyle(IconButtonStyle(hoverTint: DS.Palette.record, restTint: inProgress ? DS.Palette.record : DS.Palette.textMuted))
            .disabled(!canStart)
            .help(canStart ? "Record this meeting" : "Stop the current recording first")
        }
        .listRow(highlight: inProgress ? DS.Palette.accent.opacity(0.10) : nil)
        .accessibilityElement(children: .contain)
    }

    private var subtitle: Text {
        let range = "\(meeting.start.formatted(.dateTime.hour().minute())) – \(meeting.end.formatted(.dateTime.hour().minute()))"
        guard inProgress else { return Text(range) }
        return Text("Now").fontWeight(.medium).foregroundStyle(DS.Palette.textPrimary)
            + Text(" · until \(meeting.end.formatted(.dateTime.hour().minute()))")
    }
}
