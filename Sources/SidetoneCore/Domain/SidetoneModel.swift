import Foundation
import Observation
import AppKit

/// Owns every component and wires their callbacks. The model is @MainActor;
/// audio-thread callbacks hop to main via DispatchQueue.main.async before touching state.
@MainActor
@Observable
public final class SidetoneModel {

    // MARK: - Observable UI state

    public var state: RecorderState = .idle
    public var desktopLevel: Float = 0      // 0..1 meter (LEFT / desktop)
    public var micLevel: Float = 0          // 0..1 meter (RIGHT / mic)
    public var meetings: [Meeting] = []
    var currentSession: RecordingSession? = nil
    public var elapsed: TimeInterval = 0
    public var statusMessage: String? = nil

    // MARK: - Persisted preferences (mirrored to UserDefaults via Preferences)

    /// Auto-stop after this many seconds of two-channel silence.
    public var silenceTimeout: TimeInterval = 300 {
        didSet { Preferences.silenceTimeout = silenceTimeout }
    }
    /// dBFS below which a channel is considered silent.
    public var silenceThresholdDB: Float = -50 {
        didSet { Preferences.silenceThresholdDB = silenceThresholdDB }
    }
    /// Whether silence auto-stop runs at all.
    public var silenceAutoStopEnabled: Bool = true {
        didSet { Preferences.silenceAutoStop = silenceAutoStopEnabled }
    }

    /// The most recent recordings on disk (loaded at launch + after changes).
    public var recentRecordings: [RecordingEntry] = []

    // MARK: - Heavy / audio objects (not observation-tracked)

    @ObservationIgnored private let tap = SystemAudioTap()
    @ObservationIgnored private let mic = MicCapture()
    @ObservationIgnored private let calendar = CalendarAccess()
    @ObservationIgnored private let notifications = NotificationManager()
    @ObservationIgnored private var silenceMonitor: SilenceMonitor?

    @ObservationIgnored private var elapsedTimer: Timer?
    @ObservationIgnored private var recordingStartedAt: Date?

    /// The meeting (if any) the current recording is attached to.
    @ObservationIgnored private var activeMeeting: Meeting?

    /// `onAppear()` used to be hooked to the menu-bar panel `.task`, which
    /// re-ran TCC + notification requests on every open.
    @ObservationIgnored private var didSetUp = false

    public init() {}

    // MARK: - Lifecycle

    public func onAppear() {
        if didSetUp {
            refreshMeetings()
            refreshRecordings()
            return
        }
        didSetUp = true

        // Load persisted preferences first so the UI reflects them immediately.
        loadPreferences()

        // Load prior recordings from disk so they survive restarts.
        refreshRecordings()

        // Request permissions concurrently, then load meetings.
        Task { @MainActor in
            _ = await MicCapture.requestAccess()
        }
        Task { @MainActor in
            _ = await calendar.requestAccess()
            refreshMeetings()
        }
        Task { @MainActor in
            await notifications.requestAuthorization()
        }

        // Refetch meetings on calendar changes.
        calendar.onChange = { [weak self] in
            // onChange is delivered on main (CalendarAccess is @MainActor).
            self?.refreshMeetings()
        }

        // A user tapping "Stop Recording" in the meeting-end notification stops + saves.
        notifications.onStopRequested = { [weak self] in
            guard let self else { return }
            if self.state != .idle {
                self.saveAndStop()
            }
        }

        // Surface fatal capture errors to the UI.
        tap.onFatalError = { [weak self] error in
            DispatchQueue.main.async {
                self?.statusMessage = "Desktop audio error: \(error.localizedDescription)"
            }
        }
        mic.onFatalError = { [weak self] error in
            DispatchQueue.main.async {
                self?.statusMessage = "Mic error: \(error.localizedDescription)"
            }
        }
    }

    /// Pull persisted preferences into the observable properties. The `didSet`
    /// write-backs are idempotent (same value in → same value out).
    private func loadPreferences() {
        silenceTimeout = Preferences.silenceTimeout
        silenceThresholdDB = Preferences.silenceThresholdDB
        silenceAutoStopEnabled = Preferences.silenceAutoStop
    }

    // MARK: - Recording control

    public func startRecording(meeting: Meeting?) {
        guard state == .idle else { return }

        let now = Date()
        let session: RecordingSession
        do {
            session = try RecordingSession.create(now: now, meetingTitle: meeting?.title)
        } catch {
            statusMessage = "Could not create recording folder: \(error.localizedDescription)"
            return
        }
        currentSession = session
        activeMeeting = meeting

        // Silence monitor (auto-stop after prolonged silence on both channels).
        // Only armed when the user has auto-stop enabled.
        if silenceAutoStopEnabled {
            silenceMonitor = SilenceMonitor(
                thresholdDB: silenceThresholdDB,
                timeout: silenceTimeout,
                onTimeout: { [weak self] in
                    // onTimeout is invoked on MAIN per contract.
                    self?.saveAndStop()
                }
            )
        } else {
            silenceMonitor = nil
        }

        // Wire level callbacks (called on audio threads -> hop to main).
        tap.onLevelDB = { [weak self] db in
            DispatchQueue.main.async {
                guard let self else { return }
                self.desktopLevel = meterLevel(fromDB: db)
                self.silenceMonitor?.noteLevel(db)
            }
        }
        mic.onLevelDB = { [weak self] db in
            DispatchQueue.main.async {
                guard let self else { return }
                self.micLevel = meterLevel(fromDB: db)
                self.silenceMonitor?.noteLevel(db)
            }
        }

        // Start both captures.
        do {
            try tap.start(writingTo: session.desktopURL)
            try mic.start(writingTo: session.micURL)
        } catch {
            statusMessage = "Could not start capture: \(error.localizedDescription)"
            _ = tap.stop()
            _ = mic.stop()
            currentSession = nil
            silenceMonitor = nil
            return
        }

        silenceMonitor?.start()

        // Schedule a meeting-end alert when recording a known meeting.
        if let meeting {
            notifications.scheduleMeetingEndAlert(at: meeting.end, meetingTitle: meeting.title)
        }

        state = .recording
        statusMessage = nil
        startElapsedTimer(from: now)
    }

    public func togglePause() {
        switch state {
        case .recording:
            tap.setPaused(true)
            mic.setPaused(true)
            silenceMonitor?.stop()
            state = .paused
        case .paused:
            tap.setPaused(false)
            mic.setPaused(false)
            silenceMonitor?.start()
            state = .recording
        case .idle:
            break
        }
    }

    public func saveAndStop() {
        guard state != .idle, let session = currentSession else {
            resetToIdle()
            return
        }

        let desktopResult = tap.stop()
        let micResult = mic.stop()

        cancelTimersAndAlerts()
        state = .idle
        desktopLevel = 0
        micLevel = 0
        statusMessage = "Mixing…"

        // Mix off the main actor; keep raw CAFs regardless of outcome.
        let outputURL = session.outputURL
        let desktopURL = session.desktopURL
        let micURL = session.micURL
        Task.detached(priority: .utility) {
            do {
                try StereoMixer.mix(
                    desktopURL: desktopURL,
                    micURL: micURL,
                    desktopResult: desktopResult,
                    micResult: micResult,
                    outputURL: outputURL
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.statusMessage = "Saved \(outputURL.lastPathComponent)"
                    self.refreshRecordings()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.statusMessage = "Mix failed (raw files kept): \(error.localizedDescription)"
                }
            }
        }

        currentSession = nil
        activeMeeting = nil
        silenceMonitor = nil
    }

    public func trashAndStop() {
        guard state != .idle else {
            resetToIdle()
            return
        }

        _ = tap.stop()
        _ = mic.stop()

        cancelTimersAndAlerts()

        if let session = currentSession {
            try? FileManager.default.removeItem(at: session.folderURL)
        }

        state = .idle
        desktopLevel = 0
        micLevel = 0
        currentSession = nil
        activeMeeting = nil
        silenceMonitor = nil
        statusMessage = "Discarded"
        refreshRecordings()
    }

    public func refreshMeetings() {
        let now = Date()
        meetings = calendar.meetingsAroundNow(now)
    }

    /// The meeting currently in progress, if any. All-day events are already
    /// excluded from `meetings`, so this only matches timed meetings. Used as the
    /// default target for the main Record button so recording while you're in a
    /// meeting auto-tags it (folder name + end alert).
    public var currentMeeting: Meeting? {
        let now = Date()
        return meetings.first(where: { $0.isInProgress(now) })
    }

    public func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func startElapsedTimer(from start: Date) {
        recordingStartedAt = start
        elapsed = 0
        elapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let started = self.recordingStartedAt else { return }
                if self.state == .recording {
                    self.elapsed = Date().timeIntervalSince(started)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    private func cancelTimersAndAlerts() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        recordingStartedAt = nil
        silenceMonitor?.stop()
        notifications.cancelMeetingEndAlert()
    }

    private func resetToIdle() {
        cancelTimersAndAlerts()
        state = .idle
        currentSession = nil
        activeMeeting = nil
        silenceMonitor = nil
        elapsed = 0
        desktopLevel = 0
        micLevel = 0
    }

    // MARK: - Recordings library

    /// Reload the recent-recordings list from disk.
    public func refreshRecordings() {
        recentRecordings = RecordingsLibrary.recent(limit: 4)
    }

    /// Put a file on the clipboard (paste into Finder / Mail / …).
    public func copyFileToPasteboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        statusMessage = "Copied \(url.lastPathComponent)"
    }

    /// Reveal an arbitrary file/folder in Finder.
    public func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Open ~/Documents/Recordings in Finder (creating it if needed).
    public func openRecordingsFolder() {
        guard let root = RecordingsLibrary.recordingsRoot() else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }
}
