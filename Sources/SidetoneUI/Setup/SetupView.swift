import SwiftUI
import SidetoneCore

/// First-run setup: three permissions + where your recordings live. No account, no keys.
///
/// Shown once at launch (and re-openable from Settings). Finishing or closing it marks setup
/// complete, so it never nags; "Start recording" just closes the window.
public struct SetupView: View {
    @Environment(SidetoneModel.self) private var model

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            SetupHero()

            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("Two channels, one file")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("Sidetone records the call on the left and your voice on the right, so you always know who said what. Everything stays on this Mac.")
                    .font(DS.Typo.body)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                PermissionSetupRow(
                    title: "Microphone",
                    detail: "Your voice, on the right channel.",
                    status: micStatus,
                    actionTitle: micActionTitle,
                    action: requestMicrophone
                )
                SetupDivider()
                PermissionSetupRow(
                    title: "System audio",
                    detail: "The call, on the left channel.",
                    status: .neutral("On first record"),
                    actionTitle: "Open Settings",
                    action: { model.openSettings(for: .systemAudio) }
                )
                SetupDivider()
                PermissionSetupRow(
                    title: "Calendar",
                    detail: "Optional. Names takes after the meeting you’re in.",
                    status: calendarStatus,
                    actionTitle: calendarActionTitle,
                    action: requestCalendar
                )
                SetupDivider()
                PermissionSetupRow(
                    title: "Recordings folder",
                    detail: model.recordingsFolderDisplay,
                    status: .neutral("Your disk"),
                    actionTitle: "Choose…",
                    action: { Task { await model.chooseRecordingsFolder() } }
                )
            }
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                    .fill(DS.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                    .strokeBorder(DS.Palette.hairline, lineWidth: 1)
            )

            HStack(spacing: DS.Space.s) {
                Text("No account, keys or uploads.")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textMuted)
                Spacer()
                Button("Skip") { finish() }
                    .buttonStyle(QuietButtonStyle())
                Button("Start recording") { finish() }
                    .buttonStyle(ActionButtonStyle(height: 30))
                    .frame(width: 150)
            }
        }
        .padding(DS.Space.xl + DS.Space.xs)
        .frame(width: DS.Size.setupWidth)
        .background(DS.Palette.canvas)
    }

    private func finish() {
        model.completeSetup()
        SetupWindowController.shared.close()
    }

    private func requestMicrophone() {
        switch model.microphonePermission {
        case .denied: model.openSettings(for: .microphone)
        case .granted, .notDetermined: Task { await model.requestMicrophoneAccess() }
        }
    }

    private func requestCalendar() {
        switch model.calendarPermission {
        case .denied: model.openSettings(for: .calendar)
        case .granted, .notDetermined: Task { await model.requestCalendarAccess() }
        }
    }

    private var micStatus: PermissionSetupRow.Status {
        switch model.microphonePermission {
        case .granted:      return .granted
        case .denied:       return .off
        case .notDetermined: return .neutral("Not asked")
        }
    }

    private var micActionTitle: String {
        model.microphonePermission == .denied ? "Open Settings" : "Allow"
    }

    private var calendarStatus: PermissionSetupRow.Status {
        switch model.calendarPermission {
        case .granted:      return .granted
        case .denied:       return .off
        case .notDetermined: return .neutral("Optional")
        }
    }

    private var calendarActionTitle: String {
        model.calendarPermission == .denied ? "Open Settings" : "Allow"
    }
}

// MARK: - Pieces

private struct PermissionSetupRow: View {
    enum Status {
        case granted
        case off
        case neutral(String)

        var text: String {
            switch self {
            case .granted:          return "Allowed"
            case .off:              return "Off"
            case .neutral(let text): return text
            }
        }

        var color: Color {
            switch self {
            case .granted:          return DS.Palette.textMuted
            case .off:              return DS.Palette.attention
            case .neutral:          return DS.Palette.textMuted
            }
        }
    }

    let title: String
    let detail: String
    let status: Status
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typo.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(detail)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(detail)
            }
            Spacer(minLength: DS.Space.s)

            HStack(spacing: DS.Space.xs) {
                if case .granted = status {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.textMuted)
                        .accessibilityHidden(true)
                }
                Text(status.text)
                    .font(DS.Typo.mono)
                    .foregroundStyle(status.color)
            }

            if !isGranted {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle())
                    .fixedSize()
            }
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.m - 2)
        .accessibilityElement(children: .contain)
    }

    private var isGranted: Bool {
        if case .granted = status { return true }
        return false
    }
}

private struct SetupDivider: View {
    var body: some View {
        Hairline().padding(.leading, DS.Space.m)
    }
}

/// The one rich moment of setup: the same two-channel scope the panel uses, at rest.
private struct SetupHero: View {
    var body: some View {
        Canvas { context, size in
            let mid = size.height * 0.56
            let step = size.width / 96
            let amplitude = mid - 14

            var centre = Path()
            centre.move(to: CGPoint(x: 0, y: mid))
            centre.addLine(to: CGPoint(x: size.width, y: mid))
            context.stroke(centre, with: .color(DS.Palette.hairlineStrong), lineWidth: 1)

            func trace(_ value: (Double) -> Double, above: Bool) -> Path {
                var path = Path()
                for index in 0...96 {
                    let t = Double(index) / 96
                    let envelope = sin(t * .pi)
                    let level = min(1, max(0, value(t) * envelope))
                    let y = above ? mid - level * amplitude : mid + level * amplitude
                    let point = CGPoint(x: CGFloat(index) * step, y: y)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                return path
            }

            let top = trace({ 0.22 + 0.62 * abs(sin($0 * 17.1 + 0.6)) }, above: true)
            let bottom = trace({ 0.18 + 0.5 * abs(sin($0 * 11.3 + 2.1)) }, above: false)

            var topArea = top
            topArea.addLine(to: CGPoint(x: size.width, y: mid))
            topArea.addLine(to: CGPoint(x: 0, y: mid))
            topArea.closeSubpath()
            context.fill(topArea, with: .color(DS.Palette.accent.opacity(0.14)))
            context.stroke(top, with: .color(DS.Palette.accent), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            var bottomArea = bottom
            bottomArea.addLine(to: CGPoint(x: size.width, y: mid))
            bottomArea.addLine(to: CGPoint(x: 0, y: mid))
            bottomArea.closeSubpath()
            context.fill(bottomArea, with: .color(DS.Palette.textPrimary.opacity(0.08)))
            context.stroke(bottom, with: .color(DS.Palette.textPrimary.opacity(0.72)),
                          style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            context.draw(Text("THEM / L").font(DS.Typo.mono).foregroundStyle(DS.Palette.textMuted),
                         at: CGPoint(x: 10, y: 12), anchor: .leading)
            context.draw(Text("YOU / R").font(DS.Typo.mono).foregroundStyle(DS.Palette.textMuted),
                         at: CGPoint(x: size.width - 10, y: size.height - 12), anchor: .trailing)
        }
        .frame(height: 90)
        .padding(DS.Space.m)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                .strokeBorder(DS.Palette.hairline, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}
