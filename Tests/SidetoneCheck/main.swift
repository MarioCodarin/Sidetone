import Foundation
import AVFoundation
import SidetoneCore
import Darwin

// Tiny assertion harness — CLT has no XCTest / Swift Testing macros.
private var passed = 0
private var failed = 0

private func expect(_ cond: Bool, _ name: String) {
    if cond {
        passed += 1
        print("ok   \(name)")
    } else {
        failed += 1
        print("FAIL \(name)")
    }
}

private func expectEqual<T: Equatable>(_ got: T, _ want: T, _ name: String) {
    expect(got == want, "\(name) (got \(got), want \(want))")
}

// MARK: - Meeting.sanitize

expectEqual(Meeting.sanitize("Q3/Plan: Review?"), "Q3Plan-Review", "sanitize illegal chars")
expectEqual(Meeting.sanitize("  Weekly   Sync  "), "Weekly-Sync", "sanitize whitespace")
expectEqual(Meeting.sanitize(String(repeating: "a", count: 60)).count, 40, "sanitize cap 40")
expectEqual(Meeting.sanitize(""), "meeting", "sanitize empty")
expectEqual(Meeting.sanitize("///"), "meeting", "sanitize only illegal")
expectEqual(Meeting.sanitize("..."), "meeting", "sanitize only dots")
expectEqual(Meeting.sanitize("-.hidden"), "hidden", "sanitize leading dot/dash")

// MARK: - meterLevel

expectEqual(meterLevel(fromDB: -80), 0, "meter -80 → 0")
expectEqual(meterLevel(fromDB: 0), 1, "meter 0 → 1")
expectEqual(meterLevel(fromDB: -40), 0.5, "meter -40 → 0.5")
expectEqual(meterLevel(fromDB: -120), 0, "meter clamp low")
expectEqual(meterLevel(fromDB: 12), 1, "meter clamp high")

// MARK: - FloatRingBuffer

do {
    let ring = FloatRingBuffer(capacityFrames: 16)
    let src: [Float] = [1, 2, 3, 4, 5]
    src.withUnsafeBufferPointer { expect(ring.write($0.baseAddress!, count: 5), "ring write") }
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

// MARK: - RMSMeter

do {
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256)!
    buffer.frameLength = 256
    expectEqual(RMSMeter.dBFS(buffer), RMSMeter.floorDB, "RMS silence is floor")
}

do {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false
    )!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256)!
    buffer.frameLength = 256
    let ptr = buffer.floatChannelData![0]
    for i in 0..<256 { ptr[i] = 1.0 }
    let db = RMSMeter.dBFS(buffer)
    expect(db > -1 && db <= 0, "RMS full-scale ~ 0 dBFS (got \(db))")
}

// MARK: - SilenceMonitor

do {
    var fires = 0
    let monitor = SilenceMonitor(
        thresholdDB: -50, timeout: 0.2, pollInterval: 0.05,
        onTimeout: { fires += 1 }
    )
    monitor.start()
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    monitor.stop()
    expectEqual(fires, 1, "silence fires once when never loud")
}

do {
    var fires = 0
    let monitor = SilenceMonitor(
        thresholdDB: -50, timeout: 0.25, pollInterval: 0.05,
        onTimeout: { fires += 1 }
    )
    monitor.start()
    RunLoop.main.run(until: Date().addingTimeInterval(0.12))
    monitor.noteLevel(-10)
    RunLoop.main.run(until: Date().addingTimeInterval(0.12))
    monitor.stop()
    expectEqual(fires, 0, "loud sample resets silence clock")
}

// MARK: - RecordingsLibrary

do {
    let (date, title) = RecordingsLibrary.parseFolderName("2026-9-21-1721-RdB")
    expectEqual(title, "RdB", "parse title RdB")
    expect(date != nil, "parse date present")
    if let date {
        let comps = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        expectEqual(comps.year, 2026, "parse year")
        expectEqual(comps.month, 9, "parse month")
        expectEqual(comps.day, 21, "parse day")
        expectEqual(comps.hour, 17, "parse hour")
        expectEqual(comps.minute, 21, "parse minute")
    }
}

do {
    let (_, title) = RecordingsLibrary.parseFolderName("2026-9-21-1721-Meet-2")
    expectEqual(title, "Meet", "parse strips collision suffix")
}

do {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sidetone-lib-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("2026-9-21-1721-RdB", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: folder.appendingPathComponent("audio.m4a").path, contents: Data([0]))
    FileManager.default.createFile(atPath: root.appendingPathComponent("notes.txt").path, contents: Data([1]))
    let entries = RecordingsLibrary.recent(limit: 10, root: root)
    expectEqual(entries.count, 1, "recent count")
    expectEqual(entries.first?.title, "RdB", "recent title")
    expect(entries.first?.audioURL != nil, "recent has audio")
} catch {
    expect(false, "recent library threw \(error)")
}

// MARK: - RecordingSession

do {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("sidetone-sess-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let first = try RecordingSession.create(now: now, meetingTitle: "Standup", recordingsRoot: root)
    let second = try RecordingSession.create(now: now, meetingTitle: "Standup", recordingsRoot: root)
    expect(first.folderURL.lastPathComponent.contains("Standup"), "session folder named")
    expect(second.folderURL.lastPathComponent.hasSuffix("-2"), "session collision suffix")
    expectEqual(first.desktopURL.lastPathComponent, "desktop.caf", "session desktop.caf")
    expectEqual(first.micURL.lastPathComponent, "mic.caf", "session mic.caf")
    expectEqual(first.outputURL.lastPathComponent, "audio.m4a", "session audio.m4a")
    expect(FileManager.default.fileExists(atPath: first.folderURL.path), "session first exists")
    expect(FileManager.default.fileExists(atPath: second.folderURL.path), "session second exists")
} catch {
    expect(false, "session create threw \(error)")
}

// MARK: - StereoMixer

do {
    let leads = StereoMixer.leadingSilenceFrames(desktopHostTime: nil, micHostTime: nil)
    expectEqual(leads.desktop, 0, "align nil desktop")
    expectEqual(leads.mic, 0, "align nil mic")
}
do {
    let leads = StereoMixer.leadingSilenceFrames(desktopHostTime: 42, micHostTime: 42)
    expectEqual(leads.desktop, 0, "align equal desktop")
    expectEqual(leads.mic, 0, "align equal mic")
}
expectEqual(StereoMixer.framesForNanos(1_000_000_000), 48_000, "1s → 48000 frames")
expectEqual(StereoMixer.channel(from: [1, 2], leadingSilence: 2), [0, 0, 1, 2], "channel prepend")
expectEqual(StereoMixer.channel(from: nil, leadingSilence: 3), [0, 0, 0], "channel nil silence")

do {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("sidetone-mix-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let desktop = dir.appendingPathComponent("desktop.caf")
    let mic = dir.appendingPathComponent("mic.caf")
    let output = dir.appendingPathComponent("audio.m4a")

    func writeMonoCAF(to url: URL, amplitude: Float) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false
        )!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames: AVAudioFrameCount = 4800
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let ptr = buffer.floatChannelData![0]
        if amplitude == 0 {
            for i in 0..<Int(frames) { ptr[i] = 0 }
        } else {
            let freq: Float = 440
            for i in 0..<Int(frames) {
                ptr[i] = amplitude * sin(2 * .pi * freq * Float(i) / 48_000)
            }
        }
        try file.write(from: buffer)
    }

    try writeMonoCAF(to: desktop, amplitude: 0.5)
    try writeMonoCAF(to: mic, amplitude: 0)
    try StereoMixer.mix(
        desktopURL: desktop,
        micURL: mic,
        desktopResult: CaptureResult(firstHostTime: 1, sampleRate: 48_000, frameCount: 4800),
        micResult: CaptureResult(firstHostTime: 1, sampleRate: 48_000, frameCount: 4800),
        outputURL: output
    )
    let file = try AVAudioFile(forReading: output)
    expectEqual(Int(file.processingFormat.channelCount), 2, "mix is stereo")
    let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat,
        frameCapacity: AVAudioFrameCount(file.length)
    )!
    try file.read(into: buffer)
    func rms(_ ch: Int) -> Float {
        guard let data = buffer.floatChannelData else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        let ptr = data[ch]
        for i in 0..<n { sum += ptr[i] * ptr[i] }
        return sqrt(sum / Float(n))
    }
    let left = rms(0)
    let right = rms(1)
    expect(left > 0.05, "mix left has energy (got \(left))")
    expect(left > right * 8, "mix left >> right (L \(left) R \(right))")
} catch {
    expect(false, "mix integration threw \(error)")
}

// MARK: - Preferences (isolated suite)

do {
    let suiteName = "sidetone.prefs.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: suiteName)!
    suite.removePersistentDomain(forName: suiteName)
    let previous = Preferences.defaults
    Preferences.defaults = suite
    defer {
        Preferences.defaults = previous
        suite.removePersistentDomain(forName: suiteName)
    }
    expectEqual(Preferences.silenceTimeout, 300, "prefs default timeout")
    expectEqual(Preferences.silenceAutoStop, true, "prefs default autostop")
    expectEqual(Preferences.silenceThresholdDB, -50, "prefs default threshold")
    Preferences.silenceTimeout = 120
    Preferences.silenceAutoStop = false
    Preferences.silenceThresholdDB = -40
    expectEqual(Preferences.silenceTimeout, 120, "prefs timeout round-trip")
    expectEqual(Preferences.silenceAutoStop, false, "prefs autostop round-trip")
    expectEqual(Preferences.silenceThresholdDB, -40, "prefs threshold round-trip")
}

print("—")
print("\(passed) passed, \(failed) failed")
if failed > 0 {
    exit(1)
}
