import SwiftUI
import SidetoneCore

/// Microphone and silence auto-stop settings. Hosted in an AppKit `NSWindow` — see
/// `PreferencesWindowController`. No `@State`: Command Line Tools lack SwiftUIMacros.
public struct PreferencesView: View {
    @Environment(SidetoneModel.self) private var model

    public init() {}

    public var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Record my microphone", isOn: $model.recordMicrophone)
                Text(model.recordMicrophone
                     ? "Your voice goes on the right channel, the call on the left."
                     : "Only the call (system audio) is recorded. The microphone is never opened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Microphone")
            }

            Section {
                Toggle("Stop automatically after silence", isOn: $model.silenceAutoStopEnabled)

                if model.silenceAutoStopEnabled {
                    Stepper(
                        value: Binding(
                            get: { Int((model.silenceTimeout / 60).rounded()) },
                            set: { model.silenceTimeout = TimeInterval(max(1, $0) * 60) }
                        ),
                        in: 1...60
                    ) {
                        Text("After \(Int((model.silenceTimeout / 60).rounded())) min of silence on both channels")
                            .monospacedDigit()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Silence threshold")
                            Spacer()
                            Text("\(Int(model.silenceThresholdDB)) dB")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.silenceThresholdDB, in: -80 ... -20, step: 1)
                            .accessibilityLabel("Silence threshold")
                            .accessibilityValue("\(Int(model.silenceThresholdDB)) decibels")
                        Text("A channel counts as silent below this level. Lower = more tolerant of quiet rooms.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Auto-stop")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
