import SwiftUI
import SidetoneCore

/// The brand row: the split-circle mark, the name, and the version in quiet mono.
struct HeaderView: View {
    var body: some View {
        HStack(spacing: DS.Space.s) {
            SplitMark(size: 15)
            Text(AppInfo.name)
                .font(DS.Typo.wordmark)
                .foregroundStyle(DS.Palette.textPrimary)
            Spacer(minLength: DS.Space.s)
            if AppInfo.version != "dev" {
                Text("v\(AppInfo.version)")
                    .font(DS.Typo.mono)
                    .foregroundStyle(DS.Palette.textMuted)
                    .accessibilityLabel("Version \(AppInfo.version)")
            }
        }
        .padding(.horizontal, DS.Space.l - 2)
        .padding(.top, DS.Space.m)
    }
}

/// The product mark: one circle split down the middle — left solid ("them"), right a ring ("you").
/// It is the app icon's glyph, the menu-bar symbol and this row's logo, at one shape.
struct SplitMark: View {
    var size: CGFloat = 16
    var color: Color = DS.Palette.textPrimary

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(color.opacity(0.85), lineWidth: max(1, size * 0.08))
            Circle()
                .trim(from: 0.5, to: 1)
                .fill(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The transient message line under the hero: plain text for info/success, a tinted card for errors.
struct StatusLine: View {
    let status: StatusMessage
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
                Image(systemName: "checkmark")
                    .foregroundStyle(DS.Palette.textMuted)
                    .accessibilityHidden(true)
            }
            Text(status.text)
                .font(DS.Typo.caption)
                .foregroundStyle(isError ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, isError ? DS.Space.s : 0)
        .padding(.vertical, isError ? DS.Space.s : 0)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(isError ? DS.Palette.record.opacity(0.10) : .clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isError ? "Error: \(status.text)" : status.text)
    }
}
