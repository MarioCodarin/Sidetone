import Foundation

/// Typed wrapper over `UserDefaults` for the app's persisted preferences.
///
/// Keys + sensible defaults live here in one place; `SidetoneModel` mirrors these
/// into `@Observable` properties (loading them at launch, writing them back on
/// change) so the UI can bind to them while disk persistence stays out of band.
public enum Preferences {
    /// Production uses `.standard`. Tests pass a suite so they cannot leak into the host app.
    public static var defaults: UserDefaults = .standard

    private enum Key {
        static let silenceTimeout     = "silenceTimeoutSeconds"
        static let silenceThresholdDB = "silenceThresholdDB"
        static let silenceAutoStop    = "silenceAutoStopEnabled"
        static let recordMicrophone   = "recordMicrophone"
        static let recordingsFolder   = "recordingsFolderPath"
        static let didCompleteSetup   = "didCompleteSetup"
        static let voiceClarity       = "voiceClarity"
        static let saveVoiceTrack     = "saveVoiceTrack"
    }

    /// Seconds of two-channel silence before a recording auto-stops. Default 300 (5 min).
    public static var silenceTimeout: TimeInterval {
        get { defaults.object(forKey: Key.silenceTimeout) == nil ? 300 : defaults.double(forKey: Key.silenceTimeout) }
        set { defaults.set(newValue, forKey: Key.silenceTimeout) }
    }

    /// dBFS below which a channel counts as silent. Default -50.
    public static var silenceThresholdDB: Float {
        get { defaults.object(forKey: Key.silenceThresholdDB) == nil ? -50 : defaults.float(forKey: Key.silenceThresholdDB) }
        set { defaults.set(newValue, forKey: Key.silenceThresholdDB) }
    }

    /// Whether the microphone is part of new recordings. Default true.
    public static var recordMicrophone: Bool {
        get { defaults.object(forKey: Key.recordMicrophone) == nil ? true : defaults.bool(forKey: Key.recordMicrophone) }
        set { defaults.set(newValue, forKey: Key.recordMicrophone) }
    }

    /// Whether silence auto-stop is active at all. Default true.
    public static var silenceAutoStop: Bool {
        get { defaults.object(forKey: Key.silenceAutoStop) == nil ? true : defaults.bool(forKey: Key.silenceAutoStop) }
        set { defaults.set(newValue, forKey: Key.silenceAutoStop) }
    }

    /// Where the user keeps their takes. `nil` (the default) means `~/Documents/Recordings`.
    public static var recordingsFolderPath: String? {
        get { defaults.string(forKey: Key.recordingsFolder) }
        set { defaults.set(newValue, forKey: Key.recordingsFolder) }
    }

    /// Whether the first-run setup was completed or skipped. Until then the app opens it at launch.
    public static var didCompleteSetup: Bool {
        get { defaults.bool(forKey: Key.didCompleteSetup) }
        set { defaults.set(newValue, forKey: Key.didCompleteSetup) }
    }

    /// High-pass + gentle noise-floor reduction on the voice channel. Default true.
    public static var voiceClarity: Bool {
        get { defaults.object(forKey: Key.voiceClarity) == nil ? true : defaults.bool(forKey: Key.voiceClarity) }
        set { defaults.set(newValue, forKey: Key.voiceClarity) }
    }

    /// Write a cleaned, mic-only `.voice.m4a` beside each recording, for transcription. Default true.
    public static var saveVoiceTrack: Bool {
        get { defaults.object(forKey: Key.saveVoiceTrack) == nil ? true : defaults.bool(forKey: Key.saveVoiceTrack) }
        set { defaults.set(newValue, forKey: Key.saveVoiceTrack) }
    }
}
