import Foundation
import AVFoundation
import CoreAudio
import SidetoneCore
import SidetoneAudio
#if DEBUG
@testable import SidetoneAudio
#endif

/// Signal-level checks: ring buffer, meters, downmix, file writer, streaming mixer. No hardware.
func runAudioChecks() throws {

    // MARK: FloatRingBuffer

    do {
        let ring = FloatRingBuffer(capacityFrames: 16)
        let src: [Float] = [1, 2, 3, 4, 5]
        src.withUnsafeBufferPointer { expect(ring.write($0.baseAddress!, count: 5), "ring write") }
        expectEqual(ring.availableFrames, 5, "ring availableFrames")
        var dst = [Float](repeating: 0, count: 8)
        let n = dst.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, maxCount: 8) }
        expectEqual(n, 5, "ring read count")
        expectEqual(Array(dst.prefix(5)), src, "ring round-trip")
        expectEqual(ring.totalDropped, 0, "ring no drops")
    }
    do {
        let ring = FloatRingBuffer(capacityFrames: 8)
        let first: [Float] = [1, 2, 3, 4, 5, 6]
        first.withUnsafeBufferPointer { _ = ring.write($0.baseAddress!, count: 6) }
        var drain = [Float](repeating: 0, count: 4)
        _ = drain.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, maxCount: 4) }
        let second: [Float] = [7, 8, 9, 10]
        second.withUnsafeBufferPointer { expect(ring.write($0.baseAddress!, count: 4), "ring wrap write") }
        var out = [Float](repeating: 0, count: 8)
        let n = out.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, maxCount: 8) }
        expectEqual(n, 6, "ring wrap count")
        expectEqual(Array(out.prefix(6)), [5, 6, 7, 8, 9, 10] as [Float], "ring wrap data")
    }
    do {
        let ring = FloatRingBuffer(capacityFrames: 4)
        let src: [Float] = [1, 2, 3]
        src.withUnsafeBufferPointer { _ = ring.write($0.baseAddress!, count: 3) }
        let extra: [Float] = [9, 9]
        extra.withUnsafeBufferPointer { expect(!ring.write($0.baseAddress!, count: 2), "ring overflow returns false") }
        expectEqual(ring.totalDropped, 2, "ring overflow dropped 2")
        var out = [Float](repeating: 0, count: 4)
        let n = out.withUnsafeMutableBufferPointer { ring.read(into: $0.baseAddress!, maxCount: 4) }
        expectEqual(n, 3, "ring overflow preserved original")
        expectEqual(Array(out.prefix(3)), src, "ring overflow data intact")
    }

    // MARK: RMSMeter

    do {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256)!
        buffer.frameLength = 256
        expectEqual(RMSMeter.dBFS(buffer), RMSMeter.floorDB, "RMS silence is floor")
        let ptr = buffer.floatChannelData![0]
        for i in 0..<256 { ptr[i] = 1.0 }
        let db = RMSMeter.dBFS(buffer)
        expect(db > -1 && db <= 0, "RMS full-scale ~ 0 dBFS (got \(db))")
        expectEqual(RMSMeter.dBFS(samples: ptr, count: 0), RMSMeter.floorDB, "RMS empty is floor")
    }

    // MARK: MonoFileWriter (the disk path shared by both captures)

    do {
        let dir = try makeTempDir("writer")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("w.caf")
        let writer = try MonoFileWriter(url: url, sampleRate: 48_000)

        func produce(seconds: Double, rate: Double, hostTime: UInt64) {
            let total = Int(seconds * rate)
            var chunk = [Float](repeating: 0, count: 1_000)
            var done = 0
            var host = hostTime
            while done < total {
                let n = min(chunk.count, total - done)
                for i in 0..<n { chunk[i] = 0.5 * sin(2 * .pi * 440 * Float(done + i) / Float(rate)) }
                chunk.withUnsafeBufferPointer { writer.write($0.baseAddress!, count: n, hostTime: host) }
                done += n
                host += 1
            }
        }
        produce(seconds: 1, rate: 48_000, hostTime: 777)
        // The device renegotiated to 24 kHz: the writer must resample, not stretch, the audio.
        writer.setSourceRate(24_000)
        produce(seconds: 1, rate: 24_000, hostTime: 999_999)
        let summary = writer.finish()

        expectEqual(summary.firstHostTime, 777, "writer keeps the FIRST host time")
        expectEqual(summary.droppedFrames, 0, "writer dropped nothing")
        expectClose(Double(summary.framesWritten), 96_000, tolerance: 600, "writer: 1 s @48k + 1 s @24k = 2 s of file")

        let file = try AVAudioFile(forReading: url)
        expectEqual(file.processingFormat.sampleRate, 48_000, "writer file stays at the original rate")
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        // 440 Hz keeps its pitch across the rate change: ~880 zero-crossings per second.
        func crossings(_ range: Range<Int>) -> Int {
            let p = buffer.floatChannelData![0]
            var n = 0
            for i in range.dropFirst() where (p[i - 1] < 0) != (p[i] < 0) { n += 1 }
            return n
        }
        let expected = 880.0 * 0.8
        expectClose(Double(crossings(2_000..<40_000)), expected, tolerance: 40, "pitch before the switch")
        expectClose(Double(crossings(56_000..<94_000)), expected, tolerance: 40, "pitch after the switch (no chipmunk/slow-mo)")
    }

    // MARK: StereoMixer alignment maths

    do {
        let nilLeads = StereoMixer.leadingSilenceFrames(desktopHostTime: nil, micHostTime: nil)
        expectEqual(nilLeads.desktop, 0, "align nil desktop")
        expectEqual(nilLeads.mic, 0, "align nil mic")
        let equal = StereoMixer.leadingSilenceFrames(desktopHostTime: 42, micHostTime: 42)
        expectEqual(equal.desktop, 0, "align equal desktop")
        expectEqual(equal.mic, 0, "align equal mic")
        expectEqual(StereoMixer.framesForNanos(1_000_000_000), 48_000, "1s → 48000 frames")

        let base: UInt64 = 1_000_000
        let later = base + AudioConvertNanosToHostTime(500_000_000)
        let desktopLater = StereoMixer.leadingSilenceFrames(desktopHostTime: later, micHostTime: base)
        expectClose(Double(desktopLater.desktop), 24_000, tolerance: 5, "later desktop is delayed 0.5 s")
        expectEqual(desktopLater.mic, 0, "earlier mic not delayed")
        let micLater = StereoMixer.leadingSilenceFrames(desktopHostTime: base, micHostTime: later)
        expectClose(Double(micLater.mic), 24_000, tolerance: 5, "later mic is delayed 0.5 s")
    }

    // MARK: StereoMixer end to end (streaming, resampling, alignment, channel placement)

    do {
        let dir = try makeTempDir("mix")
        defer { try? FileManager.default.removeItem(at: dir) }
        let desktop = dir.appendingPathComponent(RecordingFiles.desktop)
        let mic = dir.appendingPathComponent(RecordingFiles.mic)
        let output = dir.appendingPathComponent(RecordingFiles.mix)

        // Desktop: 2 s @ 44.1 kHz (forces resampling across many chunks), amplitude 0.5.
        // Mic: 1 s @ 48 kHz, amplitude 0.25. Desktop starts 0.5 s AFTER the mic.
        try writeSineCAF(to: desktop, seconds: 2, sampleRate: 44_100, amplitude: 0.5)
        try writeSineCAF(to: mic, seconds: 1, sampleRate: 48_000, amplitude: 0.25)
        let base: UInt64 = 1_000_000
        try StereoMixer().mix(
            desktopURL: desktop, micURL: mic,
            desktopResult: CaptureResult(firstHostTime: base + AudioConvertNanosToHostTime(500_000_000), sampleRate: 44_100, frameCount: 88_200),
            micResult: CaptureResult(firstHostTime: base, sampleRate: 48_000, frameCount: 48_000),
            outputURL: output
        )

        let file = try AVAudioFile(forReading: output)
        expectEqual(Int(file.processingFormat.channelCount), 2, "mix is stereo")
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        // 0.5 s lead + 2 s desktop = 2.5 s = 120000 frames (AAC priming/padding tolerance).
        expectClose(Double(buffer.frameLength), 120_000, tolerance: 4_096, "mix length = longer channel incl. lead")

        func rms(_ ch: Int, _ range: Range<Int>) -> Float {
            let ptr = buffer.floatChannelData![ch]
            var sum: Float = 0
            for i in range { sum += ptr[i] * ptr[i] }
            return sqrt(sum / Float(range.count))
        }
        expect(rms(0, 0..<20_000) < 0.02, "desktop (L) silent during its 0.5 s lead")
        expect(rms(1, 2_000..<20_000) > 0.1, "mic (R) audible from t=0 (\(rms(1, 2_000..<20_000)))")
        expect(rms(0, 30_000..<100_000) > 0.25, "desktop (L) carries the desktop sine (\(rms(0, 30_000..<100_000)))")
        expect(rms(1, 60_000..<110_000) < 0.02, "mic (R) silent after its source ended")
        expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("audio-partial.m4a").path), "no partial file left")
    }

    // A missing source is silence on its channel, not an error.
    do {
        let dir = try makeTempDir("mix-missing")
        defer { try? FileManager.default.removeItem(at: dir) }
        let desktop = dir.appendingPathComponent(RecordingFiles.desktop)
        let output = dir.appendingPathComponent(RecordingFiles.mix)
        try writeSineCAF(to: desktop, seconds: 0.5, sampleRate: 48_000, amplitude: 0.5)
        try StereoMixer().mix(
            desktopURL: desktop, micURL: dir.appendingPathComponent("nope.caf"),
            desktopResult: CaptureResult(), micResult: CaptureResult(), outputURL: output
        )
        let file = try AVAudioFile(forReading: output)
        expectClose(Double(file.length), 24_000, tolerance: 4_096, "mix with missing mic still produced")

        // No mic → desktop is duplicated on both channels (centered, not left-only).
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8_192)!
        try file.read(into: buffer, frameCount: 8_192)
        var maxDiff: Float = 0, peak: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            let l = buffer.floatChannelData![0][i], r = buffer.floatChannelData![1][i]
            maxDiff = max(maxDiff, abs(l - r)); peak = max(peak, abs(l))
        }
        expect(peak > 0.2 && maxDiff < 1e-6, "missing mic → desktop on both channels (peak \(peak), diff \(maxDiff))")
    }

    // Nothing captured at all → error, and no output file.
    do {
        let dir = try makeTempDir("mix-empty")
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent(RecordingFiles.mix)
        var threw = false
        do {
            try StereoMixer().mix(
                desktopURL: dir.appendingPathComponent("a.caf"), micURL: dir.appendingPathComponent("b.caf"),
                desktopResult: CaptureResult(), micResult: CaptureResult(), outputURL: output
            )
        } catch { threw = true }
        expect(threw, "mix with both sources missing throws")
        expect(!FileManager.default.fileExists(atPath: output.path), "failed mix leaves no audio.m4a")
    }

    // A failed re-mix must not destroy an existing good mix.
    do {
        let dir = try makeTempDir("mix-keep")
        defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent(RecordingFiles.mix)
        try Data([1, 2, 3]).write(to: output)
        _ = try? StereoMixer().mix(
            desktopURL: dir.appendingPathComponent("a.caf"), micURL: dir.appendingPathComponent("b.caf"),
            desktopResult: CaptureResult(), micResult: CaptureResult(), outputURL: output
        )
        expectEqual((try? Data(contentsOf: output))?.count, 3, "failed mix keeps the previous audio.m4a")
    }
    // MARK: VoiceChain (mix-time cleanup)

    func sine(_ frequency: Double, amplitude: Float, seconds: Double) -> [Float] {
        let count = Int(48_000 * seconds)
        return (0..<count).map { index in
            Float(sin(2 * .pi * frequency * Double(index) / 48_000)) * amplitude
        }
    }

    func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(into: Float(0)) { $0 += $1 * $1 }
        return sqrt(sum / Float(samples.count))
    }

    func processed(_ input: [Float], gainDB: Float = 0, clarity: Bool = true) -> [Float] {
        var output = input
        var chain = VoiceChain(sampleRate: 48_000, gainDB: gainDB, clarity: clarity)
        output.withUnsafeMutableBufferPointer { buffer in
            chain.process(buffer.baseAddress!, count: buffer.count)
        }
        return output
    }

    do {
        // Rumble filter: 50 Hz must come out clearly quieter than 1 kHz.
        let low = processed(sine(50, amplitude: 0.5, seconds: 1))
        let speech = processed(sine(1_000, amplitude: 0.5, seconds: 1))
        let lowRMS = rms(low[24_000...])
        let speechRMS = rms(speech[24_000...])
        expect(lowRMS < speechRMS * 0.7, "voice chain: 50 Hz rumble attenuated (\(lowRMS) vs \(speechRMS))")
        expectClose(Double(speechRMS), 0.5 / sqrt(2), tolerance: 0.02, "voice chain: speech band passes through")

        // Noise floor: a -60 dBFS tone is reduced, a -20 dBFS tone is not.
        let quietIn = sine(1_000, amplitude: 0.001, seconds: 1)
        let quietOut = processed(quietIn)
        let quietRatio = rms(quietOut[24_000...]) / rms(quietIn[24_000...])
        expect(quietRatio < 0.75, "voice chain: quiet noise floor reduced (ratio \(quietRatio))")

        let loudIn = sine(1_000, amplitude: 0.1, seconds: 1)
        let loudOut = processed(loudIn)
        let loudRatio = rms(loudOut[24_000...]) / rms(loudIn[24_000...])
        expect(loudRatio > 0.95 && loudRatio < 1.05, "voice chain: speech level untouched (ratio \(loudRatio))")

        // Limiter: hot input cannot leave the chain above 0 dBFS.
        let hot = processed(sine(1_000, amplitude: 1.5, seconds: 0.5), clarity: false)
        let peak = hot.reduce(into: Float(0)) { $0 = max($0, abs($1)) }
        expect(peak <= 1.0 && peak >= 0.89, "voice chain: limiter caps at -1 dBFS (peak \(peak))")
    }

    // Makeup gain: RMS target, capped by the measured peak.
    expectClose(Double(VoiceChain.makeupGainDB(rmsDB: -40, peakDB: -10)), 9, tolerance: 0.01, "gain: peak caps the boost")
    expectClose(Double(VoiceChain.makeupGainDB(rmsDB: -40, peakDB: nil)), 18, tolerance: 0.01, "gain: max boost clamp")
    expectClose(Double(VoiceChain.makeupGainDB(rmsDB: -10, peakDB: -3)), -10, tolerance: 0.01, "gain: loud take attenuated")
    expectEqual(VoiceChain.makeupGainDB(rmsDB: nil, peakDB: nil), 0, "gain: no stats leaves the level alone")

    // MARK: Voice track (mono, same pass, beside the stereo mix)

    do {
        let dir = try makeTempDir("mix-voice")
        defer { try? FileManager.default.removeItem(at: dir) }
        let desktop = dir.appendingPathComponent(RecordingFiles.desktop)
        let mic = dir.appendingPathComponent(RecordingFiles.mic)
        let output = dir.appendingPathComponent(RecordingFiles.mix)
        let voice = dir.appendingPathComponent(RecordingFiles.voice)

        try writeSineCAF(to: desktop, seconds: 0.5, sampleRate: 48_000, amplitude: 0.3)
        try writeSineCAF(to: mic, seconds: 0.5, sampleRate: 48_000, amplitude: 0.1)
        try StereoMixer().mix(
            desktopURL: desktop, micURL: mic,
            desktopResult: CaptureResult(firstHostTime: 100, sampleRate: 48_000, frameCount: 24_000,
                                         rmsDB: -16, peakDB: -6),
            micResult: CaptureResult(firstHostTime: 100, sampleRate: 48_000, frameCount: 24_000,
                                     rmsDB: -30, peakDB: -20),
            outputURL: output, voiceTrackURL: voice, options: AudioMixOptions()
        )

        expect(FileManager.default.fileExists(atPath: voice.path), "voice track written")
        let voiceFile = try AVAudioFile(forReading: voice)
        expectEqual(Int(voiceFile.processingFormat.channelCount), 1, "voice track is mono")
        expectClose(Double(voiceFile.length), 24_000, tolerance: 4_096, "voice track spans the take")

        let stereoFile = try AVAudioFile(forReading: output)
        expectEqual(Int(stereoFile.processingFormat.channelCount), 2, "stereo mix still stereo")
        expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("voice-partial.m4a").path),
               "no partial voice file left")

        // Level matching: the mic was -30 dB RMS, so it should come out clearly louder.
        let stereo = AVAudioPCMBuffer(pcmFormat: stereoFile.processingFormat,
                                      frameCapacity: AVAudioFrameCount(stereoFile.length))!
        try stereoFile.read(into: stereo)
        var micPeak: Float = 0
        let right = stereo.floatChannelData![1]
        for index in 0..<Int(stereo.frameLength) { micPeak = max(micPeak, abs(right[index])) }
        expect(micPeak > 0.25, "mic channel level-matched up (peak \(micPeak))")
        expect(micPeak <= 1.0, "mic channel does not clip")
    }

    // No mic → no voice track, and the desktop is still centered.
    do {
        let dir = try makeTempDir("mix-voice-none")
        defer { try? FileManager.default.removeItem(at: dir) }
        let desktop = dir.appendingPathComponent(RecordingFiles.desktop)
        let output = dir.appendingPathComponent(RecordingFiles.mix)
        let voice = dir.appendingPathComponent(RecordingFiles.voice)
        try writeSineCAF(to: desktop, seconds: 0.3, sampleRate: 48_000, amplitude: 0.3)
        try StereoMixer().mix(
            desktopURL: desktop, micURL: dir.appendingPathComponent("nope.caf"),
            desktopResult: CaptureResult(), micResult: CaptureResult(),
            outputURL: output, voiceTrackURL: voice, options: AudioMixOptions()
        )
        expect(!FileManager.default.fileExists(atPath: voice.path), "no voice track without a mic")
    }


    #if DEBUG
    // MARK: LevelStats (what the captures hand to the mixer)

    do {
        var stats = LevelStats()
        let samples: [Float] = [0.5, -0.5, 0.5, -0.5]
        samples.withUnsafeBufferPointer { buffer in
            stats.add(buffer.baseAddress!, count: buffer.count)
        }
        expectClose(Double(stats.rmsDB ?? 0), -6.02, tolerance: 0.05, "level stats: RMS in dBFS")
        expectClose(Double(stats.peakDB ?? 0), -6.02, tolerance: 0.05, "level stats: peak in dBFS")
        stats.reset()
        expect(stats.rmsDB == nil && stats.peakDB == nil, "level stats: reset clears the measurement")
    }
    #endif

}

/// Write a mono float CAF containing a 440 Hz sine.
func writeSineCAF(to url: URL, seconds: Double, sampleRate: Double, amplitude: Float) throws {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let total = Int(seconds * sampleRate)
    let chunk = 8_192
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk))!
    var written = 0
    while written < total {
        let n = min(chunk, total - written)
        buffer.frameLength = AVAudioFrameCount(n)
        let ptr = buffer.floatChannelData![0]
        for i in 0..<n {
            ptr[i] = amplitude * sin(2 * .pi * 440 * Float(written + i) / Float(sampleRate))
        }
        try file.write(from: buffer)
        written += n
    }

    // MARK: Downmix (the realtime path)

    #if DEBUG
    do {
        // Planar: one buffer per channel, averaged.
        let left: [Float] = [1, 1, 0.5, -1]
        let right: [Float] = [-1, -1, 0.5, 1]
        var planar = [Float](repeating: 99, count: 4)
        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                let list = AudioBufferList.allocate(maximumBuffers: 2)
                defer { free(list.unsafeMutablePointer) }
                list[0] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(left.count * MemoryLayout<Float>.stride),
                    mData: UnsafeMutableRawPointer(mutating: leftBuffer.baseAddress)
                )
                list[1] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(right.count * MemoryLayout<Float>.stride),
                    mData: UnsafeMutableRawPointer(mutating: rightBuffer.baseAddress)
                )
                planar.withUnsafeMutableBufferPointer { out in
                    Downmix.toMono(buffers: list, frames: 4, into: out.baseAddress!)
                }
            }
        }
        expectEqual(planar, [0, 0, 0.5, 0], "downmix: planar buffers average")

        // Interleaved: L R L R, averaged per frame.
        let interleaved: [Float] = [1, -1, 0.5, -0.5, -0.5, 0.5]
        var mono = [Float](repeating: 99, count: 3)
        interleaved.withUnsafeBufferPointer { source in
            mono.withUnsafeMutableBufferPointer { out in
                Downmix.interleavedToMono(source.baseAddress!, channelCount: 2, frames: 3, into: out.baseAddress!)
            }
        }
        expectEqual(mono, [0, 0, 0], "downmix: interleaved average")
    }
    #endif


}
