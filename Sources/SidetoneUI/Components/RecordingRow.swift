import SwiftUI
import SidetoneCore

/// One past recording. Click the row to open the stereo mix, or to mix it if that never
/// finished. The ⋯ menu copies or reveals that same file.
struct RecordingRow: View {
    @Environment(SidetoneModel.self) private var model
    let entry: RecordingEntry

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Button(action: open) {
                HStack(spacing: DS.Space.s) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.displayTitle)
                            .font(DS.Typo.body)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        subtitle
                            .font(DS.Typo.secondary)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: DS.Space.xs)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(entry.audioURL == nil ? "Not mixed yet — click to mix" : "Open the stereo mix")

            Menu {
                if let audio = entry.audioURL {
                    Button { model.open(audio) } label: {
                        Label("Open", systemImage: "play.circle")
                    }
                    Button { model.copyFileToPasteboard(audio) } label: {
                        Label("Copy audio file", systemImage: "waveform")
                    }
                } else {
                    Button { model.remix(entry) } label: {
                        Label("Mix now", systemImage: "wand.and.stars")
                    }
                }
                Divider()
                Button { model.reveal(entry.audioURL ?? entry.folderURL) } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .accessibilityLabel("Actions for \(entry.displayTitle)")
            }
            .menuStyle(.button)
            .buttonStyle(IconButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Actions")
        }
        .listRow()
    }

    /// "Today, 09:30 · 47:12", or a flagged "Not mixed" instead of the length.
    private var subtitle: Text {
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(entry.date) {
            day = "Today"
        } else if calendar.isDateInYesterday(entry.date) {
            day = "Yesterday"
        } else {
            day = entry.date.formatted(.dateTime.day().month(.abbreviated))
        }
        let when = "\(day), \(time)"
        if entry.needsMix {
            return Text("\(when) · ") + Text(Image(systemName: "exclamationmark.circle.fill")).foregroundStyle(DS.Palette.attention)
                + Text(" Not mixed")
        }
        if let duration = entry.duration { return Text("\(when) · \(Formatting.elapsed(duration))") }
        return Text(when)
    }

    private func open() {
        if let audio = entry.audioURL {
            model.open(audio)
        } else {
            model.remix(entry)
        }
    }
}
