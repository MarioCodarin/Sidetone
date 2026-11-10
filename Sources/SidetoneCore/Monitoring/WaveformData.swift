import Foundation
import Observation

/// Rolling level history for the panel's waveform, at the meter bridge's 20 Hz cadence.
///
/// Kept in its own `@Observable` object so only the waveform redraws when a level arrives,
/// not the whole panel. A few hundred bytes, and reset on every take.
@MainActor
@Observable
public final class WaveformData {
    /// Samples kept per channel (~5 s at 20 Hz).
    public static let capacity = 96

    /// 0…1, oldest first, for the desktop channel ("Them").
    public private(set) var desktop: [Float] = []
    /// 0…1, oldest first, for the mic channel ("You").
    public private(set) var mic: [Float] = []

    public init() {}

    public func append(desktop: Float?, mic: Float?) {
        if let desktop {
            Self.push(desktop, into: &self.desktop)
        } else if !self.desktop.isEmpty {
            self.desktop.append(0)
            if self.desktop.count > Self.capacity { self.desktop.removeFirst(self.desktop.count - Self.capacity) }
        }
        if let mic {
            Self.push(mic, into: &self.mic)
        } else if !self.mic.isEmpty {
            self.mic.append(0)
            if self.mic.count > Self.capacity { self.mic.removeFirst(self.mic.count - Self.capacity) }
        }
    }

    public func reset() {
        desktop.removeAll(keepingCapacity: true)
        mic.removeAll(keepingCapacity: true)
    }

    /// Normalised 0…1 levels since the last reset; used by the preview tool.
    public var isEmpty: Bool { desktop.isEmpty && mic.isEmpty }

    private static func push(_ level: Float, into samples: inout [Float]) {
        samples.append(max(0, min(1, level)))
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}
