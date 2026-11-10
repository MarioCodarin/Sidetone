import Foundation
import SidetoneCore
import AVFoundation
import CoreAudio   // AudioConvertHostTimeToNanos (mach_absolute_time -> ns)

/// Produces `audio.m4a` (desktop hard LEFT, mic hard RIGHT) and, when asked, `voice.m4a`
/// (the cleaned mic channel, mono).
///
/// Pipeline (all streaming — memory use is a few chunks, independent of recording length):
///  1. Open both mono CAFs as `MonoSource`s (48 kHz mono Float32, resampled on the fly).
///  2. Compute the start skew from the two `firstHostTime` values and delay whichever stream began
///     LATER by that many frames of leading silence, so both line up at t = 0.
///  3. Level-match each channel from the RMS/peak measured during capture, high-pass and gently
///     expand the mic (see `VoiceChain`), then interleave chunk by chunk into a stereo buffer,
///     padding the shorter side with silence.
///  4. Encode to AAC `.m4a` via `AVAudioFile`, into a temp file that replaces `audio.m4a` only on
///     success — a failed mix never leaves a truncated file behind. The voice track is encoded
///     from the same processed samples in the same pass.
///
/// A missing/empty/unreadable desktop source is silence on its channel. With no mic source (mic
/// recording turned off, or no usable mic file) the desktop audio is duplicated onto both channels
/// so the take plays centered instead of left-only. Raw CAFs are never modified.
public struct StereoMixer: AudioMixing {

    public init() {}

    // MARK: - Tunables

    /// Common output sample rate for the mixed file.
    static let outputSampleRate: Double = 48_000
    /// AAC bit rate for the stereo file (speech is transparent well below this; headroom for music).
    private static let outputBitRate = 160_000
    /// AAC bit rate for the mono voice track.
    private static let voiceBitRate = 96_000
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
        outputURL: URL,
        voiceTrackURL: URL?,
        options: AudioMixOptions
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

        // Level-match each side to the same speech RMS (only when the capture measured it), and
        // clean the mic. The desktop gets no filtering — it may be music, not a voice.
        let desktopGain = options.levelMatch
            ? VoiceChain.makeupGainDB(rmsDB: desktopResult.rmsDB, peakDB: desktopResult.peakDB,
                                      targetRMSDB: options.targetRMSDB)
            : 0
        let micGain = options.levelMatch
            ? VoiceChain.makeupGainDB(rmsDB: micResult.rmsDB, peakDB: micResult.peakDB,
                                      targetRMSDB: options.targetRMSDB)
            : 0
        Log.mix.debug("mix gains: desktop \(desktopGain, format: .fixed(precision: 1)) dB, mic \(micGain, format: .fixed(precision: 1)) dB, clarity \(options.voiceClarity, privacy: .public)")

        let left = Channel(
            source: desktop,
            leadingSilence: lead.desktop,
            processor: VoiceChain(sampleRate: Self.outputSampleRate, gainDB: desktopGain,
                                  clarity: false, parameters: .levelOnly)
        )
        let right = Channel(
            source: mic,
            leadingSilence: lead.mic,
            processor: VoiceChain(sampleRate: Self.outputSampleRate, gainDB: micGain,
                                  clarity: options.voiceClarity)
        )

        // Encode next to the destination, then swap in atomically.
        let folder = outputURL.deletingLastPathComponent()
        let partialURL = folder.appendingPathComponent("audio-partial.m4a")
        let partialVoiceURL = voiceTrackURL == nil ? nil : folder.appendingPathComponent("voice-partial.m4a")
        try? FileManager.default.removeItem(at: partialURL)
        if let partialVoiceURL { try? FileManager.default.removeItem(at: partialVoiceURL) }

        do {
            let wroteVoice = try Self.encode(
                left: left,
                right: right,
                stereoFormat: stereoFormat,
                monoFormat: monoFormat,
                to: partialURL,
                voiceURL: partialVoiceURL
            )
            try Self.replace(outputURL, with: partialURL)

            if wroteVoice, let voiceTrackURL, let partialVoiceURL {
                do {
                    try Self.replace(voiceTrackURL, with: partialVoiceURL)
                } catch {
                    // The voice track is a bonus; never fail the recording over it.
                    Log.mix.error("voice track could not be installed: \(error.localizedDescription, privacy: .public)")
                    try? FileManager.default.removeItem(at: partialVoiceURL)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            if let partialVoiceURL { try? FileManager.default.removeItem(at: partialVoiceURL) }
            throw error
        }
    }

    private static func replace(_ destination: URL, with replacement: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: replacement)
        } else {
            try FileManager.default.moveItem(at: replacement, to: destination)
        }
    }

    // MARK: - Channel streaming

    /// One output channel: `leadingSilence` zeros, then the source, then zeros forever. Its
    /// processor (level match, cleanup, limiter) runs on the samples that come out of it.
    private struct Channel {
        let source: MonoSource?
        var leadingSilence: Int
        var exhausted: Bool
        var processor: VoiceChain?

        init(source: MonoSource?, leadingSilence: Int, processor: VoiceChain?) {
            self.source = source
            // A missing source is pure silence; delaying silence would only lengthen the file.
            self.leadingSilence = source == nil ? 0 : max(0, leadingSilence)
            self.exhausted = source == nil
            self.processor = processor
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
            if real > 0, processor != nil {
                processor!.process(destination, count: real)
            }
            return real
        }
    }

    private static func encode(
        left: Channel,
        right: Channel,
        stereoFormat: AVAudioFormat,
        monoFormat: AVAudioFormat,
        to url: URL,
        voiceURL: URL?
    ) throws -> Bool {
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

        // The voice track is written from the same processed right-channel samples, in the same
        // pass. A failure here is non-fatal: the stereo file is what must survive.
        var voiceFile: AVAudioFile?
        var voiceBuffer: AVAudioPCMBuffer?
        var voiceEnabled = false
        var voiceReportedError = false
        if let voiceURL, right.source != nil {
            let voiceSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: outputSampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: voiceBitRate
            ]
            do {
                voiceFile = try AVAudioFile(
                    forWriting: voiceURL, settings: voiceSettings,
                    commonFormat: .pcmFormatFloat32, interleaved: false
                )
                voiceBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(chunkFrames))
                voiceEnabled = voiceFile != nil && voiceBuffer != nil
            } catch {
                Log.mix.error("voice track could not be created: \(error.localizedDescription, privacy: .public)")
            }
        }

        var left = left, right = right
        var wroteAny = false
        var voiceFrames: AVAudioFramePosition = 0

        while true {
            // The file is as long as the longer channel; the shorter one is zero-padded by `fill`.
            let real = max(left.fill(channels[0], count: chunkFrames), right.fill(channels[1], count: chunkFrames))
            if real == 0 { break }
            if right.source == nil, left.source != nil {
                channels[1].update(from: channels[0], count: chunkFrames)
            }
            buffer.frameLength = AVAudioFrameCount(real)
            do { try outFile.write(from: buffer) } catch { throw MixError.writeFailed(error.localizedDescription) }
            wroteAny = true

            if voiceEnabled, let voiceFile, let voiceBuffer, let voiceData = voiceBuffer.floatChannelData?[0] {
                voiceData.update(from: channels[1], count: real)
                voiceBuffer.frameLength = AVAudioFrameCount(real)
                do {
                    try voiceFile.write(from: voiceBuffer)
                    voiceFrames += AVAudioFramePosition(real)
                } catch {
                    // Stop writing the bonus track, keep the stereo file.
                    voiceEnabled = false
                    if !voiceReportedError {
                        voiceReportedError = true
                        Log.mix.error("voice track write failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
        if !wroteAny { throw MixError.bothSourcesEmpty }
        return voiceFrames > 0
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
