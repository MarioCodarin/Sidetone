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

            // A menu-bar window sizes to its ideal height, and a ScrollView's ideal height is
            // not the list. Give it an explicit height so a short list stays short and a long
            // one scrolls instead of running off the screen.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    MeetingsSection()

                    if !model.recentRecordings.isEmpty {
                        Divider()
                        RecentRecordingsSection()
                    }
                }
            }
            .frame(height: listHeight)

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
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // Settings becoming key is not the panel opening. Refreshing there re-fetches
            // the calendar while the user is clicking in that window.
            guard let window = note.object as? NSWindow, window.title != "Sidetone Settings" else { return }
            model.refresh()
        }
    }

    /// Matches the section headers and rows closely enough that the cap is the only slack.
    private var listHeight: CGFloat {
        var height: CGFloat = 28
        if model.meetings.isEmpty {
            height += 24
        } else {
            height += CGFloat(model.meetings.count) * 44
        }
        if !model.recentRecordings.isEmpty {
            height += 16
            height += 28
            height += CGFloat(model.recentRecordings.count) * 48
        }
        return min(height, 360)
    }
}
