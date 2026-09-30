import Foundation
import AVFoundation
import SidetoneCore

/// Microphone permission via `AVCaptureDevice` (the `AVAudioSession` API is iOS-only).
public struct SystemPermissions: PermissionsProviding {

    public init() {}

    public func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:            return .granted
        case .notDetermined:         return .notDetermined
        case .denied, .restricted:   return .denied
        @unknown default:            return .denied
        }
    }

    public func requestMicrophone() async -> PermissionStatus {
        if microphoneStatus() == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        return microphoneStatus()
    }
}
