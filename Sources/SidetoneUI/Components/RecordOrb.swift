import SwiftUI
import SidetoneCore

/// The one hero control: a circular button whose ring is the live level meter for each channel.
///
/// Idle it is an amber disc ("arm"); while recording the disc becomes a red stop square and the
/// two half-rings breathe with the desktop (left) and mic (right) levels. The split-circle mark
/// is the product's signature, so the control and the icon are the same shape.
struct RecordOrb: View {
    let state: RecorderState
    let desktopLevel: Float
    let micLevel: Float
    let micEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HoverReader { hovering in
                ZStack {
                    Circle()
                        .fill(DS.Palette.surface)

                    Circle()
                        .strokeBorder(DS.Palette.hairline, lineWidth: 1)

                    if state != .idle {
                        arcs
                    }

                    glyph
                        .scaleEffect(hovering ? 1.06 : 1)
                }
                .frame(width: DS.Size.orbit, height: DS.Size.orbit)
                .overlay(
                    Circle()
                        .strokeBorder(hovering ? DS.Palette.hairlineStrong : .clear, lineWidth: 1)
                        .padding(1)
                )
                .scaleEffect(hovering ? 1.02 : 1)
                .animation(DS.Motion.quick, value: hovering)
                .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .help(state == .idle ? "Start recording  ⌘R" : "Stop and save  ⌘R")
        .accessibilityLabel(state == .idle ? "Start recording" : "Stop and save the recording")
        .accessibilityValue(state.label)
    }

    /// Left half = desktop ("Them"), right half = mic ("You"). Trim starts at 3 o'clock, so the
    /// whole view is rotated to start at 12, where half of the ring is each channel.
    private var arcs: some View {
        ZStack {
            Circle()
                .trim(from: 1 - 0.5 * CGFloat(max(0, min(1, desktopLevel))), to: 1)
                .stroke(DS.Palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if micEnabled {
                Circle()
                    .trim(from: 0, to: 0.5 * CGFloat(max(0, min(1, micLevel))))
                    .stroke(DS.Palette.textPrimary.opacity(0.75),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(5)
    }

    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .idle:
            Circle()
                .fill(DS.Palette.accent)
                .frame(width: 22, height: 22)
        case .recording:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DS.Palette.record)
                .frame(width: 20, height: 20)
        case .paused:
            Image(systemName: "play.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DS.Palette.attention)
                .padding(.leading, 2)
        }
    }
}

/// A compact circular secondary control (pause, discard) that sits next to the orb.
struct SecondaryOrbButton: View {
    let systemImage: String
    var tint: Color = DS.Palette.textSecondary
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(DS.Palette.surface)
                )
                .overlay(
                    Circle().strokeBorder(DS.Palette.hairline, lineWidth: 1)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
