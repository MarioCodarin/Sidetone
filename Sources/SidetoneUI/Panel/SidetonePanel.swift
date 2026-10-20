import SwiftUI
import AppKit
import SidetoneCore

/// The menu-bar panel. Pure composition: each section is its own view in this folder and reads
/// the shared `SidetoneModel` from the environment; none of them touches audio objects — they
/// only call the model's intent methods.
///
/// Layout (top → bottom): header · permission banner (if needed) · controls · level meters
/// (while capturing) · meetings · recent recordings · footer.
public struct SidetonePanel: View {
    @Environment(SidetoneModel.self) private var model

    public init() {}

    private let panelWidth: CGFloat = 336
    private let maxListHeight: CGFloat = 320

    /// Height of the list's content, measured. Starts at a plausible guess to avoid a jump on
    /// the first open.
    private let listContentHeight = State(initialValue: CGFloat(160))

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HeaderView()

            if !model.permissionIssues.isEmpty {
                PermissionBanner()
                    .transition(.opacity)
            }

            ControlsView()

            if model.state != .idle {
                MetersView()
                    .transition(.opacity)
            }

            // A menu-bar window sizes to its ideal height, and a ScrollView's ideal height is
            // not its content. Measure the content so a short list stays short and a long one
            // scrolls instead of running off the screen.
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    MeetingsSection()

                    if !model.recentRecordings.isEmpty {
                        RecentRecordingsSection()
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    listContentHeight.wrappedValue = height
                }
            }
            .scrollIndicators(.never)
            .frame(height: min(listContentHeight.wrappedValue, maxListHeight))

            Divider()
                .opacity(0.6)

            FooterView()
        }
        .padding(DS.Space.m)
        .frame(width: panelWidth)
        .motion(value: model.state)
        .motion(value: model.permissionIssues)
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
}
