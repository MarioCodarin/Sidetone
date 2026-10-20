import SwiftUI
import SidetoneCore

/// State dot + label + elapsed time, with the latest status message underneath.
struct HeaderView: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .center, spacing: DS.Space.s) {
                StatusDot(state: model.state)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.state.label)
                        .font(DS.Typo.title)

                    if let title = model.recordingTitle, !title.isEmpty {
                        Text(title)
                            .font(DS.Typo.secondary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: DS.Space.s)

                if model.state != .idle {
                    Text(Formatting.elapsed(model.elapsed))
                        .font(DS.Typo.timer)
                        .foregroundStyle(model.state == .paused ? .secondary : .primary)
                        .accessibilityLabel("Elapsed \(Formatting.elapsed(model.elapsed))")
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, DS.Space.s)

            if let status = model.status {
                StatusMessageView(status: status, busy: model.mixesInFlight > 0)
                    .transition(.opacity)
            }
        }
        .motion(value: model.state)
        .motion(value: model.status)
        .accessibilityElement(children: .contain)
    }
}

/// 8 pt state indicator. The recording dot breathes unless Reduce Motion is on.
private struct StatusDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: RecorderState

    var body: some View {
        Group {
            if state == .recording && !reduceMotion {
                dot.phaseAnimator([1.0, 0.35]) { view, opacity in
                    view.opacity(opacity)
                } animation: { _ in
                    .easeInOut(duration: 0.9)
                }
            } else {
                dot
            }
        }
        .accessibilityHidden(true)
    }

    private var dot: some View {
        Circle()
            .fill(state == .idle ? AnyShapeStyle(.tertiary) : AnyShapeStyle(state.tint))
            .frame(width: 8, height: 8)
    }
}

private struct StatusMessageView: View {
    let status: StatusMessage
    /// A mix is running, so show it as progress rather than only as text.
    let busy: Bool

    var body: some View {
        let isError = status.kind == .error
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            if isError {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(DS.Palette.record)
                    .accessibilityHidden(true)
            } else if busy && status.kind == .info {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
            } else if status.kind == .success {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(status.text)
                .font(DS.Typo.secondary)
                .foregroundStyle(isError ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, isError ? DS.Space.s : 0)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(isError ? DS.Palette.record.opacity(0.10) : .clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isError ? "Error: \(status.text)" : status.text)
    }
}
