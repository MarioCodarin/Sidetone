import Foundation
import Accelerate

/// Mix-time voice cleanup for the microphone channel.
///
/// The raw captures are never altered — this runs while the finished files are being written, so
/// a re-mix can apply a different setting. Four stages, in order:
///
/// 1. **Level** — a static gain that brings the take to a consistent speech RMS (capped so the
///    measured peak cannot exceed -1 dBFS). Quiet mics become audible, loud ones are tamed.
/// 2. **Rumble filter** — a 12 dB/octave high-pass at 70 Hz removes desk thumps, HVAC rumble and
///    DC offset without touching the speech band.
/// 3. **Noise floor** — a very gentle downward expander (2.5:1, at most 10 dB of reduction, 5 ms
///    attack / 200 ms release) turns steady room tone down between words. It is deliberately mild:
///    an aggressive gate clips consonants and hurts transcription more than noise does.
/// 4. **Limiter** — a soft-knee ceiling at -1 dBFS, so the gain stage can never clip the AAC.
///
/// Streaming and stateful: filter and gain state carry across buffers, so it can run on chunks
/// while the mixer interleaves. Allocation-free.
public struct VoiceChain: Sendable {

    public struct Parameters: Sendable {
        /// High-pass corner. Below the male speech fundamental, above most rumble.
        public var highPassHz: Double
        /// dBFS below which the expander starts reducing gain.
        public var gateThresholdDB: Float
        /// Expansion ratio. 2.5 means a floor 10 dB below the threshold is reduced by 6 dB.
        public var gateRatio: Float
        /// Never reduce more than this, however quiet the signal.
        public var gateMaxReductionDB: Float
        public var gateAttackSeconds: Float
        public var gateReleaseSeconds: Float
        /// Expander analysis window.
        public var blockSeconds: Float

        public init(
            highPassHz: Double = 70,
            gateThresholdDB: Float = -50,
            gateRatio: Float = 2.5,
            gateMaxReductionDB: Float = 10,
            gateAttackSeconds: Float = 0.005,
            gateReleaseSeconds: Float = 0.2,
            blockSeconds: Float = 0.02
        ) {
            self.highPassHz = highPassHz
            self.gateThresholdDB = gateThresholdDB
            self.gateRatio = gateRatio
            self.gateMaxReductionDB = gateMaxReductionDB
            self.gateAttackSeconds = gateAttackSeconds
            self.gateReleaseSeconds = gateReleaseSeconds
            self.blockSeconds = blockSeconds
        }

        public static let `default` = Parameters()
        /// Level + limiter only: used for the desktop channel, where filtering would colour music.
        public static let levelOnly = Parameters(highPassHz: 20, gateThresholdDB: -120)
    }

    private let sampleRate: Float
    private let gainDB: Float
    private let clarity: Bool
    private let parameters: Parameters
    private let blockFrames: Int

    private var highPass: Biquad
    /// Smoothed expander gain, 0…1.
    private var gateGain: Float = 1

    /// Ceiling for the soft limiter: -1 dBFS.
    private static let ceiling: Float = 0.891

    public init(
        sampleRate: Double,
        gainDB: Float,
        clarity: Bool = true,
        parameters: Parameters = .default
    ) {
        self.sampleRate = Float(sampleRate)
        self.gainDB = gainDB
        self.clarity = clarity
        self.parameters = parameters
        self.blockFrames = max(1, Int(sampleRate * Double(parameters.blockSeconds)))
        self.highPass = Biquad.highPass(frequency: clarity ? parameters.highPassHz : 20, sampleRate: sampleRate)
    }

    /// Makeup gain that brings `rmsDB` to `target`, but never so much that `peakDB` would exceed
    /// -1 dBFS. Returns 0 when the capture has no measurement (older recordings).
    public static func makeupGainDB(
        rmsDB: Float?,
        peakDB: Float?,
        targetRMSDB: Float = -20,
        maxGainDB: Float = 18,
        maxCutDB: Float = 12
    ) -> Float {
        guard let rmsDB, rmsDB.isFinite, rmsDB > -70 else { return 0 }
        var gain = targetRMSDB - rmsDB
        if let peakDB, peakDB.isFinite {
            gain = min(gain, -1 - peakDB)
        }
        return max(-maxCutDB, min(maxGainDB, gain))
    }

    /// Process `count` mono samples in place.
    public mutating func process(_ samples: UnsafeMutablePointer<Float>, count: Int) {
        guard count > 0 else { return }

        if gainDB != 0 {
            var scale = pow(10, gainDB / 20)
            vDSP_vsmul(samples, 1, &scale, samples, 1, vDSP_Length(count))
        }

        if clarity {
            for index in 0..<count {
                samples[index] = highPass.process(samples[index])
            }
            applyExpander(samples, count: count)
        }

        limit(samples, count: count)
    }

    // MARK: - Expander

    private mutating func applyExpander(_ samples: UnsafeMutablePointer<Float>, count: Int) {
        var offset = 0
        while offset < count {
            let block = min(blockFrames, count - offset)
            var rms: Float = 0
            vDSP_rmsqv(samples + offset, 1, &rms, vDSP_Length(block))
            let db = rms > 1e-7 ? 20 * log10(rms) : -140

            var target: Float = 1
            if db < parameters.gateThresholdDB {
                let reduction = min(
                    parameters.gateMaxReductionDB,
                    (parameters.gateThresholdDB - db) * (1 - 1 / parameters.gateRatio)
                )
                target = pow(10, -reduction / 20)
            }

            let seconds = Float(block) / sampleRate
            let time = target > gateGain ? parameters.gateAttackSeconds : parameters.gateReleaseSeconds
            let coefficient = 1 - exp(-seconds / max(time, 0.0001))
            let next = gateGain + (target - gateGain) * coefficient

            // Ramp across the block so the gain change cannot click.
            var gain = gateGain
            let step = (next - gateGain) / Float(block)
            for index in 0..<block {
                samples[offset + index] *= gain
                gain += step
            }
            gateGain = next
            offset += block
        }
    }

    // MARK: - Limiter

    private func limit(_ samples: UnsafeMutablePointer<Float>, count: Int) {
        let ceiling = Self.ceiling
        let range = 1 - ceiling
        for index in 0..<count {
            let value = samples[index]
            let magnitude = abs(value)
            guard magnitude > ceiling else { continue }
            let compressed = ceiling + range * tanh((magnitude - ceiling) / range)
            samples[index] = value < 0 ? -compressed : compressed
        }
    }

    /// Direct-form-II-transposed biquad. A single RBJ high-pass section; a per-sample loop at
    /// 48 kHz mono is far cheaper than the AAC encode next to it.
    struct Biquad {
        var b0: Float = 1
        var b1: Float = 0
        var b2: Float = 0
        var a1: Float = 0
        var a2: Float = 0
        var z1: Float = 0
        var z2: Float = 0

        static func highPass(frequency: Double, sampleRate: Double, q: Double = 0.7071) -> Biquad {
            let omega = 2 * Double.pi * frequency / sampleRate
            let alpha = sin(omega) / (2 * q)
            let cosOmega = cos(omega)
            let a0 = 1 + alpha
            return Biquad(
                b0: Float((1 + cosOmega) / 2 / a0),
                b1: Float(-(1 + cosOmega) / a0),
                b2: Float((1 + cosOmega) / 2 / a0),
                a1: Float(-2 * cosOmega / a0),
                a2: Float((1 - alpha) / a0)
            )
        }

        mutating func process(_ input: Float) -> Float {
            let output = b0 * input + z1
            z1 = b1 * input - a1 * output + z2
            z2 = b2 * input - a2 * output
            return output
        }
    }
}
