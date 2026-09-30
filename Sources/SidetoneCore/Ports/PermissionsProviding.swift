import Foundation

public enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
}

/// Microphone permission (the only one with a query API; system-audio denial is only
/// discoverable when the tap fails to start, which surfaces as `CaptureError.permissionDenied`).
public protocol PermissionsProviding {
    func microphoneStatus() -> PermissionStatus
    /// Prompts if undetermined; returns the resulting status.
    func requestMicrophone() async -> PermissionStatus
}
