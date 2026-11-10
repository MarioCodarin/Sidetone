import Foundation
import Accelerate

/// Running RMS and peak of the samples actually written to disk.
///
/// Updated on the producer side (the IOProc / audio tap) and read only after that producer has
/// stopped, so it needs no lock. Used by the mixer to level-match a take without a second pass.
struct LevelStats {
    private(set) var frames: Int = 0
    private var sumSquares: Double = 0
    private var peak: Float = 0

    mutating func reset() {
        frames = 0
        sumSquares = 0
        peak = 0
    }

    mutating func add(_ samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        var squares: Float = 0
        vDSP_svesq(samples, 1, &squares, vDSP_Length(count))
        sumSquares += Double(squares)
        frames += count

        var highest: Float = 0
        vDSP_maxmgv(samples, 1, &highest, vDSP_Length(count))
        if highest > peak { peak = highest }
    }

    /// RMS in dBFS, nil when nothing was written.
    var rmsDB: Float? {
        guard frames > 0, sumSquares > 0 else { return nil }
        let rms = sqrt(sumSquares / Double(frames))
        let db = 20 * log10(Float(rms))
        return db.isFinite ? db : nil
    }

    /// Loudest sample in dBFS, nil when the take was pure silence.
    var peakDB: Float? {
        guard frames > 0, peak > 0 else { return nil }
        let db = 20 * log10(peak)
        return db.isFinite ? db : nil
    }
}
