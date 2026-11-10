import SwiftUI
import SidetoneCore

/// One row per missing permission, each with a shortcut to the right System Settings pane.
struct PermissionBanner: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        VStack(spacing: DS.Space.xs) {
            ForEach(model.permissionIssues) { issue in
                HStack(alignment: .center, spacing: DS.Space.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Palette.attention)
                        .accessibilityHidden(true)
                    Text(issue.explanation)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Space.xs)
                    Button("Open Settings") { model.openSettings(for: issue) }
                        .buttonStyle(TextActionButtonStyle())
                        .fixedSize()
                        .help("Open System Settings")
                }
                .padding(DS.Space.s)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .fill(DS.Palette.attention.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .strokeBorder(DS.Palette.attention.opacity(0.22), lineWidth: 1)
                )
                .accessibilityElement(children: .contain)
            }
        }
    }
}
