import Foundation
import AVFoundation
import Accelerate

/// Per-buffer RMS level in dBFS. Cheap enough for the realtime audio thread
/// (vectorized `vDSP_rmsqv`, no allocation).
public enum RMSMeter {

    /// Floor for the returned level. Truly-silent or invalid buffers report this value
    /// so callers (meters, silence detection) get a stable, finite "very quiet" reading.
    public static let floorDB: Float = -120

    /// RMS of `buffer`'s channel 0 expressed in dBFS (floor for empty / non-float / silent buffers).
    public static func dBFS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return floorDB }
        return dBFS(samples: channels[0], count: Int(buffer.frameLength))
    }

    /// RMS of `count` contiguous samples expressed in dBFS, clamped to `floorDB`.
    public static func dBFS(samples: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return floorDB }

        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(count))

        // Guard log10(0) = -inf and NaN from a bad buffer: 1e-7 ≈ -140 dBFS is "silent".
        guard rms > 1e-7, rms.isFinite else { return floorDB }

        let db = 20 * log10(rms)
        return db.isFinite ? max(db, floorDB) : floorDB
    }
}
