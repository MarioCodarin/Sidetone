import SwiftUI
import AppKit
import SidetoneCore

/// The full menu-bar panel UI for Sidetone.
///
/// Layout (top -> bottom):
///   1. Header — state badge + elapsed (mm:ss) + status line
///   2. Primary controls — Record (idle) OR Pause/Resume + Save + Trash (recording/paused)
///   3. Two level meters — Them (desktop L) + You (mic R), only while capturing
///   4. Meetings list — title + time range, with a per-row record button
///   5. Footer — Recordings folder + Settings… + Quit
///
/// Preferences (silence auto-stop) live in a dedicated Preferences window —
/// see `PreferencesView` / `PreferencesWindowController` — opened from the
/// footer's "Settings…" button or ⌘,.
///
/// Pure SwiftUI, compiles under Swift 5 language mode. Reads the shared @Observable model
/// from the environment and never mutates audio objects directly — it only calls the
/// model's intent methods (startRecording / togglePause / saveAndStop / trashAndStop / quit).
struct SidetonePanel: View {
    @Environment(SidetoneModel.self) private var model

    private let panelWidth: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            controls

            if model.state != .idle {
                Divider()
                meters
            }

            Divider()

            meetingsSection

            if !model.recentRecordings.isEmpty {
                Divider()
                recentSection
            }

            Divider()

            footer
        }
        .padding(12)
        .frame(width: panelWidth)
        // Suppress the auto-drawn focus ring on the first control when the
        // menu-bar window opens. (All text entry lives in the Preferences window.)
        .focusEffectDisabled()
    }

    // MARK: - 1. Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: stateSymbolName)
                .foregroundStyle(stateColor)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text(stateLabel)
                    .font(.headline)

                if let status = model.statusMessage, !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if model.state != .idle {
                Text(formattedElapsed(model.elapsed))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(model.state == .paused ? .secondary : .primary)
                    .monospacedDigit()
            }
        }
    }

    private var stateLabel: String {
        switch model.state {
        case .idle:      return "Ready"
        case .recording: return "Recording"
        case .paused:    return "Paused"
        }
    }

    private var stateSymbolName: String {
        switch model.state {
        case .idle:      return "circle.lefthalf.filled"
        case .recording: return "record.circle.fill"
        case .paused:    return "pause.circle.fill"
        }
    }

    private var stateColor: Color {
        switch model.state {
        case .idle:      return .secondary
        case .recording: return .red
        case .paused:    return .orange
        }
    }

    // MARK: - 2. Primary controls

    @ViewBuilder
    private var controls: some View {
        switch model.state {
        case .idle:
            if let current = model.currentMeeting {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button {
                            model.startRecording(meeting: current)
                        } label: {
                            Label("Record Meeting", systemImage: "record.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .keyboardShortcut("r", modifiers: [.command])

                        Button {
                            model.startRecording(meeting: nil)
                        } label: {
                            Image(systemName: "record.circle")
                                .frame(width: 22)
                        }
                        .controlSize(.large)
                        .buttonStyle(.bordered)
                        .help("Record without attaching to a meeting")
                    }
                    Text("Tags this recording as “\(current.title)”.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                Button {
                    model.startRecording(meeting: nil)
                } label: {
                    Label("Record", systemImage: "record.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut("r", modifiers: [.command])
            }

        case .recording, .paused:
            HStack(spacing: 8) {
                Button {
                    model.togglePause()
                } label: {
                    Label(
                        model.state == .paused ? "Resume" : "Pause",
                        systemImage: model.state == .paused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .tint(.orange)

                Button {
                    model.saveAndStop()
                } label: {
                    Label("Save", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button(role: .destructive) {
                    model.trashAndStop()
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .tint(.red)
                .help("Discard this recording")
            }
        }
    }

    // MARK: - 3. Level meters (visible only while capturing)

    private var meters: some View {
        VStack(alignment: .leading, spacing: 8) {
            LevelMeter(label: "Them", caption: "desktop · L", level: model.desktopLevel, tint: .green)
            LevelMeter(label: "You", caption: "mic · R", level: model.micLevel, tint: .blue)
        }
    }

    // MARK: - 4. Meetings

    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Meetings")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    model.refreshMeetings()
                } label: {
                    Image(systemName: "arrow.clockwise")
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
                VStack(spacing: 4) {
                    ForEach(model.meetings) { meeting in
                        MeetingRow(
                            meeting: meeting,
                            inProgress: meeting.isInProgress(Date()),
                            canStart: model.state == .idle,
                            onRecord: { model.startRecording(meeting: meeting) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - 4b. Recent recordings

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent recordings")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 2) {
                ForEach(model.recentRecordings) { entry in
                    recentRow(entry)
                }
            }
        }
    }

    @ViewBuilder
    private func recentRow(_ entry: RecordingEntry) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.displayTitle)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(recentSubtitle(entry))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .onDrag { recentDragProvider(entry) }
            .help("Drag the audio out, or use ⋯ for more")

            Menu {
                if let audio = entry.audioURL {
                    Button { model.copyFileToPasteboard(audio) } label: {
                        Label("Copy audio file", systemImage: "waveform")
                    }
                }
                Divider()
                Button { model.reveal(entry.folderURL) } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
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

    private func recentDragProvider(_ entry: RecordingEntry) -> NSItemProvider {
        if let audio = entry.audioURL {
            return NSItemProvider(contentsOf: audio) ?? NSItemProvider()
        }
        return NSItemProvider()
    }

    private func recentSubtitle(_ entry: RecordingEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let when = formatter.string(from: entry.date)
        let status = entry.audioURL != nil ? "Audio" : "Raw only"
        return "\(when) · \(status)"
    }

    // MARK: - 6. Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                model.openRecordingsFolder()
            } label: {
                Label("Recordings", systemImage: "folder")
            }
            .buttonStyle(.borderless)
            .help("Open ~/Documents/Recordings in Finder")

            Spacer()

            Button {
                openPreferences()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: [.command])
            .help("Open Preferences")

            Button {
                model.quit()
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q", modifiers: [.command])
        }
    }

    private func openPreferences() {
        PreferencesWindowController.shared.show(model: model)
    }

    /// mm:ss (or h:mm:ss past an hour) for the elapsed timer.
    private func formattedElapsed(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - LevelMeter

private struct LevelMeter: View {
    let label: String
    let caption: String
    let level: Float
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption2.weight(.medium))
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            GeometryReader { geo in
                let clamped = CGFloat(max(0, min(1, level)))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(2, geo.size.width * clamped))
                        .animation(.linear(duration: 0.08), value: clamped)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - MeetingRow

private struct MeetingRow: View {
    let meeting: Meeting
    let inProgress: Bool
    let canStart: Bool
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(inProgress ? Color.red : Color.clear)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(timeRange(meeting.start, meeting.end))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button {
                onRecord()
            } label: {
                Image(systemName: "record.circle")
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

    private func timeRange(_ start: Date, _ end: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
    }
}
