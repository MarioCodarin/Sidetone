import SwiftUI
import AppKit
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
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                if let current = model.currentMeeting(at: context.date) {
                    recordButton(title: "Record Meeting", meeting: current)
                    HStack(spacing: DS.Space.xs) {
                        Text("Named “\(current.title)”")
                            .font(DS.Typo.secondary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: DS.Space.xs)
                        Button("Without meeting") { model.startRecording(meeting: nil) }
                            .buttonStyle(QuietButtonStyle())
                            .layoutPriority(1)
                            .help("Record without attaching to a meeting")
                    }
                    .padding(.leading, DS.Space.s)
                } else {
                    recordButton(title: "Record", meeting: nil)
                }
            }
        }
    }

    private func recordButton(title: String, meeting: Meeting?) -> some View {
        Button {
            model.startRecording(meeting: meeting)
        } label: {
            ZStack {
                Label(title, systemImage: "record.circle.fill")
                HStack {
                    Spacer()
                    Text("⌘R")
                        .font(DS.Typo.secondary)
                        .opacity(0.7)
                        .accessibilityHidden(true)
                }
                .padding(.trailing, DS.Space.m)
            }
        }
        .buttonStyle(ActionButtonStyle(tint: DS.Palette.record, height: 36))
        .keyboardShortcut("r", modifiers: [.command])
    }

    // MARK: Recording / paused

    private var activeControls: some View {
        HStack(spacing: DS.Space.s) {
            Button {
                model.togglePause()
            } label: {
                Label(
                    model.state == .paused ? "Resume" : "Pause",
                    systemImage: model.state == .paused ? "play.fill" : "pause.fill"
                )
            }
            .buttonStyle(ActionButtonStyle(prominent: false, height: 36))

            Button {
                model.saveAndStop()
            } label: {
                Label("Save", systemImage: "stop.fill")
            }
            .buttonStyle(ActionButtonStyle(tint: .accentColor, height: 36))

            Button(role: .destructive) {
                confirmDiscard()
            } label: {
                Label("Discard", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(DS.Palette.record)
            }
            .buttonStyle(ActionButtonStyle(prominent: false, height: 36))
            .frame(width: 40)
            .help("Discard this recording")
        }
    }

    /// A sheet on the menu-bar window. `confirmationDialog` does not present reliably there.
    private func confirmDiscard() {
        let alert = NSAlert()
        alert.messageText = "Discard this recording?"
        alert.informativeText = "The recording in progress will be deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Keep Recording")
        alert.buttons.first?.hasDestructiveAction = true

        guard let window = NSApp.keyWindow else { return }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                model.trashAndStop()
            }
        }
    }
}
