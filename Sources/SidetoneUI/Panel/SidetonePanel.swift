import SwiftUI
import AppKit
import SidetoneCore

/// The menu-bar panel. Pure composition: each section is its own view in this folder and reads
/// the shared `SidetoneModel` from the environment; none of them touches audio objects — they
/// only call the model's intent methods.
///
/// Layout (top → bottom): brand · hero control · live waveform · permission banner · the list
/// (meetings + recent recordings) · footer.
public struct SidetonePanel: View {
    @Environment(SidetoneModel.self) private var model

    public init() {}

    private let maxListHeight: CGFloat = 280
    /// Measured height of the list's content; nil until the first layout pass.
    private let measuredListHeight = State<CGFloat?>(initialValue: nil)

    public var body: some View {
        VStack(spacing: 0) {
            HeaderView()

            VStack(alignment: .leading, spacing: DS.Space.s) {
                HeroView()

                WaveformStrip(
                    data: model.waveform,
                    active: model.state != .idle,
                    micEnabled: model.state == .idle ? model.recordMicrophone : model.sessionUsesMic
                )

                if !model.permissionIssues.isEmpty {
                    PermissionBanner()
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, DS.Space.l - 2)
            .padding(.top, DS.Space.m)

            Hairline()
                .padding(.top, DS.Space.m)

            // A menu-bar window sizes to its ideal height, and a ScrollView's ideal height is
            // not its content. Give it an explicit height (measured, with an estimate for the
            // first frame) so a short list stays short and a long one scrolls.
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    if model.meetings.isEmpty && model.recentRecordings.isEmpty {
                        EmptyLibraryNote()
                    } else {
                        MeetingsSection()

                        if !model.recentRecordings.isEmpty {
                            RecentRecordingsSection()
                        }
                    }
                }
                .padding(.vertical, DS.Space.m)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    measuredListHeight.wrappedValue = height
                }
            }
            .scrollIndicators(.never)
            .frame(height: min(measuredListHeight.wrappedValue ?? estimatedListHeight, maxListHeight))
            .overlay(alignment: .bottom) {
                // A long list fades into the panel instead of slicing a row at the hairline.
                if (measuredListHeight.wrappedValue ?? 0) >= maxListHeight - 4 {
                    LinearGradient(
                        colors: [DS.Palette.canvas.opacity(0), DS.Palette.canvas],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 26)
                    .allowsHitTesting(false)
                }
            }

            Hairline()

            FooterView()
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, DS.Space.s)
        }
        .frame(width: DS.Size.panelWidth)
        .background(DS.Palette.canvas)
        .motion(value: model.state)
        .motion(value: model.permissionIssues)
        // The window is created once, so `onAppear` alone would leave meetings/recordings stale.
        // Becoming key is what happens every time the panel is opened.
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // Settings/setup becoming key is not the panel opening.
            guard let window = note.object as? NSWindow,
                  window.title != PreferencesWindowController.windowTitle,
                  window.title != SetupWindowController.windowTitle else { return }
            model.refresh()
        }
    }
}

extension SidetonePanel {
    /// Close enough to the real layout that the first frame rarely moves.
    fileprivate var estimatedListHeight: CGFloat {
        guard !model.meetings.isEmpty || !model.recentRecordings.isEmpty else { return 118 }
        var height: CGFloat = 24 + (model.meetings.isEmpty ? 28 : CGFloat(model.meetings.count) * 40)
        if !model.recentRecordings.isEmpty {
            height += DS.Space.m + 24 + CGFloat(model.recentRecordings.count) * 40
        }
        return height
    }
}

/// First-run panel state: what to do, where it goes, and that it stays here.
private struct EmptyLibraryNote: View {
    @Environment(SidetoneModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Nothing recorded yet")
                .font(DS.Typo.title)
                .foregroundStyle(DS.Palette.textPrimary)
            Text("Press the amber button to record. Takes are saved as one .m4a each.")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.recordingsFolderDisplay)
                .font(DS.Typo.mono)
                .foregroundStyle(DS.Palette.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.recordingsFolderDisplay)
        }
        .padding(.horizontal, DS.Space.s + DS.Space.xs)
        .accessibilityElement(children: .combine)
    }
}
