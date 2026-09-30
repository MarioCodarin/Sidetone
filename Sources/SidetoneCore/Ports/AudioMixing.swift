import Foundation

/// Turns the two raw captures into the final stereo file (desktop = L, mic = R).
///
/// `Sendable` because the model runs it off the main actor.
public protocol AudioMixing: Sendable {
    /// A missing/empty source is treated as silence on its channel; throws only if
    /// nothing was captured on either side or the output can't be written.
    func mix(
        desktopURL: URL,
        micURL: URL,
        desktopResult: CaptureResult,
        micResult: CaptureResult,
        outputURL: URL
    ) throws
}
