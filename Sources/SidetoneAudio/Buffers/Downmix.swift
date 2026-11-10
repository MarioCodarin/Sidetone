import Foundation
import Accelerate
import AudioToolbox

/// Channel averaging, shared by both captures and the mixer. Allocation-free, so it is
/// safe on realtime threads.
enum Downmix {

    /// Average `channelCount` planar channels into `destination`, reading `frames` samples
    /// starting `offset` samples into each channel. `destination` must not alias any input.
    static func toMono(
        channels: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        offset: Int = 0,
        frames: Int,
        into destination: UnsafeMutablePointer<Float>
    ) {
        guard frames > 0, channelCount > 0 else { return }
        let n = vDSP_Length(frames)
        memcpy(destination, channels[0] + offset, frames * MemoryLayout<Float>.stride)
        guard channelCount > 1 else { return }
        for ch in 1..<channelCount {
            vDSP_vadd(destination, 1, channels[ch] + offset, 1, destination, 1, n)
        }
        var scale = 1.0 / Float(channelCount)
        vDSP_vsmul(destination, 1, &scale, destination, 1, n)
    }

    /// Same, straight from an `AudioBufferList` (one planar buffer per channel), so the
    /// realtime callback never has to build an array of channel pointers.
    static func toMono(
        buffers: UnsafeMutableAudioBufferListPointer,
        offset: Int = 0,
        frames: Int,
        into destination: UnsafeMutablePointer<Float>
    ) {
        guard frames > 0, let first = buffers.first, let firstData = first.mData else { return }
        let firstSamples = firstData.assumingMemoryBound(to: Float.self)
        guard buffers.count > 1 else {
            memcpy(destination, firstSamples + offset, frames * MemoryLayout<Float>.stride)
            return
        }
        memcpy(destination, firstSamples + offset, frames * MemoryLayout<Float>.stride)
        let n = vDSP_Length(frames)
        for index in 1..<buffers.count {
            guard let data = buffers[index].mData else { continue }
            vDSP_vadd(destination, 1, data.assumingMemoryBound(to: Float.self) + offset, 1, destination, 1, n)
        }
        var scale = 1.0 / Float(buffers.count)
        vDSP_vsmul(destination, 1, &scale, destination, 1, n)
    }

    /// Average an interleaved buffer (`channelCount` floats per frame) into mono.
    /// `destination` must not alias `samples`.
    static func interleavedToMono(
        _ samples: UnsafePointer<Float>,
        channelCount: Int,
        frames: Int,
        into destination: UnsafeMutablePointer<Float>
    ) {
        guard frames > 0, channelCount > 0 else { return }
        let n = vDSP_Length(frames)
        var zero: Float = 0
        vDSP_vfill(&zero, destination, 1, n)
        guard channelCount > 1 else {
            memcpy(destination, samples, frames * MemoryLayout<Float>.stride)
            return
        }
        for channel in 0..<channelCount {
            vDSP_vadd(destination, 1, samples + channel, vDSP_Stride(channelCount), destination, 1, n)
        }
        var scale = 1.0 / Float(channelCount)
        vDSP_vsmul(destination, 1, &scale, destination, 1, n)
    }
}
