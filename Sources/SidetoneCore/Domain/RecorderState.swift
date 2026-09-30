import Foundation

/// The recorder's lifecycle. `SidetoneModel` is the only writer.
public enum RecorderState: Equatable {
    /// Nothing is being captured; no input device is held.
    case idle
    /// Both sources are being written to disk.
    case recording
    /// Captures stay open (meters keep moving) but nothing is written.
    case paused
}
