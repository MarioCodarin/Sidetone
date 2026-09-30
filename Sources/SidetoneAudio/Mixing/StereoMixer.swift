import Foundation
import SidetoneCore
import AVFoundation
import CoreAudio   // AudioConvertHostTimeToNanos (mach_absolute_time -> ns)

/// Produces `audio.m4a`: desktop audio hard LEFT (ch0), mic hard RIGHT (ch1).
///
/// Pipeline (all streaming — memory use is a few chunks, independent of recording length):
///  1. Open both mono CAFs as `MonoSource`s (48 kHz mono Float32, resampled on the fly).
///  2. Compute the start skew from the two `firstHostTime` values and delay whichever stream began
///     LATER by that many frames of leading silence, so both line up at t = 0.
///  3. Interleave chunk by chunk into a stereo buffer, padding the shorter side with silence.
///  4. Encode to AAC `.m4a` via `AVAudioFile`, into a temp file that replaces `audio.m4a` only on
///     success — a failed mix never leaves a truncated `audio.m4a` behind.
///
/// A missing/empty/unreadable source is silence on its channel. Raw CAFs are never modified.
public struct StereoMixer: AudioMixing {

    public init() {}

    // MARK: - Tunables

    /// Common output sample rate for the mixed file.
    static let outputSampleRate: Double = 48_000
    /// AAC bit rate for the encoded `.m4a`.
    private static let outputBitRate = 128_000
    /// Frames processed per iteration.
    private static let chunkFrames = 16_384

    // MARK: - Errors

    enum MixError: LocalizedError {
        case couldNotCreateFormat
        case couldNotAllocateBuffer
        case bothSourcesEmpty
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .couldNotCreateFormat:   return "Could not create an audio format for mixing."
            case .couldNotAllocateBuffer: return "Could not allocate an audio buffer for mixing."
            case .bothSourcesEmpty:       return "Both audio sources were empty — nothing to mix."
            case .writeFailed(let why):   return "Failed to write the mixed file: \(why)"
            }
        }
    }

    // MARK: - AudioMixing

    public func mix(
        desktopURL: URL,
        micURL: URL,
        desktopResult: CaptureResult,
        micResult: CaptureResult,
        outputURL: URL
    ) throws {
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.outputSampleRate, channels: 1, interleaved: false
        ), let stereoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.outputSampleRate, channels: 2, interleaved: false
        ) else {
            throw MixError.couldNotCreateFormat
        }

        let desktop = MonoSource(url: desktopURL, outputFormat: monoFormat)
        let mic = MonoSource(url: micURL, outputFormat: monoFormat)
        if desktop == nil && mic == nil {
            throw MixError.bothSourcesEmpty
        }

        let lead = Self.leadingSilenceFrames(
            desktopHostTime: desktopResult.firstHostTime,
            micHostTime: micResult.firstHostTime
        )

        // Encode next to the destination, then swap in atomically.
        let partialURL = outputURL.deletingLastPathComponent().appendingPathComponent("audio-partial.m4a")
        try? FileManager.default.removeItem(at: partialURL)
        do {
            try Self.encode(
                left: Channel(source: desktop, leadingSilence: lead.desktop),
                right: Channel(source: mic, leadingSilence: lead.mic),
                stereoFormat: stereoFormat,
                to: partialURL
            )
            if FileManager.default.fileExists(atPath: outputURL.path) {
                _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: partialURL)
            } else {
                try FileManager.default.moveItem(at: partialURL, to: outputURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            throw error
        }
    }

    // MARK: - Channel streaming

    /// One output channel: `leadingSilence` zeros, then the source, then zeros forever.
    private struct Channel {
        let source: MonoSource?
        var leadingSilence: Int
        var exhausted: Bool

        init(source: MonoSource?, leadingSilence: Int) {
            self.source = source
            // A missing source is pure silence; delaying silence would only lengthen the file.
            self.leadingSilence = source == nil ? 0 : max(0, leadingSilence)
            self.exhausted = source == nil
        }

        /// Fill `count` frames of `destination` (zero-padding whatever the channel can't supply)
        /// and return how many of them are real content: leading silence + source frames.
        mutating func fill(_ destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
            var real = 0
            if leadingSilence > 0 {
                let n = min(leadingSilence, count)
                destination.update(repeating: 0, count: n)
                leadingSilence -= n
                real = n
            }
            if real < count, !exhausted, let source {
                let wanted = count - real
                let got = source.read(into: destination + real, count: wanted)
                if got < wanted { exhausted = true }
                real += got
            }
            if real < count {
                (destination + real).update(repeating: 0, count: count - real)
            }
            return real
        }
    }

    private static func encode(left: Channel, right: Channel, stereoFormat: AVAudioFormat, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: outputSampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: outputBitRate
        ]
        let outFile: AVAudioFile
        do {
            outFile = try AVAudioFile(
                forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false
            )
        } catch {
            throw MixError.writeFailed(error.localizedDescription)
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: AVAudioFrameCount(chunkFrames)),
              let channels = buffer.floatChannelData else {
            throw MixError.couldNotAllocateBuffer
        }

        var left = left, right = right
        var wroteAny = false
        while true {
            // The file is as long as the longer channel; the shorter one is zero-padded by `fill`.
            let real = max(left.fill(channels[0], count: chunkFrames), right.fill(channels[1], count: chunkFrames))
            if real == 0 { break }
            buffer.frameLength = AVAudioFrameCount(real)
            do { try outFile.write(from: buffer) } catch { throw MixError.writeFailed(error.localizedDescription) }
            wroteAny = true
        }
        if !wroteAny { throw MixError.bothSourcesEmpty }
        // `outFile` finalizes (closes the AAC stream) when it deinits at scope end.
    }

    // MARK: - Alignment

    /// Convert the two first-sample host times into how many 48 kHz frames of leading silence each
    /// stream needs so the EARLIER stream starts at frame 0 and the LATER one is pushed back by
    /// the inter-onset gap. Unknown onsets → assume coincident starts.
    public static func leadingSilenceFrames(
        desktopHostTime: UInt64?,
        micHostTime: UInt64?
    ) -> (desktop: Int, mic: Int) {
        guard let d = desktopHostTime, let m = micHostTime else { return (0, 0) }
        if d == m { return (0, 0) }
        if d < m {
            return (0, framesForNanos(AudioConvertHostTimeToNanos(m - d)))   // delay the mic
        }
        return (framesForNanos(AudioConvertHostTimeToNanos(d - m)), 0)       // delay the desktop
    }

    /// Nanoseconds -> 48 kHz frame count (rounded to nearest, clamped >= 0).
    public static func framesForNanos(_ nanos: UInt64) -> Int {
        let frames = (Double(nanos) / 1_000_000_000.0 * outputSampleRate).rounded()
        guard frames > 0, frames.isFinite else { return 0 }
        return Int(frames)
    }
}
