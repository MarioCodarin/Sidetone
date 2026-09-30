import Foundation

/// Which side of the call a capture belongs to.
public enum CaptureSource: String, Codable {
    case desktop
    case mic
}

/// Failures a capture reports in a form the model can react to (without knowing Core Audio).
public enum CaptureError: LocalizedError {
    /// macOS refused access; the user has to grant it in System Settings.
    case permissionDenied(CaptureSource)
    /// Anything else, already phrased for the user.
    case failed(CaptureSource, String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(.desktop):
            return "System Audio Recording permission is required to capture the other side of the call."
        case .permissionDenied(.mic):
            return "Microphone permission is required to capture your voice."
        case .failed(_, let message):
            return message
        }
    }
}

/// One mono capture that streams to a raw file (`desktop.caf` / `mic.caf`).
///
/// Implemented by `SystemAudioTap` and `MicCapture` in `SidetoneAudio`; faked in tests.
/// Callbacks arrive on audio/arbitrary threads — the model hops to main before touching state.
public protocol AudioCapturing: AnyObject {
    /// dBFS per buffer, throttled for the UI. Called on an audio thread.
    var onLevelDB: ((Float) -> Void)? { get set }
    /// Called on an arbitrary thread when the capture fails mid-recording.
    var onFatalError: ((Error) -> Void)? { get set }

    func start(writingTo url: URL) throws
    /// Gate writes without closing the device (meters keep updating). Thread-safe.
    func setPaused(_ paused: Bool)
    /// Stop, finalize the file, and report what was written.
    func stop() -> CaptureResult
}
