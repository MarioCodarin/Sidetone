import Foundation
import SidetoneCore

// MARK: - Fakes

/// Scripted stand-in for `SystemAudioTap` / `MicCapture`.
final class FakeCapture: AudioCapturing {
    var onLevelDB: ((Float) -> Void)?
    var onFatalError: ((Error) -> Void)?
    var startError: Error?
    var result = CaptureResult(firstHostTime: 100, sampleRate: 48_000, frameCount: 48_000)

    private(set) var startedURL: URL?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var paused = false

    func start(writingTo url: URL) throws {
        if let startError { throw startError }
        startCount += 1
        startedURL = url
        FileManager.default.createFile(atPath: url.path, contents: Data([0]))   // "raw file exists"
    }
    func setPaused(_ paused: Bool) { self.paused = paused }
    func stop() -> CaptureResult {
        stopCount += 1
        return result
    }
}

/// Records what it was asked to mix; can be held open to simulate a slow mix.
final class FakeMixer: AudioMixing, @unchecked Sendable {
    struct Call { var desktop: CaptureResult; var mic: CaptureResult; var output: URL }
    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _fail = false
    private var _gate: DispatchSemaphore?

    var calls: [Call] { lock.withLock { _calls } }
    func failNext() { lock.withLock { _fail = true } }
    /// Block mixes until `release()`.
    func hold() { lock.withLock { _gate = DispatchSemaphore(value: 0) } }
    func release() { lock.withLock { _gate }?.signal() }

    func mix(desktopURL: URL, micURL: URL, desktopResult: CaptureResult, micResult: CaptureResult, outputURL: URL) throws {
        let (gate, fail) = lock.withLock { (_gate, _fail) }
        gate?.wait()
        lock.withLock {
            _calls.append(Call(desktop: desktopResult, mic: micResult, output: outputURL))
            _fail = false
        }
        struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
        if fail { throw Boom() }
        FileManager.default.createFile(atPath: outputURL.path, contents: Data([1]))
    }
}

@MainActor
final class FakeMeetings: MeetingProviding {
    var onChange: (() -> Void)?
    var granted = true
    var list: [Meeting] = []
    func requestAccess() async -> Bool { granted }
    func meetingsAroundNow(_ now: Date) -> [Meeting] { list }
}

@MainActor
final class FakeAlerts: MeetingAlerting {
    var onStopRequested: (() -> Void)?
    private(set) var scheduled: [(end: Date, title: String)] = []
    private(set) var cancelCount = 0
    func requestAuthorization() async {}
    func scheduleMeetingEndAlert(at endDate: Date, meetingTitle: String) { scheduled.append((endDate, meetingTitle)) }
    func cancelMeetingEndAlert() { cancelCount += 1 }
}

final class FakePermissions: PermissionsProviding {
    var mic: PermissionStatus = .granted
    func microphoneStatus() -> PermissionStatus { mic }
    func requestMicrophone() async -> PermissionStatus { mic }
}

@MainActor
final class FakeActions: SystemActions {
    private(set) var opened: [URL] = []
    private(set) var settings: [PermissionIssue] = []
    private(set) var quitCount = 0
    func copyFileToPasteboard(_ url: URL) {}
    func reveal(_ url: URL) {}
    func open(_ url: URL) { opened.append(url) }
    func openSettings(for issue: PermissionIssue) { settings.append(issue) }
    func quit() { quitCount += 1 }
}

final class Clock {
    var now = Date(timeIntervalSince1970: 1_700_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
struct Rig {
    let root: URL
    let desktop: FakeCapture
    let mic: FakeCapture
    let mixer: FakeMixer
    let meetings: FakeMeetings
    let alerts: FakeAlerts
    let permissions: FakePermissions
    let actions: FakeActions
    let clock: Clock
    let model: SidetoneModel

    init(root: URL) {
        self.root = root
        // Locals first: `model` needs the same instances the rig exposes.
        let (desktop, mic, mixer, meetings, alerts, permissions, actions, clock) =
            (FakeCapture(), FakeCapture(), FakeMixer(), FakeMeetings(), FakeAlerts(), FakePermissions(), FakeActions(), Clock())
        self.desktop = desktop; self.mic = mic; self.mixer = mixer; self.meetings = meetings
        self.alerts = alerts; self.permissions = permissions; self.actions = actions; self.clock = clock
        self.model = SidetoneModel(dependencies: SidetoneDependencies(
            desktop: desktop, mic: mic, mixer: mixer, meetings: meetings, alerts: alerts,
            permissions: permissions, actions: actions, recordingsRoot: root, now: { clock.now }
        ))
    }
}

// MARK: - Checks

@MainActor
func runModelChecks() throws {

    func withRig(_ body: (Rig) throws -> Void) throws {
        let root = try makeTempDir("model")
        defer { try? FileManager.default.removeItem(at: root) }
        try body(Rig(root: root))
    }

    // Recording starts both captures inside a dated folder and reports the state.
    try withRig { rig in
        rig.model.startRecording(meeting: nil)
        expectEqual(rig.model.state, .recording, "start → recording")
        expectEqual(rig.desktop.startCount, 1, "desktop started")
        expectEqual(rig.mic.startCount, 1, "mic started")
        expectEqual(rig.desktop.startedURL?.lastPathComponent, RecordingFiles.desktop, "desktop writes desktop.caf")
        expectEqual(rig.desktop.startedURL?.deletingLastPathComponent(),
                    rig.mic.startedURL?.deletingLastPathComponent(), "both captures share one folder")
        rig.model.startRecording(meeting: nil)
        expectEqual(rig.desktop.startCount, 1, "second start while recording is ignored")
        rig.model.trashAndStop()
    }

    // Elapsed time excludes paused time.
    try withRig { rig in
        rig.model.startRecording(meeting: nil)
        rig.clock.advance(10)
        rig.model.refreshElapsed()
        expectClose(rig.model.elapsed, 10, tolerance: 0.01, "elapsed while recording")

        rig.model.togglePause()
        expectEqual(rig.model.state, .paused, "pause → paused")
        expect(rig.desktop.paused && rig.mic.paused, "pause gates both captures")
        rig.clock.advance(60)
        rig.model.refreshElapsed()
        expectClose(rig.model.elapsed, 10, tolerance: 0.01, "elapsed frozen while paused")

        rig.model.togglePause()
        expectEqual(rig.model.state, .recording, "resume → recording")
        expect(!rig.desktop.paused && !rig.mic.paused, "resume ungates both captures")
        rig.clock.advance(5)
        rig.model.refreshElapsed()
        expectClose(rig.model.elapsed, 15, tolerance: 0.01, "elapsed skips the 60 s pause")
        rig.model.trashAndStop()
    }

    // Save: stops captures, writes session.json, mixes with the captured alignment, lists the result.
    try withRig { rig in
        rig.desktop.result = CaptureResult(firstHostTime: 500, sampleRate: 44_100, frameCount: 10)
        rig.mic.result = CaptureResult(firstHostTime: 900, sampleRate: 16_000, frameCount: 20)
        rig.model.startRecording(meeting: nil)
        let folder = rig.desktop.startedURL!.deletingLastPathComponent()
        rig.model.saveAndStop()

        expectEqual(rig.model.state, .idle, "save → idle")
        expectEqual(rig.desktop.stopCount, 1, "save stops desktop")
        expectEqual(rig.mic.stopCount, 1, "save stops mic")
        expect(rig.alerts.cancelCount >= 1, "save cancels the meeting-end alert")
        let info = SessionInfo.read(fromFolder: folder)
        expectEqual(info?.desktop.firstHostTime, 500, "session.json has desktop alignment")
        expectEqual(info?.mic.sampleRate, 16_000, "session.json has mic rate")

        expect(waitUntil { rig.model.mixesInFlight == 0 && !rig.mixer.calls.isEmpty && !rig.model.recentRecordings.isEmpty },
               "mix completes and the library refreshes")
        expectEqual(rig.mixer.calls.first?.desktop.firstHostTime, 500, "mixer got the desktop result")
        expectEqual(rig.mixer.calls.first?.mic.firstHostTime, 900, "mixer got the mic result")
        expectEqual(rig.model.recentRecordings.first?.needsMix, false, "saved recording has audio")
        expectEqual(rig.model.status?.kind, .success, "success status after mix")
    }

    // Discard deletes the folder.
    try withRig { rig in
        rig.model.startRecording(meeting: nil)
        let folder = rig.desktop.startedURL!.deletingLastPathComponent()
        rig.model.trashAndStop()
        expectEqual(rig.model.state, .idle, "discard → idle")
        expect(!FileManager.default.fileExists(atPath: folder.path), "discard removes the folder")
        expectEqual(rig.mixer.calls.count, 0, "discard does not mix")
    }

    // A failed start cleans up after itself and reports permission problems.
    try withRig { rig in
        struct Boom: Error {}
        rig.mic.startError = Boom()
        rig.model.startRecording(meeting: nil)
        expectEqual(rig.model.state, .idle, "failed start stays idle")
        expectEqual(rig.desktop.stopCount, 1, "failed start stops the desktop capture that did start")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: rig.root.path)) ?? ["?"]
        expectEqual(leftovers.count, 0, "failed start leaves no empty folder")
        expectEqual(rig.model.status?.kind, .error, "failed start shows an error")

        rig.mic.startError = nil
        rig.desktop.startError = CaptureError.permissionDenied(.desktop)
        rig.model.startRecording(meeting: nil)
        expect(rig.model.permissionIssues.contains(.systemAudio), "denied system audio → permission issue")
        rig.desktop.startError = nil
        rig.model.startRecording(meeting: nil)
        expect(!rig.model.permissionIssues.contains(.systemAudio), "successful start clears the system-audio issue")
        rig.model.trashAndStop()
    }

    // Denied mic refuses to record (instead of silently recording one side).
    try withRig { rig in
        rig.permissions.mic = .denied
        rig.model.startRecording(meeting: nil)
        expectEqual(rig.model.state, .idle, "denied mic → no recording")
        expect(rig.model.permissionIssues.contains(.microphone), "denied mic → permission issue")
        rig.model.openSettings(for: .microphone)
        expectEqual(rig.actions.settings, [.microphone], "settings shortcut routed")
    }

    // Meeting-end alert: only for meetings that haven't ended.
    try withRig { rig in
        let now = rig.clock.now
        let live = Meeting(id: "1", title: "Standup", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(1_200))
        rig.model.startRecording(meeting: live)
        expectEqual(rig.alerts.scheduled.count, 1, "alert scheduled for a meeting still running")
        expect(rig.desktop.startedURL!.deletingLastPathComponent().lastPathComponent.contains("Standup"), "folder named after meeting")
        rig.model.trashAndStop()

        let over = Meeting(id: "2", title: "Old", start: now.addingTimeInterval(-3_600), end: now.addingTimeInterval(-1_800))
        rig.model.startRecording(meeting: over)
        expectEqual(rig.alerts.scheduled.count, 1, "no alert for a meeting that already ended")
        rig.model.trashAndStop()
    }

    // Notification "Stop Recording" saves; current-meeting lookup follows the date passed in.
    try withRig { rig in
        rig.model.launch()
        rig.model.startRecording(meeting: nil)
        rig.alerts.onStopRequested?()
        expectEqual(rig.model.state, .idle, "notification stop action saves and stops")

        let now = rig.clock.now
        let meeting = Meeting(id: "m", title: "Design", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1_800))
        rig.meetings.list = [meeting]
        rig.model.refresh()
        expectEqual(rig.model.meetings.count, 1, "refresh pulls meetings")
        expect(rig.model.currentMeeting(at: now) == nil, "no current meeting before it starts")
        expectEqual(rig.model.currentMeeting(at: now.addingTimeInterval(900))?.id, "m", "current meeting once started")
    }

    // Quitting mid-recording saves it and waits for the mix.
    try withRig { rig in
        rig.mixer.hold()
        rig.model.startRecording(meeting: nil)
        expect(rig.model.hasWorkInFlight, "recording counts as work in flight")
        var finished = false
        Task { @MainActor in
            await rig.model.finishAllWork()
            finished = true
        }
        pump(0.2)
        expect(!finished, "finishAllWork waits for the running mix")
        expectEqual(rig.model.state, .idle, "finishAllWork stopped the recording")
        rig.mixer.release()
        expect(waitUntil { finished }, "finishAllWork returns once mixed")
        expect(!rig.model.hasWorkInFlight, "nothing in flight afterwards")
        expectEqual(rig.mixer.calls.count, 1, "the recording was mixed before quitting")
    }

    // Re-mix rebuilds a raw-only folder using session.json, and ignores a duplicate request.
    try withRig { rig in
        let folder = rig.root.appendingPathComponent("2026-9-22-0900-Sync", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: folder.appendingPathComponent(RecordingFiles.desktop).path, contents: Data([0]))
        FileManager.default.createFile(atPath: folder.appendingPathComponent(RecordingFiles.mic).path, contents: Data([0]))
        try SessionInfo(
            startedAt: rig.clock.now, meetingTitle: "Sync",
            desktop: CaptureResult(firstHostTime: 7, sampleRate: 48_000, frameCount: 1),
            mic: CaptureResult(firstHostTime: 8, sampleRate: 48_000, frameCount: 1)
        ).write(toFolder: folder)

        rig.model.refreshRecordings()
        expectEqual(rig.model.recentRecordings.first?.needsMix, true, "raw-only recording needs a mix")

        rig.mixer.hold()
        let entry = rig.model.recentRecordings[0]
        rig.model.remix(entry)
        rig.model.remix(entry)
        rig.mixer.release()
        expect(waitUntil { rig.model.mixesInFlight == 0 && !rig.mixer.calls.isEmpty }, "re-mix completes")
        expectEqual(rig.mixer.calls.count, 1, "duplicate re-mix ignored while one is running")
        expectEqual(rig.mixer.calls.first?.desktop.firstHostTime, 7, "re-mix reuses session.json alignment")
        expectEqual(rig.model.recentRecordings.first?.needsMix, false, "re-mixed recording now has audio")
    }

    // A failed mix keeps the raw files and says so.
    try withRig { rig in
        rig.mixer.failNext()
        rig.model.startRecording(meeting: nil)
        let folder = rig.desktop.startedURL!.deletingLastPathComponent()
        rig.model.saveAndStop()
        expect(waitUntil { rig.model.status?.kind == .error }, "failed mix → error status")
        expect(rig.model.status?.text.contains("raw files kept") == true, "error mentions raw files kept")
        expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(RecordingFiles.desktop).path), "raw file still there")
    }

    // Fatal capture errors surface in the header.
    try withRig { rig in
        rig.model.launch()
        rig.mic.onFatalError?(CaptureError.failed(.mic, "device vanished"))
        expect(waitUntil { rig.model.status?.text.contains("device vanished") == true }, "fatal mic error surfaces")
    }
}
