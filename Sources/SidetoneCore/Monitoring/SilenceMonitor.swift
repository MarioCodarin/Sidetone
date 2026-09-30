import Foundation
import os

/// Watches the audio level stream and fires `onTimeout` once the signal has stayed
/// below `thresholdDB` for `timeout` seconds continuously.
///
/// Usage by the model: `noteLevel(_:)` is fed dBFS values from BOTH the desktop tap and
/// the mic capture (after the model hops those callbacks to main). Because both sources
/// share a single `lastLoud` timestamp, "loud on either channel" naturally resets the
/// silence clock — so auto-stop only triggers when *both* channels are quiet.
///
/// Thread-safety: `noteLevel(_:)` may be called from any thread; `lastLoud` is guarded by
/// an `OSAllocatedUnfairLock`. The internal poll timer runs on the main run loop, and
/// `onTimeout` is therefore always invoked on MAIN (per the contract).
public final class SilenceMonitor {

    /// dBFS threshold above which the signal counts as "loud" (resets the silence clock).
    var thresholdDB: Float

    /// How long the signal must stay below `thresholdDB` before `onTimeout` fires.
    var timeout: TimeInterval

    /// Invoked on MAIN exactly once when the silence window elapses. The monitor stops
    /// itself first, so the timer won't fire repeatedly.
    private let onTimeout: () -> Void

    /// Guards `lastLoud` against concurrent reads/writes from arbitrary threads.
    private let lock = OSAllocatedUnfairLock(initialState: Date())

    /// Main-run-loop poll timer. Only mutated on main (start/stop are called from the
    /// @MainActor model), so no lock is needed for the timer itself.
    private var ticker: Timer?

    /// How often the silence window is evaluated. Coarse on purpose — the actual silence
    /// decision is based on wall-clock deltas from `lastLoud`, not on tick count.
    private let pollInterval: TimeInterval

    /// - Parameter onTimeout: invoked on MAIN when silence has persisted for `timeout`.
    /// - Parameter pollInterval: how often to evaluate the window. Tests pass a short
    ///   interval; production uses the 5-second default.
    public init(
        thresholdDB: Float,
        timeout: TimeInterval,
        pollInterval: TimeInterval = 5,
        onTimeout: @escaping () -> Void
    ) {
        self.thresholdDB = thresholdDB
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.onTimeout = onTimeout
    }

    /// Feed one dBFS reading. If it's above the threshold, the signal is "loud" and the
    /// silence clock resets to now. Thread-safe; cheap enough to call per buffer.
    public func noteLevel(_ db: Float) {
        guard db > thresholdDB else { return }
        let now = Date()
        lock.withLock { $0 = now }
    }

    /// Begin (or restart) the silence watch: reset the clock to now and start the poll
    /// timer on the main run loop. Safe to call again to re-arm after a pause.
    public func start() {
        // Reset the clock so a fresh window begins (e.g. after resuming from pause).
        let now = Date()
        lock.withLock { $0 = now }

        // Replace any existing timer.
        ticker?.invalidate()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common so the timer keeps firing during menu tracking / UI interaction.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Stop watching and tear down the timer. Idempotent.
    public func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - Private

    /// Poll callback (main run loop). If the silence window has elapsed, stop and notify.
    private func tick() {
        let lastLoud = lock.withLock { $0 }
        guard Date().timeIntervalSince(lastLoud) >= timeout else { return }

        // Stop first so we never fire twice, then notify. We're already on the main
        // run loop here, satisfying the "onTimeout on MAIN" contract.
        stop()
        onTimeout()
    }
}
