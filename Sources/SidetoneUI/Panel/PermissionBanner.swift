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
                        .foregroundStyle(DS.Palette.attention)
                        .accessibilityHidden(true)
                    Text(issue.explanation)
                        .font(DS.Typo.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Space.xs)
                    Button("Open Settings") { model.openSettings(for: issue) }
                        .buttonStyle(ActionButtonStyle(prominent: false, height: 24))
                        .fixedSize()
                }
                .padding(DS.Space.s)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .fill(DS.Palette.attention.opacity(0.12))
                )
                .accessibilityElement(children: .contain)
            }
        }
    }
}
