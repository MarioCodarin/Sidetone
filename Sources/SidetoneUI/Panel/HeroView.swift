import SwiftUI
import AppKit
import SidetoneCore

/// The control deck: one orb, the state (or the clock), and the two secondary actions while a
/// take is running. The meeting this take is tagged with sits underneath as a quiet hint.
struct HeroView: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .center, spacing: DS.Space.m) {
                RecordOrb(
                    state: model.state,
                    desktopLevel: model.desktopLevel,
                    micLevel: model.micLevel,
                    micEnabled: model.sessionUsesMic || model.recordMicrophone,
                    action: primaryAction
                )

                VStack(alignment: .leading, spacing: 1) {
                    stateLine
                    Text(subtitle)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: DS.Space.s)

                if model.state == .idle {
                    KeyCap(text: "⌘R")
                        .padding(.trailing, DS.Space.xs)
                        .accessibilityHidden(true)
                } else {
                    VStack(spacing: DS.Space.xs) {
                        SecondaryOrbButton(
                            systemImage: model.state == .paused ? "play.fill" : "pause.fill",
                            help: model.state == .paused ? "Resume  ⌘P" : "Pause  ⌘P"
                        ) {
                            model.togglePause()
                        }

                        SecondaryOrbButton(
                            systemImage: "trash",
                            tint: DS.Palette.record.opacity(0.85),
                            help: "Discard this recording"
                        ) {
                            confirmDiscard()
                        }
                    }
                }
            }

            // Hidden shortcuts: the orb is a custom control, so ⌘R / ⌘P need real buttons.
            Group {
                Button("") { primaryAction() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("") { model.togglePause() }
                    .keyboardShortcut("p", modifiers: [.command])
                    .disabled(model.state == .idle)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)

            if let status = model.status {
                StatusLine(status: status, busy: model.mixesInFlight > 0)
                    .transition(.opacity)
            } else if model.state == .idle {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if let meeting = model.currentMeeting(at: context.date) {
                        MeetingHint(meeting: meeting)
                    }
                }
            }
        }
        .motion(value: model.status)
        .motion(value: model.state)
    }

    @ViewBuilder
    private var stateLine: some View {
        if model.state == .idle {
            Text("Ready to record")
                .font(DS.Typo.heading)
                .foregroundStyle(DS.Palette.textPrimary)
        } else {
            Text(Formatting.elapsed(model.elapsed))
                .font(DS.Typo.timer)
                .foregroundStyle(model.state == .paused ? DS.Palette.textSecondary : DS.Palette.textPrimary)
                .contentTransition(.numericText())
                .accessibilityLabel("Elapsed \(Formatting.elapsed(model.elapsed))")
        }
    }

    private var subtitle: String {
        if model.state == .idle {
            return model.state.channelSummary(micEnabled: model.recordMicrophone)
        }
        if let title = model.recordingTitle, !title.isEmpty {
            return model.state == .paused ? "Paused · \(title)" : title
        }
        return model.state.channelSummary(micEnabled: model.sessionUsesMic)
    }

    private func primaryAction() {
        if model.state == .idle {
            model.startRecording(meeting: model.currentMeeting(at: Date()))
        } else {
            model.saveAndStop()
        }
    }

    /// A sheet on the menu-bar window. `confirmationDialog` does not present reliably there.
    private func confirmDiscard() {
        let alert = NSAlert()
        alert.messageText = "Discard this recording?"
        alert.informativeText = "The take in progress will be deleted. You can’t undo this."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Keep recording")
        alert.buttons.first?.hasDestructiveAction = true

        guard let window = NSApp.keyWindow else { return }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                model.trashAndStop()
            }
        }
    }
}

/// "In “Weekly sync” · until 13:10" — what this take will be named if you press record now.
private struct MeetingHint: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: DS.Space.s) {
            StatusDot(color: DS.Palette.accent)
            Text("In “\(meeting.title)”")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: DS.Space.xs)
            Text("until \(meeting.end.formatted(.dateTime.hour().minute()))")
                .font(DS.Typo.mono)
                .foregroundStyle(DS.Palette.textMuted)
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .strokeBorder(DS.Palette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording now will be named \(meeting.title), until \(meeting.end.formatted(date: .omitted, time: .shortened))")
    }
}
