import SwiftUI
import SidetoneCore

/// Settings: recording, auto-stop, where your data lives, and about. A custom layout (not a
/// stock `Form`) so it reads as part of the same instrument as the panel.
public struct PreferencesView: View {
    @Environment(SidetoneModel.self) private var model
    private let repoURL = URL(string: "https://github.com/MarioCodarin/Sidetone")!

    public init() {}

    public var body: some View {
        @Bindable var model = model
        let minutes = Int((model.silenceTimeout / 60).rounded())

        VStack(alignment: .leading, spacing: DS.Space.l + DS.Space.xs) {
            header

            SettingsCard(title: "Recording") {
                SettingsRow(title: "Microphone",
                            detail: model.recordMicrophone
                                ? "Your voice on the right channel; the call on the left."
                                : "The mic is never opened. Only the call is recorded.") {
                    Toggle("", isOn: $model.recordMicrophone)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(DS.Palette.accent)
                        .accessibilityLabel("Record my microphone")
                }

                SettingsDivider()

                SettingsRow(title: "Recordings folder",
                            detail: model.recordingsFolderDisplay) {
                    HStack(spacing: DS.Space.xs) {
                        Button("Change…") { Task { await model.chooseRecordingsFolder() } }
                            .buttonStyle(ActionButtonStyle(fill: .neutral, height: 26))
                            .fixedSize()
                        Button {
                            model.openRecordingsFolder()
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .accessibilityLabel("Open recordings folder in Finder")
                        }
                        .buttonStyle(IconButtonStyle())
                        .help("Open in Finder")
                    }
                }

                SettingsDivider()

                SettingsRow(title: "Permissions",
                            detail: permissionSummary) {
                    if !model.permissionIssues.isEmpty {
                        Button("Open Settings") { model.openSettings(for: firstIssue) }
                            .buttonStyle(TextActionButtonStyle())
                            .fixedSize()
                    }
                }
            }

            SettingsCard(title: "Stop when quiet") {
                SettingsRow(title: "Auto-stop",
                            detail: "Ends a take when both channels stay below the threshold.") {
                    Toggle("", isOn: $model.silenceAutoStopEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(DS.Palette.accent)
                        .accessibilityLabel("Stop after silence")
                }

                if model.silenceAutoStopEnabled {
                    SettingsDivider()
                    SettingsRow(title: "Silence lasts", detail: "Minutes of two-channel silence.") {
                        HStack(spacing: DS.Space.s) {
                            Text("\(minutes) min")
                                .font(DS.Typo.mono)
                                .foregroundStyle(DS.Palette.textSecondary)
                                .frame(width: 44, alignment: .trailing)
                            Stepper(
                                "Minutes of silence before stopping",
                                value: Binding(
                                    get: { minutes },
                                    set: { model.silenceTimeout = TimeInterval(max(1, $0) * 60) }
                                ),
                                in: 1...60
                            )
                            .labelsHidden()
                            .accessibilityValue("\(minutes) minutes")
                        }
                    }

                    SettingsDivider()
                    SettingsRow(title: "Threshold", detail: "Quieter than this counts as silence.") {
                        HStack(spacing: DS.Space.s) {
                            Slider(
                                value: Binding(
                                    get: { Double(model.silenceThresholdDB) },
                                    set: { model.silenceThresholdDB = Float($0.rounded()) }
                                ),
                                in: -80 ... -20
                            )
                            .frame(width: 150)
                            .tint(DS.Palette.accent)
                            .accessibilityLabel("Silence threshold")
                            .accessibilityValue("\(Int(model.silenceThresholdDB)) decibels")
                            Text("\(Int(model.silenceThresholdDB)) dB")
                                .font(DS.Typo.mono)
                                .foregroundStyle(DS.Palette.textSecondary)
                                .frame(width: 46, alignment: .trailing)
                        }
                    }
                }
            }

            SettingsCard(title: "Your data") {
                SettingsRow(title: "Stays on this Mac",
                            detail: "No account, no keys, no uploads. A finished take is one .m4a file.") {
                    EmptyView()
                }
                SettingsDivider()
                SettingsRow(title: "Setup", detail: "Permissions and the recordings folder.") {
                    Button("Run setup again") {
                        model.replaySetup()
                        SetupWindowController.shared.show(model: model)
                    }
                    .buttonStyle(QuietButtonStyle())
                    .fixedSize()
                }
            }

            footer
        }
        .padding(DS.Space.xl - DS.Space.xs)
        .frame(width: DS.Size.settingsWidth)
        .background(DS.Palette.canvas)
    }

    private var header: some View {
        HStack(spacing: DS.Space.s) {
            SplitMark(size: 17)
            Text("Settings")
                .font(DS.Typo.heading)
                .foregroundStyle(DS.Palette.textPrimary)
            Spacer()
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.s) {
            Text("Sidetone \(AppInfo.version) (\(AppInfo.build))")
                .font(DS.Typo.mono)
                .foregroundStyle(DS.Palette.textMuted)
            Spacer()
            Button("GitHub") { model.open(repoURL) }
                .buttonStyle(QuietButtonStyle())
        }
    }

    /// A one-line permission summary; the full explanation lives in the panel banner.
    private var permissionSummary: String {
        if model.permissionIssues.contains(.microphone) { return "Microphone access is off." }
        if model.permissionIssues.contains(.systemAudio) { return "System Audio Recording access is off." }
        if model.permissionIssues.contains(.calendar) { return "Calendar access is off; meetings can’t be listed." }
        return "All granted."
    }

    private var firstIssue: PermissionIssue {
        model.permissionIssues.first ?? .microphone
    }
}

// MARK: - Pieces

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(title)
                .font(DS.Typo.section)
                .foregroundStyle(DS.Palette.textSecondary)
                .padding(.leading, DS.Space.xs)
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                    .fill(DS.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                    .strokeBorder(DS.Palette.hairline, lineWidth: 1)
            )
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typo.title)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(detail)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(detail)
            }
            Spacer(minLength: DS.Space.s)
            control()
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.m - 2)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Hairline()
            .padding(.leading, DS.Space.m)
    }
}
