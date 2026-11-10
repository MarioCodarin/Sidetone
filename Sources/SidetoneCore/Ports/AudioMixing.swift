import Foundation

/// How the raw captures are turned into the final files.
public struct AudioMixOptions: Sendable, Equatable {
    /// High-pass + gentle noise-floor reduction on the voice channel.
    public var voiceClarity: Bool
    /// Bring both channels to a common speech level (only when the capture recorded its RMS).
    public var levelMatch: Bool
    /// RMS target for level matching, in dBFS.
    public var targetRMSDB: Float

    public init(voiceClarity: Bool = true, levelMatch: Bool = true, targetRMSDB: Float = -20) {
        self.voiceClarity = voiceClarity
        self.levelMatch = levelMatch
        self.targetRMSDB = targetRMSDB
    }
}

/// Turns the two raw captures into the final stereo file (desktop = L, mic = R), and optionally
/// a mono voice track for transcription.
///
/// `Sendable` because the model runs it off the main actor.
public protocol AudioMixing: Sendable {
    /// A missing/empty source is treated as silence on its channel; throws only if
    /// nothing was captured on either side or the output can't be written.
    ///
    /// - Parameter voiceTrackURL: when non-nil and the mic captured something, a cleaned mono
    ///   AAC file is written there as well. A failure to write it never fails the main mix.
    func mix(
        desktopURL: URL,
        micURL: URL,
        desktopResult: CaptureResult,
        micResult: CaptureResult,
        outputURL: URL,
        voiceTrackURL: URL?,
        options: AudioMixOptions
    ) throws
}

extension AudioMixing {
    /// Convenience for callers (and tests) that only want the stereo file.
    public func mix(
        desktopURL: URL,
        micURL: URL,
        desktopResult: CaptureResult,
        micResult: CaptureResult,
        outputURL: URL
    ) throws {
        try mix(
            desktopURL: desktopURL, micURL: micURL,
            desktopResult: desktopResult, micResult: micResult,
            outputURL: outputURL, voiceTrackURL: nil, options: AudioMixOptions()
        )
    }
}
