import SwiftUI
import SidetoneCore

/// One past recording. Click the row to open the stereo mix, or to mix it if that never
/// finished. The ⋯ menu copies or reveals that same file.
struct RecordingRow: View {
    @Environment(SidetoneModel.self) private var model
    let entry: RecordingEntry

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 8) {
                    Image(systemName: entry.needsMix ? "exclamationmark.circle.fill" : "waveform.circle.fill")
                        .foregroundStyle(entry.needsMix ? Color.orange : Color.secondary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.displayTitle)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)
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
                Label("Actions for \(entry.displayTitle)", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Actions")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    /// Date, then either the length or "Not mixed".
    private var subtitle: String {
        let when = entry.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        if entry.needsMix { return "\(when) · Not mixed" }
        if let duration = entry.duration { return "\(when) · \(Formatting.elapsed(duration))" }
        return when
    }

    private func open() {
        if let audio = entry.audioURL {
            model.open(audio)
        } else {
            model.remix(entry)
        }
    }
}
