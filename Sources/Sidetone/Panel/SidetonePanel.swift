import SwiftUI
import AppKit
import SidetoneCore

/// The menu-bar panel. Pure composition: each section is its own view in this folder and reads
/// the shared `SidetoneModel` from the environment; none of them touches audio objects — they
/// only call the model's intent methods.
///
/// Layout (top → bottom): header · permission banner (if needed) · controls · level meters
/// (while capturing) · meetings · recent recordings · footer.
struct SidetonePanel: View {
    @Environment(SidetoneModel.self) private var model

    private let panelWidth: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderView()

            if !model.permissionIssues.isEmpty {
                PermissionBanner()
            }

            Divider()

            ControlsView()

            if model.state != .idle {
                Divider()
                MetersView()
            }

            Divider()

            MeetingsSection()

            if !model.recentRecordings.isEmpty {
                Divider()
                RecentRecordingsSection()
            }

            Divider()

            FooterView()
        }
        .padding(12)
        .frame(width: panelWidth)
        // Suppress the auto-drawn focus ring on the first control when the panel opens.
        .focusEffectDisabled()
        // The window is created once, so `onAppear` alone would leave meetings/recordings stale.
        // Becoming key is what happens every time the panel is opened.
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refresh()
        }
    }
}
