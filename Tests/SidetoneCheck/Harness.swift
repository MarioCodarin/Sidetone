import Foundation

// Tiny assertion harness — Command Line Tools ship neither XCTest nor Swift Testing macros.

nonisolated(unsafe) var passed = 0
nonisolated(unsafe) var failed = 0

func expect(_ cond: Bool, _ name: String) {
    if cond {
        passed += 1
        print("ok   \(name)")
    } else {
        failed += 1
        print("FAIL \(name)")
    }
}

func expectEqual<T: Equatable>(_ got: T, _ want: T, _ name: String) {
    expect(got == want, "\(name) (got \(got), want \(want))")
}

func expectClose(_ got: Double, _ want: Double, tolerance: Double, _ name: String) {
    expect(abs(got - want) <= tolerance, "\(name) (got \(got), want \(want) ± \(tolerance))")
}

/// Run the main run loop (timers, main-queue hops, main-actor tasks) for `seconds`.
func pump(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// Pump the run loop until `condition` holds or `timeout` elapses. Returns whether it held.
@discardableResult
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        pump(0.02)
    }
    return condition()
}

/// A fresh temporary directory, removed by the caller with `defer`.
func makeTempDir(_ label: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sidetone-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
