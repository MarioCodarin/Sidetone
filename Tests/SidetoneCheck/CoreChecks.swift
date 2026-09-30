import Foundation
import SidetoneCore

/// Pure-domain checks: naming, meeting windowing, library parsing, session files, prefs.
func runCoreChecks() throws {

    // MARK: Meeting.sanitize

    expectEqual(Meeting.sanitize("Q3/Plan: Review?"), "Q3Plan-Review", "sanitize illegal chars")
    expectEqual(Meeting.sanitize("  Weekly   Sync  "), "Weekly-Sync", "sanitize whitespace")
    expectEqual(Meeting.sanitize(String(repeating: "a", count: 60)).count, 40, "sanitize cap 40")
    expectEqual(Meeting.sanitize(""), "meeting", "sanitize empty")
    expectEqual(Meeting.sanitize("///"), "meeting", "sanitize only illegal")
    expectEqual(Meeting.sanitize("..."), "meeting", "sanitize only dots")
    expectEqual(Meeting.sanitize("-.hidden"), "hidden", "sanitize leading dot/dash")

    // MARK: Meeting.window

    do {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func m(_ id: String, _ startMin: Double, _ endMin: Double) -> Meeting {
            Meeting(id: id, title: id, start: now.addingTimeInterval(startMin * 60), end: now.addingTimeInterval(endMin * 60))
        }
        let all = [m("p1", -100, -90), m("p2", -80, -70), m("p3", -60, -50), m("cur", -5, 25),
                   m("n1", 30, 60), m("n2", 70, 90), m("n3", 100, 120)]
        let ids = Meeting.window(around: now, from: all).map(\.id)
        expectEqual(ids, ["p2", "p3", "cur", "n1", "n2"], "window: last 2 past + current + next 2")
        expectEqual(Meeting.window(around: now, from: []).count, 0, "window: empty")
        expect(m("cur", -5, 25).isInProgress(now), "isInProgress")
        expect(m("p1", -100, -90).hasEnded(now), "hasEnded")
    }

    // MARK: meterLevel / Formatting

    expectEqual(meterLevel(fromDB: -80), 0, "meter -80 → 0")
    expectEqual(meterLevel(fromDB: 0), 1, "meter 0 → 1")
    expectEqual(meterLevel(fromDB: -40), 0.5, "meter -40 → 0.5")
    expectEqual(meterLevel(fromDB: -120), 0, "meter clamp low")
    expectEqual(meterLevel(fromDB: 12), 1, "meter clamp high")
    expectEqual(Formatting.elapsed(65), "01:05", "elapsed mm:ss")
    expectEqual(Formatting.elapsed(3725), "1:02:05", "elapsed h:mm:ss")
    expectEqual(Formatting.elapsed(-3), "00:00", "elapsed clamps negative")

    // MARK: RecordingsLibrary

    do {
        let (date, title) = RecordingsLibrary.parseFolderName("2026-9-21-1721-RdB")
        expectEqual(title, "RdB", "parse title RdB")
        expect(date != nil, "parse date present")
        if let date {
            let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: date)
            expectEqual(c.year, 2026, "parse year")
            expectEqual(c.month, 9, "parse month")
            expectEqual(c.day, 21, "parse day")
            expectEqual(c.hour, 17, "parse hour")
            expectEqual(c.minute, 21, "parse minute")
        }
        expectEqual(RecordingsLibrary.parseFolderName("2026-9-21-1721-Meet-2").1, "Meet", "parse strips collision suffix")
    }

    do {
        let root = try makeTempDir("lib")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default

        let mixed = root.appendingPathComponent("2026-9-21-1721-RdB", isDirectory: true)
        try fm.createDirectory(at: mixed, withIntermediateDirectories: true)
        fm.createFile(atPath: mixed.appendingPathComponent(RecordingFiles.mix).path, contents: Data([0]))

        let rawOnly = root.appendingPathComponent("2026-9-22-0900", isDirectory: true)
        try fm.createDirectory(at: rawOnly, withIntermediateDirectories: true)
        fm.createFile(atPath: rawOnly.appendingPathComponent(RecordingFiles.mic).path, contents: Data([0]))

        let unrelated = root.appendingPathComponent("photos", isDirectory: true)
        try fm.createDirectory(at: unrelated, withIntermediateDirectories: true)
        fm.createFile(atPath: root.appendingPathComponent("notes.txt").path, contents: Data([1]))

        let entries = RecordingsLibrary.recent(limit: 10, root: root)
        expectEqual(entries.count, 2, "library lists only recording folders")
        expectEqual(entries.first?.date != nil, true, "library entry dated")
        expect(entries.first?.needsMix == true, "newest (raw only) needsMix")
        expect(entries.last?.needsMix == false, "mixed entry does not need mix")
        expectEqual(entries.last?.title, "RdB", "library title")
        expectEqual(RecordingsLibrary.recent(limit: 1, root: root).count, 1, "library limit")
    }

    // MARK: RecordingSession + SessionInfo

    do {
        let root = try makeTempDir("sess")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try RecordingSession.create(now: now, meetingTitle: "Standup", recordingsRoot: root)
        let second = try RecordingSession.create(now: now, meetingTitle: "Standup", recordingsRoot: root)
        expect(first.folderURL.lastPathComponent.contains("Standup"), "session folder named")
        expect(second.folderURL.lastPathComponent.hasSuffix("-2"), "session collision suffix")
        expectEqual(first.desktopURL.lastPathComponent, RecordingFiles.desktop, "session desktop.caf")
        expectEqual(first.micURL.lastPathComponent, RecordingFiles.mic, "session mic.caf")
        expectEqual(first.outputURL.lastPathComponent, RecordingFiles.mix, "session audio.m4a")
        expect(FileManager.default.fileExists(atPath: first.folderURL.path), "session first exists")
        expect(FileManager.default.fileExists(atPath: second.folderURL.path), "session second exists")

        let info = SessionInfo(
            startedAt: now, meetingTitle: "Standup",
            desktop: CaptureResult(firstHostTime: 123, sampleRate: 48_000, frameCount: 9),
            mic: CaptureResult(firstHostTime: nil, sampleRate: 16_000, frameCount: 0)
        )
        try info.write(toFolder: first.folderURL)
        expectEqual(SessionInfo.read(fromFolder: first.folderURL), info, "session.json round-trip")
        expect(SessionInfo.read(fromFolder: second.folderURL) == nil, "session.json missing → nil")
    }

    // MARK: Preferences (isolated suite)

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

    // MARK: SilenceMonitor

    do {
        var fires = 0
        let monitor = SilenceMonitor(thresholdDB: -50, timeout: 0.2, pollInterval: 0.05, onTimeout: { fires += 1 })
        monitor.start()
        pump(0.4)
        monitor.stop()
        expectEqual(fires, 1, "silence fires once when never loud")
    }
    do {
        var fires = 0
        let monitor = SilenceMonitor(thresholdDB: -50, timeout: 0.25, pollInterval: 0.05, onTimeout: { fires += 1 })
        monitor.start()
        pump(0.12)
        monitor.noteLevel(-10)
        pump(0.12)
        monitor.stop()
        expectEqual(fires, 0, "loud sample resets silence clock")
    }
}
