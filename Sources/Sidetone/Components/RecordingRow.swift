import SwiftUI
import SidetoneCore

/// One past recording. Drag the row to pull the audio file out; double-click to open it;
/// the ⋯ menu has copy / reveal / re-mix.
struct RecordingRow: View {
    @Environment(SidetoneModel.self) private var model
    let entry: RecordingEntry

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: entry.needsMix ? "exclamationmark.circle.fill" : "waveform.circle.fill")
                    .foregroundStyle(entry.needsMix ? Color.orange : Color.secondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.displayTitle)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(entry.date, format: .dateTime.month(.abbreviated).day().hour().minute()) · \(entry.needsMix ? "Not mixed" : "Audio")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .onDrag { dragProvider }
            .onTapGesture(count: 2) { open() }
            .help(entry.audioURL == nil ? "Not mixed yet — use ⋯ → Mix now" : "Double-click to open · drag the audio out")

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
                Button { model.reveal(entry.folderURL) } label: {
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

    private var dragProvider: NSItemProvider {
        entry.audioURL.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
    }

    private func open() {
        model.open(entry.audioURL ?? entry.folderURL)
    }
}
