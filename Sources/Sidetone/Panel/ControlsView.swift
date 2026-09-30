import SwiftUI
import SidetoneCore

/// Record (idle) or Pause / Save / Discard (recording, paused).
struct ControlsView: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        switch model.state {
        case .idle:
            idleControls
        case .recording, .paused:
            activeControls
        }
    }

    // MARK: Idle

    /// The meeting "in progress" changes with the clock, not with model state, so tick it.
    private var idleControls: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let current = model.currentMeeting(at: context.date) {
                VStack(alignment: .leading, spacing: 6) {
                    recordButton(title: "Record Meeting", meeting: current)
                    HStack(spacing: 4) {
                        Text("Tags this recording as “\(current.title)”.")
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Button("Without meeting") { model.startRecording(meeting: nil) }
                            .buttonStyle(.link)
                            .help("Record without attaching to a meeting")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } else {
                recordButton(title: "Record", meeting: nil)
            }
        }
    }

    private func recordButton(title: String, meeting: Meeting?) -> some View {
        Button {
            model.startRecording(meeting: meeting)
        } label: {
            Label(title, systemImage: "record.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .keyboardShortcut("r", modifiers: [.command])
    }

    // MARK: Recording / paused

    private var activeControls: some View {
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
                Label("Discard", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .controlSize(.large)
            .buttonStyle(.bordered)
            .tint(.red)
            .help("Discard this recording")
        }
    }
}
