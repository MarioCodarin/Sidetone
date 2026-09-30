import Foundation
import Observation

/// The app's single source of truth: recorder state machine, meters, meetings, library.
///
/// `@MainActor` and `@Observable`: SwiftUI reads it directly. Audio callbacks arrive on
/// audio threads and hop to main (`DispatchQueue.main.async`) before touching any state.
/// All I/O goes through `SidetoneDependencies`, so nothing here imports AppKit,
/// AVFoundation or EventKit.
@MainActor
@Observable
public final class SidetoneModel {

    // MARK: - Observable UI state

    public private(set) var state: RecorderState = .idle
    /// 0…1 meter for the desktop channel (LEFT / "Them").
    public private(set) var desktopLevel: Float = 0
    /// 0…1 meter for the mic channel (RIGHT / "You").
    public private(set) var micLevel: Float = 0
    public private(set) var meetings: [Meeting] = []
    /// Time actually recorded: excludes paused time.
    public private(set) var elapsed: TimeInterval = 0
    /// Latest message for the header; clears itself after a few seconds.
    public private(set) var status: StatusMessage?
    public private(set) var recentRecordings: [RecordingEntry] = []
    /// Number of mixes currently running in the background.
    public private(set) var mixesInFlight = 0
    private var permissionIssueSet: Set<PermissionIssue> = []

    /// Permissions the user has to grant, in a stable order.
    public var permissionIssues: [PermissionIssue] {
        PermissionIssue.allCases.filter { permissionIssueSet.contains($0) }
    }

    // MARK: - Persisted preferences (mirrored to UserDefaults via `Preferences`)

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

    // MARK: - Internals (not observation-tracked)

    @ObservationIgnored private let deps: SidetoneDependencies
    @ObservationIgnored private var currentSession: RecordingSession?
    @ObservationIgnored private var currentMeetingTitle: String?
    @ObservationIgnored private var silenceMonitor: SilenceMonitor?
    @ObservationIgnored private var elapsedTimer: Timer?
    /// Recorded time banked before the current run of `.recording` began.
    @ObservationIgnored private var bankedElapsed: TimeInterval = 0
    /// When the current run of `.recording` began; nil while paused/idle.
    @ObservationIgnored private var runStartedAt: Date?
    @ObservationIgnored private var statusClearTask: Task<Void, Never>?
    @ObservationIgnored private var pendingMixes: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var mixingOutputs: Set<URL> = []
    @ObservationIgnored private var didLaunch = false

    private static let recentLimit = 4

    public init(dependencies: SidetoneDependencies) {
        self.deps = dependencies
    }

    // MARK: - Lifecycle

    /// One-time setup at app launch: load preferences, request permissions, wire callbacks.
    public func launch() {
        guard !didLaunch else { return }
        didLaunch = true

        loadPreferences()
        refreshRecordings()

        Task { @MainActor in
            let status = await deps.permissions.requestMicrophone()
            setIssue(.microphone, active: status == .denied)
        }
        Task { @MainActor in
            let granted = await deps.meetings.requestAccess()
            setIssue(.calendar, active: !granted)
            refreshMeetings()
        }
        Task { @MainActor in
            await deps.alerts.requestAuthorization()
        }

        deps.meetings.onChange = { [weak self] in self?.refreshMeetings() }
        deps.alerts.onStopRequested = { [weak self] in
            guard let self, self.state != .idle else { return }
            self.saveAndStop()
        }
        deps.desktop.onFatalError = { [weak self] error in
            DispatchQueue.main.async {
                self?.post("Desktop audio error: \(error.localizedDescription)", kind: .error)
            }
        }
        deps.mic.onFatalError = { [weak self] error in
            DispatchQueue.main.async {
                self?.post("Mic error: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    /// Re-read everything that can change while the panel is closed. Call when the panel opens.
    public func refresh() {
        refreshMeetings()
        refreshRecordings()
        if deps.permissions.microphoneStatus() != .notDetermined {
            setIssue(.microphone, active: deps.permissions.microphoneStatus() == .denied)
        }
        if permissionIssueSet.contains(.calendar) {
            Task { @MainActor in
                let granted = await deps.meetings.requestAccess()
                setIssue(.calendar, active: !granted)
                if granted { refreshMeetings() }
            }
        }
    }

    private func loadPreferences() {
        silenceTimeout = Preferences.silenceTimeout
        silenceThresholdDB = Preferences.silenceThresholdDB
        silenceAutoStopEnabled = Preferences.silenceAutoStop
    }

    // MARK: - Recording control

    public func startRecording(meeting: Meeting?) {
        guard state == .idle else { return }

        // Without the mic the recording would silently be one-sided; say so instead.
        if deps.permissions.microphoneStatus() == .denied {
            setIssue(.microphone, active: true)
            post("Microphone access is off. Grant it in System Settings to record.", kind: .error)
            return
        }

        let now = deps.now()
        let session: RecordingSession
        do {
            session = try RecordingSession.create(
                now: now, meetingTitle: meeting?.title, recordingsRoot: deps.recordingsRoot
            )
        } catch {
            post("Could not create recording folder: \(error.localizedDescription)", kind: .error)
            return
        }

        silenceMonitor = silenceAutoStopEnabled
            ? SilenceMonitor(thresholdDB: silenceThresholdDB, timeout: silenceTimeout) { [weak self] in
                self?.saveAndStop(note: "Stopped after silence · ")
            }
            : nil

        // Level callbacks arrive on audio threads.
        deps.desktop.onLevelDB = { [weak self] db in
            DispatchQueue.main.async { self?.noteLevel(db, source: .desktop) }
        }
        deps.mic.onLevelDB = { [weak self] db in
            DispatchQueue.main.async { self?.noteLevel(db, source: .mic) }
        }

        do {
            try deps.desktop.start(writingTo: session.desktopURL)
            try deps.mic.start(writingTo: session.micURL)
        } catch {
            _ = deps.desktop.stop()
            _ = deps.mic.stop()
            try? FileManager.default.removeItem(at: session.folderURL)   // don't leave an empty folder
            silenceMonitor = nil
            handleStartFailure(error)
            return
        }

        currentSession = session
        currentMeetingTitle = meeting?.title
        setIssue(.systemAudio, active: false)
        silenceMonitor?.start()

        // Only alert for a meeting that hasn't ended: past meetings are listed too.
        if let meeting, meeting.end > now {
            deps.alerts.scheduleMeetingEndAlert(at: meeting.end, meetingTitle: meeting.title)
        }

        state = .recording
        clearStatus()
        startElapsedClock(at: now)
    }

    public func togglePause() {
        switch state {
        case .recording:
            deps.desktop.setPaused(true)
            deps.mic.setPaused(true)
            silenceMonitor?.stop()
            bankElapsed(at: deps.now())
            state = .paused
        case .paused:
            deps.desktop.setPaused(false)
            deps.mic.setPaused(false)
            silenceMonitor?.start()
            runStartedAt = deps.now()
            state = .recording
        case .idle:
            break
        }
    }

    /// Stop both captures and mix them in the background. Raw files are always kept.
    ///
    /// - Parameter note: prefix for the final "Saved …" message (e.g. why it auto-stopped).
    public func saveAndStop(note: String = "") {
        guard state != .idle, let session = currentSession else {
            resetToIdle()
            return
        }

        let desktopResult = deps.desktop.stop()
        let micResult = deps.mic.stop()
        let title = currentMeetingTitle
        finishCaptureSession()

        // Persist alignment data before mixing so a crash mid-mix is still recoverable.
        let info = SessionInfo(
            startedAt: session.startedAt, meetingTitle: title,
            desktop: desktopResult, mic: micResult
        )
        try? info.write(toFolder: session.folderURL)

        startMix(
            desktopURL: session.desktopURL, micURL: session.micURL,
            desktopResult: desktopResult, micResult: micResult,
            outputURL: session.outputURL, note: note
        )
    }

    /// Stop and delete the in-progress recording.
    public func trashAndStop() {
        guard state != .idle else {
            resetToIdle()
            return
        }

        _ = deps.desktop.stop()
        _ = deps.mic.stop()
        if let session = currentSession {
            try? FileManager.default.removeItem(at: session.folderURL)
        }
        finishCaptureSession()
        post("Discarded", kind: .info)
        refreshRecordings()
    }

    /// Rebuild `audio.m4a` for a folder that only has raw captures (crash, quit mid-mix, failed mix).
    public func remix(_ entry: RecordingEntry) {
        let folder = entry.folderURL
        let info = SessionInfo.read(fromFolder: folder)
        startMix(
            desktopURL: folder.appendingPathComponent(RecordingFiles.desktop),
            micURL: folder.appendingPathComponent(RecordingFiles.mic),
            // Without session.json we can't align the streams; assume coincident starts.
            desktopResult: info?.desktop ?? CaptureResult(),
            micResult: info?.mic ?? CaptureResult(),
            outputURL: folder.appendingPathComponent(RecordingFiles.mix),
            note: ""
        )
    }

    // MARK: - Termination

    /// True while something would be lost (or left half-written) if the app quit right now.
    public var hasWorkInFlight: Bool {
        state != .idle || !pendingMixes.isEmpty
    }

    /// Save any active recording and wait for every mix to finish. Used before quitting.
    public func finishAllWork() async {
        if state != .idle { saveAndStop() }
        for task in Array(pendingMixes.values) {
            await task.value
        }
    }

    // MARK: - Meetings & library

    public func refreshMeetings() {
        meetings = deps.meetings.meetingsAroundNow(deps.now())
    }

    public func refreshRecordings() {
        recentRecordings = RecordingsLibrary.recent(limit: Self.recentLimit, root: deps.recordingsRoot)
    }

    /// The meeting in progress at `date`, if any. The main Record button targets it so recording
    /// during a meeting auto-tags it (folder name + end alert). Takes the date so views can pass a
    /// ticking clock instead of relying on when `meetings` was last fetched.
    public func currentMeeting(at date: Date) -> Meeting? {
        meetings.first(where: { $0.isInProgress(date) })
    }

    // MARK: - System actions

    public func copyFileToPasteboard(_ url: URL) {
        deps.actions.copyFileToPasteboard(url)
        post("Copied \(url.lastPathComponent)", kind: .success)
    }

    public func reveal(_ url: URL) {
        deps.actions.reveal(url)
    }

    public func open(_ url: URL) {
        deps.actions.open(url)
    }

    /// Open ~/Documents/Recordings in Finder (creating it if needed).
    public func openRecordingsFolder() {
        guard let root = deps.recordingsRoot ?? RecordingsLibrary.recordingsRoot() else { return }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        deps.actions.open(root)
    }

    public func openSettings(for issue: PermissionIssue) {
        deps.actions.openSettings(for: issue)
    }

    public func quit() {
        deps.actions.quit()
    }

    // MARK: - Mixing

    private func startMix(
        desktopURL: URL, micURL: URL,
        desktopResult: CaptureResult, micResult: CaptureResult,
        outputURL: URL, note: String
    ) {
        // A second click on "Re-mix" while the first is still running would race on the output file.
        guard mixingOutputs.insert(outputURL).inserted else { return }

        mixesInFlight += 1
        post("Mixing…", kind: .info, persistent: true)

        let mixer = deps.mixer
        let id = UUID()
        pendingMixes[id] = Task { [weak self] in
            let outcome: Result<Void, Error> = await Task.detached(priority: .utility) {
                Result {
                    try mixer.mix(
                        desktopURL: desktopURL, micURL: micURL,
                        desktopResult: desktopResult, micResult: micResult,
                        outputURL: outputURL
                    )
                }
            }.value

            guard let self else { return }
            self.mixingOutputs.remove(outputURL)
            self.pendingMixes[id] = nil
            self.mixesInFlight -= 1
            switch outcome {
            case .success:
                self.post("\(note)Saved \(outputURL.deletingLastPathComponent().lastPathComponent)", kind: .success)
            case .failure(let error):
                self.post("Mix failed (raw files kept): \(error.localizedDescription)", kind: .error)
            }
            self.refreshRecordings()
        }
    }

    // MARK: - Helpers

    private func noteLevel(_ db: Float, source: CaptureSource) {
        switch source {
        case .desktop: desktopLevel = meterLevel(fromDB: db)
        case .mic:     micLevel = meterLevel(fromDB: db)
        }
        silenceMonitor?.noteLevel(db)
    }

    private func handleStartFailure(_ error: Error) {
        if case CaptureError.permissionDenied(let source) = error {
            setIssue(source == .desktop ? .systemAudio : .microphone, active: true)
        }
        post("Could not start recording: \(error.localizedDescription)", kind: .error)
    }

    private func setIssue(_ issue: PermissionIssue, active: Bool) {
        if active {
            permissionIssueSet.insert(issue)
        } else {
            permissionIssueSet.remove(issue)
        }
    }

    /// Show `text` in the header. Non-persistent messages clear themselves.
    private func post(_ text: String, kind: StatusMessage.Kind, persistent: Bool = false) {
        let message = StatusMessage(text, kind: kind)
        status = message
        statusClearTask?.cancel()
        guard !persistent else { return }

        let seconds: UInt64 = kind == .error ? 12 : 6
        statusClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled, let self, self.status?.id == message.id else { return }
            self.status = nil
        }
    }

    private func clearStatus() {
        statusClearTask?.cancel()
        status = nil
    }

    // MARK: Elapsed clock

    private func startElapsedClock(at start: Date) {
        bankedElapsed = 0
        runStartedAt = start
        elapsed = 0
        elapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshElapsed() }
        }
        RunLoop.main.add(timer, forMode: .common)
        elapsedTimer = timer
    }

    /// Recompute `elapsed` from the clock. Driven by a 1 s timer; also callable directly.
    public func refreshElapsed() {
        guard let runStartedAt else { return }
        elapsed = bankedElapsed + deps.now().timeIntervalSince(runStartedAt)
    }

    private func bankElapsed(at now: Date) {
        if let runStartedAt {
            bankedElapsed += now.timeIntervalSince(runStartedAt)
        }
        runStartedAt = nil
        elapsed = bankedElapsed
    }

    /// Common teardown after captures have been stopped.
    private func finishCaptureSession() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        runStartedAt = nil
        bankedElapsed = 0
        silenceMonitor?.stop()
        silenceMonitor = nil
        deps.alerts.cancelMeetingEndAlert()
        state = .idle
        desktopLevel = 0
        micLevel = 0
        currentSession = nil
        currentMeetingTitle = nil
    }

    private func resetToIdle() {
        finishCaptureSession()
        elapsed = 0
    }
}
