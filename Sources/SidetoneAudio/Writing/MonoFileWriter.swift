import Foundation
import SidetoneCore
import AVFoundation
import Synchronization
import os

/// Streams a mono float capture to a CAF file **off the realtime thread**.
///
/// The audio callback (the SOLE producer) calls `write(_:count:hostTime:)`, which only
/// memcpys into a lock-free ring buffer. A dedicated background thread (the SOLE consumer)
/// drains the ring to an `AVAudioFile`. Doing the file write — or any malloc — directly in the
/// audio callback overran its deadline and tore the stream at every buffer boundary, so both
/// captures (`SystemAudioTap`, `MicCapture`) share this writer.
///
/// The file is opened at `fileSampleRate`. If the capture device later renegotiates its rate
/// (Bluetooth profile switch, output device change), call `setSourceRate(_:)` while the
/// producer is quiescent and the writer resamples on the way to disk, so the file never
/// contains frames at the wrong rate.
public final class MonoFileWriter {

    public struct Summary {
        /// mach host time of the first frame handed to `write`, if any.
        public var firstHostTime: UInt64?
        /// Frames written to the file (after any resampling).
        public var framesWritten: Int
        /// Frames dropped because the consumer fell behind (expected 0).
        public var droppedFrames: Int
    }

    /// Called on the writer thread if a disk write fails. The writer keeps draining (and discarding).
    public var onError: ((Error) -> Void)?

    public let fileSampleRate: Double

    private let ring: FloatRingBuffer
    private let fileFormat: AVAudioFormat
    private var file: AVAudioFile?

    /// 0 = unset (mach host times are never 0 in practice).
    private let firstHostTime = Atomic<UInt64>(0)
    private let framesWritten = Atomic<Int>(0)
    private let sourceRate: Atomic<Int>
    private let stopRequested = Atomic<Bool>(false)
    private let finished = DispatchSemaphore(value: 0)
    private var didFinish = false

    private static let log = Logger(subsystem: "com.mariocodarin.Sidetone", category: "MonoFileWriter")
    private static let chunkFrames = 4096

    /// - Parameters:
    ///   - url: destination CAF (Float32 mono; CAF avoids WAV's 4 GB ceiling on long meetings).
    ///   - sampleRate: the file's rate — normally the device's rate at start.
    ///   - ringSeconds: producer headroom before frames are dropped.
    public init(url: URL, sampleRate: Double, ringSeconds: Double = 4) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        ) else {
            throw CaptureError.failed(.desktop, "Could not create a mono audio format at \(Int(sampleRate)) Hz.")
        }
        fileFormat = format
        fileSampleRate = sampleRate
        sourceRate = Atomic<Int>(Int(sampleRate.rounded()))
        ring = FloatRingBuffer(capacityFrames: max(Int(sampleRate * ringSeconds), 48_000))
        // AVAudioFile flushes per write, so a crash loses at most one chunk.
        file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let thread = Thread { [unowned self] in self.drainLoop() }
        thread.name = "com.mariocodarin.Sidetone.fileWriter"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    // MARK: - Producer (realtime-safe)

    /// Copy `count` frames into the ring. No allocation, no locks, no I/O.
    /// `hostTime` is the mach host time of the first frame; the earliest non-zero one is kept.
    public func write(_ samples: UnsafePointer<Float>, count: Int, hostTime: UInt64) {
        if hostTime != 0 {
            _ = firstHostTime.compareExchange(expected: 0, desired: hostTime, ordering: .relaxed)
        }
        ring.write(samples, count: count)
    }

    // MARK: - Control

    /// Tell the writer the source now delivers `rate` Hz. Blocks until everything already queued
    /// is on disk, so the caller must have stopped the producer first (it is safe to restart
    /// only after this returns).
    public func setSourceRate(_ rate: Double) {
        let deadline = Date().addingTimeInterval(1)
        while ring.availableFrames > 0, Date() < deadline { usleep(2_000) }
        sourceRate.store(Int(rate.rounded()), ordering: .releasing)
    }

    /// Drain the ring, close the file, and report. Call once, after the producer has stopped.
    @discardableResult
    public func finish() -> Summary {
        if !didFinish {
            didFinish = true
            stopRequested.store(true, ordering: .releasing)
            finished.wait()
            file = nil    // last reference: flushes and closes
            if ring.totalDropped > 0 {
                Self.log.error("capture dropped \(self.ring.totalDropped) frames (consumer fell behind)")
            }
        }
        let first = firstHostTime.load(ordering: .relaxed)
        return Summary(
            firstHostTime: first == 0 ? nil : first,
            framesWritten: framesWritten.load(ordering: .relaxed),
            droppedFrames: ring.totalDropped
        )
    }

    // MARK: - Consumer

    private func drainLoop() {
        let chunk = Self.chunkFrames
        var currentRate = Int(fileSampleRate.rounded())
        var converter: AVAudioConverter?
        var sourceFormat = fileFormat

        guard let input = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: AVAudioFrameCount(chunk)),
              let inputData = input.floatChannelData?[0] else {
            finished.signal()
            return
        }
        var reportedError = false

        while true {
            let requested = stopRequested.load(ordering: .acquiring)

            // Pick up a source-rate change (only ever set while the ring is empty).
            let rate = sourceRate.load(ordering: .acquiring)
            if rate != currentRate {
                currentRate = rate
                if rate == Int(fileSampleRate.rounded()) {
                    converter = nil
                    sourceFormat = fileFormat
                } else if let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: Double(rate), channels: 1, interleaved: false
                ) {
                    sourceFormat = format
                    converter = AVAudioConverter(from: format, to: fileFormat)
                }
            }

            let n = ring.read(into: inputData, maxCount: chunk)
            if n > 0 {
                input.frameLength = AVAudioFrameCount(n)
                do {
                    try write(input, sourceFormat: sourceFormat, converter: converter)
                } catch where !reportedError {
                    reportedError = true
                    onError?(error)
                } catch {}
            } else if requested {
                break               // empty AND asked to stop → fully drained
            } else {
                usleep(5_000)       // the ring holds seconds of headroom
            }
        }
        finished.signal()
    }

    private func write(_ input: AVAudioPCMBuffer, sourceFormat: AVAudioFormat, converter: AVAudioConverter?) throws {
        guard let file else { return }
        guard let converter else {
            try file.write(from: input)
            framesWritten.add(Int(input.frameLength), ordering: .relaxed)
            return
        }

        // Rate differs: `input` is filled at the file's format object, so re-wrap the same samples
        // at the source rate before converting.
        guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: input.frameLength),
              let src = source.floatChannelData?[0], let dst = input.floatChannelData?[0] else { return }
        source.frameLength = input.frameLength
        src.update(from: dst, count: Int(input.frameLength))

        let ratio = fileSampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var convertError: NSError?
        converter.convert(to: output, error: &convertError) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return source
        }
        if let convertError { throw convertError }
        guard output.frameLength > 0 else { return }
        try file.write(from: output)
        framesWritten.add(Int(output.frameLength), ordering: .relaxed)
    }
}
