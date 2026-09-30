import Foundation
import AVFoundation

/// Streams a raw mono CAF as 48 kHz mono Float32, a few thousand frames at a time, so mixing a
/// multi-hour recording needs kilobytes of memory instead of gigabytes.
///
/// Resampling uses one `AVAudioConverter` for the whole file (its filter state carries across
/// chunks, so there are no seams). Returns `nil` from `init` if the file is missing, unreadable
/// or empty — the caller then treats that channel as silence.
final class MonoSource {

    private let file: AVAudioFile
    private let inputBuffer: AVAudioPCMBuffer
    private let converter: AVAudioConverter?
    private let outputBuffer: AVAudioPCMBuffer

    /// Converted samples not yet handed out.
    private var pending: [Float] = []
    private var pendingHead = 0
    private var inputExhausted = false
    private var flushed = false

    private static let readFrames: AVAudioFrameCount = 16_384

    init?(url: URL, outputFormat: AVAudioFormat) {
        guard FileManager.default.fileExists(atPath: url.path),
              let file = try? AVAudioFile(forReading: url),
              file.length > 0, file.processingFormat.sampleRate > 0 else { return nil }

        let inFormat = file.processingFormat
        guard let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: Self.readFrames) else { return nil }

        let needsConversion = inFormat.sampleRate != outputFormat.sampleRate
            || inFormat.channelCount != outputFormat.channelCount
            || inFormat.commonFormat != outputFormat.commonFormat
        if needsConversion {
            guard let converter = AVAudioConverter(from: inFormat, to: outputFormat) else { return nil }
            self.converter = converter
        } else {
            self.converter = nil
        }

        let ratio = outputFormat.sampleRate / inFormat.sampleRate
        let outCapacity = AVAudioFrameCount((Double(Self.readFrames) * ratio).rounded(.up)) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outCapacity) else { return nil }

        self.file = file
        self.inputBuffer = input
        self.outputBuffer = output
    }

    /// Fill `destination` with up to `count` frames. Returns how many were produced;
    /// fewer than `count` (including 0) means the source has ended.
    func read(into destination: UnsafeMutablePointer<Float>, count: Int) -> Int {
        var produced = 0
        while produced < count {
            if pendingHead < pending.count {
                let take = min(count - produced, pending.count - pendingHead)
                pending.withUnsafeBufferPointer { src in
                    (destination + produced).update(from: src.baseAddress! + pendingHead, count: take)
                }
                pendingHead += take
                produced += take
                continue
            }
            guard refill() else { break }
        }
        return produced
    }

    /// Decode + convert the next chunk into `pending`. Returns false once nothing more can be produced.
    private func refill() -> Bool {
        pending.removeAll(keepingCapacity: true)
        pendingHead = 0

        while pending.isEmpty {
            if !inputExhausted {
                inputBuffer.frameLength = 0
                do {
                    try file.read(into: inputBuffer, frameCount: Self.readFrames)
                } catch {
                    inputExhausted = true
                }
                if inputBuffer.frameLength == 0 { inputExhausted = true }
            }

            guard let converter else {
                if inputBuffer.frameLength == 0 { return false }
                append(inputBuffer)
                inputBuffer.frameLength = 0
                continue
            }

            if inputExhausted && flushed { return false }

            var supplied = false
            let hasInput = inputBuffer.frameLength > 0
            var convertError: NSError?
            outputBuffer.frameLength = 0
            let status = converter.convert(to: outputBuffer, error: &convertError) { [inputBuffer, inputExhausted] _, inputStatus in
                if supplied || !hasInput {
                    inputStatus.pointee = inputExhausted ? .endOfStream : .noDataNow
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return inputBuffer
            }
            if inputExhausted { flushed = true }
            if status == .error || convertError != nil { return false }
            append(outputBuffer)
            inputBuffer.frameLength = 0
            if inputExhausted && pending.isEmpty { return false }
        }
        return true
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0, let data = buffer.floatChannelData else { return }
        pending.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }
}
