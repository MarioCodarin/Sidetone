import Foundation
import AVFoundation

/// What a capture reports when it stops. Persisted per session (`session.json`) so a
/// recording can be re-mixed later with the same alignment.
public struct CaptureResult: Codable, Equatable {
    /// mach host time (`mach_absolute_time` domain) of the FIRST sample written; nil if nothing captured.
    public var firstHostTime: UInt64?
    /// Sample rate of the raw file on disk.
    public var sampleRate: Double
    /// Number of audio frames written.
    public var frameCount: AVAudioFramePosition

    public init(firstHostTime: UInt64? = nil, sampleRate: Double = 0, frameCount: AVAudioFramePosition = 0) {
        self.firstHostTime = firstHostTime
        self.sampleRate = sampleRate
        self.frameCount = frameCount
    }
}
