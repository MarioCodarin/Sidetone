import AppKit
import AVFoundation
import SwiftUI
import SidetoneCore
import SidetoneUI

// Dev tool: hosts the real panel and settings views against fixture data and screenshots just
// that window (never the whole screen) in light and dark.
//
//   swift run SidetonePreview <out-dir> [scenario ...]
//
// With no scenario names, every scenario is captured.

// MARK: - Fakes (a smaller copy of the ones in SidetoneCheck)

final class StubCapture: AudioCapturing {
    var onLevelDB: ((Float) -> Void)?
    var onFatalError: ((Error) -> Void)?
    func start(writingTo url: URL) throws { FileManager.default.createFile(atPath: url.path, contents: Data([0])) }
    func setPaused(_ paused: Bool) {}
    func stop() -> CaptureResult { CaptureResult(firstHostTime: 100, sampleRate: 48_000, frameCount: 48_000) }
}

final class StubMixer: AudioMixing, @unchecked Sendable {
    /// Blocks every mix forever, so the "Mixing…" state can be photographed.
    var hold = false
    func mix(desktopURL: URL, micURL: URL, desktopResult: CaptureResult, micResult: CaptureResult, outputURL: URL) throws {
        if hold { DispatchSemaphore(value: 0).wait() }
    }
}

@MainActor final class StubMeetings: MeetingProviding {
    var onChange: (() -> Void)?
    var granted = true
    var list: [Meeting] = []
    func requestAccess() async -> Bool { granted }
    func meetingsAroundNow(_ now: Date) -> [Meeting] { list }
}

@MainActor final class StubAlerts: MeetingAlerting {
    var onStopRequested: (() -> Void)?
    func requestAuthorization() async {}
    func scheduleMeetingEndAlert(at endDate: Date, meetingTitle: String) {}
    func cancelMeetingEndAlert() {}
}

final class StubPermissions: PermissionsProviding {
    var mic: PermissionStatus = .granted
    func microphoneStatus() -> PermissionStatus { mic }
    func requestMicrophone() async -> PermissionStatus { mic }
}

@MainActor final class StubActions: SystemActions {
    func copyFileToPasteboard(_ url: URL) {}
    func reveal(_ url: URL) {}
    func open(_ url: URL) {}
    func openSettings(for issue: PermissionIssue) {}
    func quit() {}
}

// MARK: - Scenarios

struct Scenario {
    let name: String
    let isSettings: Bool
    /// Seconds the fixture clock is advanced after recording starts.
    var recordedSeconds: TimeInterval = 0
    var meetings = false
    var recordings = 0
    var recordMeeting = false
    var pause = false
    var denyMic = false
    var denyCalendar = false
    var error: String?
    var micOff = false
    var longTitles = false
    var manyMeetings = false
    /// Stop the capture right away: "mixing" holds the mix open, "saved" lets it finish.
    var finish: Finish?
    /// Index of the recent-recording row to hover with the real pointer (nil = none).
    var hoverRow: Int?
    enum Finish { case mixing, saved }

    init(_ name: String, isSettings: Bool = false) {
        self.name = name
        self.isSettings = isSettings
    }
}

let scenarios: [Scenario] = {
    var idle = Scenario("idle"); idle.meetings = true; idle.recordings = 4
    let empty = Scenario("empty")
    var rec = Scenario("recording"); rec.meetings = true; rec.recordings = 3; rec.recordMeeting = true; rec.recordedSeconds = 754
    var paused = rec.renamed("paused"); paused.pause = true
    var adhoc = Scenario("recording-adhoc"); adhoc.recordedSeconds = 62; adhoc.recordings = 1
    var perms = Scenario("permissions"); perms.denyMic = true; perms.denyCalendar = true; perms.error = "Desktop audio error: the audio device went away."
    var micOff = Scenario("recording-mic-off"); micOff.micOff = true; micOff.recordedSeconds = 5; micOff.meetings = true
    var long = Scenario("long-titles"); long.meetings = true; long.recordings = 4; long.longTitles = true
    var many = Scenario("many-meetings"); many.meetings = true; many.manyMeetings = true; many.recordings = 4
    var mixing = Scenario("mixing"); mixing.meetings = true; mixing.recordings = 2; mixing.recordedSeconds = 90; mixing.finish = .mixing
    var saved = mixing.renamed("saved"); saved.finish = .saved
    var hover = idle.renamed("hover"); hover.hoverRow = 1
    return [idle, empty, rec, paused, adhoc, perms, micOff, long, many, mixing, saved, hover, Scenario("settings", isSettings: true)]
}()

extension Scenario {
    func renamed(_ name: String) -> Scenario {
        var copy = Scenario(name, isSettings: isSettings)
        copy.recordedSeconds = recordedSeconds; copy.meetings = meetings; copy.recordings = recordings
        copy.recordMeeting = recordMeeting; copy.pause = pause; copy.denyMic = denyMic
        copy.denyCalendar = denyCalendar; copy.error = error; copy.micOff = micOff; copy.longTitles = longTitles
        copy.manyMeetings = manyMeetings; copy.finish = finish; copy.hoverRow = hoverRow
        return copy
    }
}

// MARK: - Fixture building

/// A tiny LPCM file; `RecordingsLibrary` reads its length from the header.
func writeFakeAudio(_ url: URL, seconds: Double) {
    let rate = 1000.0
    guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
          let file = try? AVAudioFile(forWriting: url, settings: format.settings),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * rate))
    else { return }
    buffer.frameLength = buffer.frameCapacity
    try? file.write(from: buffer)
}

@MainActor
func makeModel(_ s: Scenario, root: URL) -> SidetoneModel {
    // Real time, so the panel's own clock-driven "in progress" highlight lines up with the fixtures.
    let now = Date()

    let long = s.longTitles
    let titles = long
        ? ["Quarterly business review with the EMEA partnerships and enablement teams", "1:1", "Design critique: onboarding"]
        : ["Weekly product sync", "Design review", "1:1 with Sam"]
    let meetings = StubMeetings()
    if s.meetings {
        meetings.list = [
            Meeting(id: "a", title: titles[0], start: now.addingTimeInterval(-25 * 60), end: now.addingTimeInterval(35 * 60)),
            Meeting(id: "b", title: titles[1], start: now.addingTimeInterval(80 * 60), end: now.addingTimeInterval(110 * 60)),
            Meeting(id: "c", title: titles[2], start: now.addingTimeInterval(200 * 60), end: now.addingTimeInterval(230 * 60)),
        ]
    }
    if s.manyMeetings {
        for i in 0..<9 {
            meetings.list.append(Meeting(id: "m\(i)", title: "Meeting \(i + 4)", start: now.addingTimeInterval(Double(300 + i * 70) * 60), end: now.addingTimeInterval(Double(330 + i * 70) * 60)))
        }
    }
    meetings.granted = !s.denyCalendar

    let samples: [(String, Double, Bool)] = [
        (long ? "2026-10-20-0900-Quarterly-business-review-with-the-EMEA-partnerships-team" : "2026-10-20-0930-Weekly-product-sync", 47 * 60 + 12, true),
        ("2026-10-19-1615-Design-review", 28 * 60 + 40, true),
        ("2026-10-19-1100", 6 * 60 + 3, false),
        ("2026-10-16-1000-1-on-1-with-Sam", 31 * 60, true),
    ]
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for (i, (name, seconds, finished)) in samples.enumerated() where i < s.recordings {
        if finished {
            writeFakeAudio(root.appendingPathComponent(name + ".m4a"), seconds: seconds)
        } else {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: folder.appendingPathComponent(RecordingFiles.desktop).path, contents: Data([0]))
        }
    }

    let permissions = StubPermissions()
    permissions.mic = s.denyMic ? .denied : .granted
    let desktop = StubCapture()
    let mic = StubCapture()
    let clock = Box(now)
    let mixer = StubMixer()
    mixer.hold = s.finish == .mixing
    let model = SidetoneModel(dependencies: SidetoneDependencies(
        desktop: desktop, mic: mic, mixer: mixer, meetings: meetings, alerts: StubAlerts(),
        permissions: permissions, actions: StubActions(), recordingsRoot: root, now: { clock.value }))
    model.recordMicrophone = !s.micOff
    model.launch()
    model.refresh()

    if s.recordedSeconds > 0 {
        model.startRecording(meeting: s.recordMeeting ? meetings.list.first : nil)
        clock.value = now.addingTimeInterval(s.recordedSeconds)
        model.refreshElapsed()
        desktop.onLevelDB?(-18)
        mic.onLevelDB?(s.micOff ? -90 : -32)
        if s.pause { model.togglePause() }
        if s.finish != nil { model.saveAndStop() }
    }
    if let error = s.error { desktop.onFatalError?(NSError(domain: "preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "the audio device went away."])); _ = error }
    return model
}

final class Box<T> { var value: T; init(_ v: T) { value = v } }

// MARK: - Window + capture

/// Borderless windows refuse key status by default; the real popover is key, so controls render active.
final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
func host(_ s: Scenario, model: SidetoneModel, appearance: NSAppearance.Name) -> NSWindow {
    let content: AnyView = s.isSettings
        ? AnyView(PreferencesView().environment(model))
        : AnyView(SidetonePanel().environment(model))
    let hosting = NSHostingView(rootView: content)
    hosting.layoutSubtreeIfNeeded()
    let size = hosting.fittingSize

    let window: NSWindow
    if s.isSettings {
        window = PreviewWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Sidetone Settings"
        window.contentView = hosting
    } else {
        // Approximates the MenuBarExtra popover: material background, rounded, no chrome.
        window = PreviewWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        window.contentView = effect
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
    }
    window.appearance = NSAppearance(named: appearance)
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.level = .floating
    window.setFrameOrigin(NSPoint(x: 200, y: 200))
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    return window
}

@MainActor
func pump(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

@MainActor
func run() async {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let outPath = args.first else {
        print("usage: SidetonePreview <out-dir> [scenario ...]")
        exit(2)
    }
    let outDir = URL(fileURLWithPath: outPath, isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    // `--settings-window`: open the *real* Settings window controller and wait, so its keyboard
    // handling (⌘W, Esc) can be driven from outside.
    if args.contains("--settings-window") {
        let model = makeModel(Scenario("settings", isSettings: true), root: FileManager.default.temporaryDirectory.appendingPathComponent("sidetone-preview-sw"))
        PreferencesWindowController.shared.show(model: model)
        await pump(40)
        exit(0)
    }
    let wanted = Set(args.dropFirst())
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("sidetone-preview-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: work) }

    for scenario in scenarios where wanted.isEmpty || wanted.contains(scenario.name) {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let model = makeModel(scenario, root: work.appendingPathComponent("\(scenario.name)-\(suffix)"))
            let window = host(scenario, model: model, appearance: appearance)
            await pump(0.5)   // let the model's async launch work (permissions, calendar) land
            if let hosting = window.contentView?.subviews.first as? NSHostingView<AnyView> ?? window.contentView as? NSHostingView<AnyView> {
                window.setContentSize(hosting.fittingSize)
            }
            if let row = scenario.hoverRow, let screen = NSScreen.main {
                // Recent rows sit in the lower half; walk the pointer onto the requested one.
                let frame = window.frame
                let y = screen.frame.height - (frame.minY + 110 + CGFloat(row) * 40)
                CGWarpMouseCursorPosition(CGPoint(x: frame.minX + 120, y: y))
                CGAssociateMouseAndMouseCursorPosition(1)
                let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: frame.minX + 122, y: y), mouseButton: .left)
                move?.post(tap: .cghidEventTap)
            }
            // SIDETONE_PREVIEW_HOLD=<seconds> keeps the window up so the accessibility tree can be inspected.
            if let hold = ProcessInfo.processInfo.environment["SIDETONE_PREVIEW_HOLD"].flatMap(Double.init) { await pump(hold) }
            await pump(0.5)
            let file = outDir.appendingPathComponent("\(scenario.name)-\(suffix).png")
            try? FileManager.default.removeItem(at: file)
            for attempt in 1...3 where !FileManager.default.fileExists(atPath: file.path) {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                task.arguments = ["-x", "-o", "-l", String(window.windowNumber), file.path]
                try? task.run()
                task.waitUntilExit()
                if attempt < 3, !FileManager.default.fileExists(atPath: file.path) { await pump(0.5) }
            }
            window.close()
            print("captured \(file.lastPathComponent)")
        }
    }
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in await run() }
app.run()
