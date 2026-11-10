import Foundation

// Unbuffered stdout so a crash shows exactly which check was running.
setbuf(stdout, nil)

// Runner for the hardware-free checks. `swift run SidetoneCheck`
//   CoreChecks   — domain types, naming, library, prefs, silence monitor
//   AudioChecks  — ring buffer, meters, file writer, streaming mixer (real files, no devices)
//   ModelChecks  — the recorder state machine driven through fake ports

do {
    try runCoreChecks()
    try runAudioChecks()
    try MainActor.assumeIsolated { try runModelChecks() }
} catch {
    print("FAIL unexpected error: \(error)")
    failed += 1
}

print("—")
print("\(passed) passed, \(failed) failed")
if failed > 0 {
    exit(1)
}
