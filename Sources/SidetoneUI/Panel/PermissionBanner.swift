import SwiftUI
import SidetoneCore

/// One row per missing permission, each with a shortcut to the right System Settings pane.
struct PermissionBanner: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            ForEach(model.permissionIssues) { issue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(issue.explanation)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button("Open Settings") { model.openSettings(for: issue) }
                        .controlSize(.small)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
            }
        }
    }
}
