import SwiftUI
import SidetoneCore

/// Microphone and silence auto-stop settings. Hosted in an AppKit `NSWindow` — see
/// `PreferencesWindowController`. No `@State`: Command Line Tools lack SwiftUIMacros.
public struct PreferencesView: View {
    @Environment(SidetoneModel.self) private var model

    public init() {}

    public var body: some View {
        @Bindable var model = model
        let minutes = Int((model.silenceTimeout / 60).rounded())

        Form {
            Section {
                Toggle("Record my microphone", isOn: $model.recordMicrophone)
            } header: {
                Text("Microphone")
            } footer: {
                Text(model.recordMicrophone
                     ? "Your voice goes on the right channel, the call on the left."
                     : "Only the call is recorded. The microphone is never opened.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                Toggle("Stop after silence", isOn: $model.silenceAutoStopEnabled)

                if model.silenceAutoStopEnabled {
                    LabeledContent("Silence lasts") {
                        HStack(spacing: DS.Space.s) {
                            Text("\(minutes) min")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
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

                    LabeledContent("Threshold") {
                        HStack(spacing: DS.Space.s) {
                            Slider(
                                value: Binding(
                                    get: { Double(model.silenceThresholdDB) },
                                    set: { model.silenceThresholdDB = Float($0.rounded()) }
                                ),
                                in: -80 ... -20
                            )
                                .frame(width: 140)
                                .accessibilityLabel("Silence threshold")
                                .accessibilityValue("\(Int(model.silenceThresholdDB)) decibels")
                            Text("\(Int(model.silenceThresholdDB)) dB")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }
            } header: {
                Text("Auto-stop")
            } footer: {
                Text(model.silenceAutoStopEnabled
                     ? "Recording stops when both channels stay below the threshold. Lower it if quiet rooms stop too early."
                     : "Recordings run until you stop them.")
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .motion(value: model.silenceAutoStopEnabled)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
