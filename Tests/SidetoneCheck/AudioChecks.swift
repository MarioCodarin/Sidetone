import Foundation
import AVFoundation
import CoreAudio
import SidetoneCore
import SidetoneAudio

/// Signal-level checks: ring buffer, meters, file writer, streaming mixer. No hardware.
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
}
