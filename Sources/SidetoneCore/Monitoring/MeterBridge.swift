import Foundation
import os

/// Collapses the audio threads' level callbacks into a single main-thread update.
///
/// A Core Audio IOProc fires every ~10 ms and the mic tap just as often. Forwarding each one
/// with `DispatchQueue.main.async` meant hundreds of main-queue hops per second, most of which
/// merely overwrote the same two floats. This bridge keeps the **peak** of each channel and
/// delivers at most one update per `interval` (20 Hz by default) — the same information the
/// meters and the silence monitor need, at a fraction of the wakeups and CPU.
public final class MeterBridge: @unchecked Sendable {

    public static let defaultInterval: TimeInterval = 0.05

    /// When no buffer arrives for this long the meters are pushed to the floor, so a stopped
    /// stream does not leave a bar stuck at its last reading. (The model zeroes them on stop.)
    private struct Pending {
        var desktop: Float = -.infinity
        var mic: Float = -.infinity
        var scheduled = false
    }

    private let pending = OSAllocatedUnfairLock(initialState: Pending())
    private let interval: TimeInterval
    private let onLevels: @MainActor (Float?, Float?) -> Void

    /// - Parameter onLevels: invoked on the main actor with each channel's peak since the last
    ///   delivery (`nil` when that channel produced nothing in the window).
    public init(
        interval: TimeInterval = MeterBridge.defaultInterval,
        onLevels: @escaping @MainActor (Float?, Float?) -> Void
    ) {
        self.interval = interval
        self.onLevels = onLevels
    }

    /// Called from any thread (normally the audio thread). Allocation-free after the first call
    /// in a window.
    public func submit(_ db: Float, source: CaptureSource) {
        let shouldSchedule = pending.withLock { state -> Bool in
            switch source {
            case .desktop: state.desktop = max(state.desktop, db)
            case .mic:     state.mic = max(state.mic, db)
            }
            guard !state.scheduled else { return false }
            state.scheduled = true
            return true
        }
        guard shouldSchedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.flush()
        }
    }

    /// Drop anything buffered (used when a capture starts or stops).
    public func reset() {
        pending.withLock { state in
            state.desktop = -.infinity
            state.mic = -.infinity
            state.scheduled = false
        }
    }

    private func flush() {
        let levels = pending.withLock { state -> (Float?, Float?) in
            let desktop = state.desktop.isFinite ? state.desktop : nil
            let mic = state.mic.isFinite ? state.mic : nil
            state.desktop = -.infinity
            state.mic = -.infinity
            state.scheduled = false
            return (desktop, mic)
        }
        guard levels.0 != nil || levels.1 != nil else { return }
        MainActor.assumeIsolated { onLevels(levels.0, levels.1) }
    }
}
