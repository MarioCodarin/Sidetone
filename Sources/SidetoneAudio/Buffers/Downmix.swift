import Foundation
import Accelerate

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
}
