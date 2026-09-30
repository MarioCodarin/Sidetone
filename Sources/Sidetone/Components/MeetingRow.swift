import SwiftUI
import SidetoneCore

/// One calendar meeting: title, time range, record button. Red dot + tint while in progress.
struct MeetingRow: View {
    let meeting: Meeting
    let inProgress: Bool
    let canStart: Bool
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(inProgress ? Color.red : Color.clear)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(meeting.start, format: .dateTime.hour().minute()) – \(meeting.end, format: .dateTime.hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(action: onRecord) {
                Label("Record \(meeting.title)", systemImage: "record.circle")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(canStart ? Color.red : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!canStart)
            .help("Record this meeting")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(inProgress ? Color.red.opacity(0.10) : Color.clear)
        )
    }
}
