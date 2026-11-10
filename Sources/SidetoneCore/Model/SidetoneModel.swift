import Foundation
import Observation

/// The app's single source of truth: recorder state machine, meters, meetings, library.
///
/// `@MainActor` and `@Observable`: SwiftUI reads it directly. Audio callbacks arrive on
/// audio threads and are collapsed by `MeterBridge` before touching main. All I/O goes
/// through `SidetoneDependencies`, so nothing here imports AppKit, AVFoundation or EventKit.
@MainActor
@Observable
public final class SidetoneModel {

    // MARK: - Observable UI state

    public private(set) var state: RecorderState = .idle
    /// 0…1 meter for the desktop channel (LEFT / "Them").
    public private(set) var desktopLevel: Float = 0
    /// 0…1 meter for the mic channel (RIGHT / "You").
    public private(set) var micLevel: Float = 0
    /// Rolling levels for the panel waveform.
    public let waveform = WaveformData()
    public private(set) var meetings: [Meeting] = []
    /// Time actually recorded: excludes paused time.
    public private(set) var elapsed: TimeInterval = 0
    /// Latest message for the header; clears itself after a few seconds.
    public private(set) var status: StatusMessage?
    public private(set) var recentRecordings: [RecordingEntry] = []
    /// Number of mixes currently running in the background.
    public private(set) var mixesInFlight = 0
    /// Meeting this capture is tagged with. Nil for an ad-hoc recording, and whenever idle.
    public private(set) var recordingTitle: String?
    /// Microphone permission, kept current for setup / Settings.
    public private(set) var microphonePermission: PermissionStatus = .notDetermined
    /// Calendar permission, kept current for setup / Settings.
    public private(set) var calendarPermission: PermissionStatus = .notDetermined
    /// False until the first-run setup is finished or skipped.
    public private(set) var isSetupComplete: Bool
    /// Whether the running capture opened the mic (the preference can change mid-recording).
    public private(set) var sessionUsesMic = false

    private var permissionIssueSet: Set<PermissionIssue> = []

    /// Permissions the user still has to grant, in a stable order.
    public var permissionIssues: [PermissionIssue] {
        PermissionIssue.allCases.filter { permissionIssueSet.contains($0) }
    }

    /// Where recordings live right now (the user's choice, or `~/Documents/Recordings`).
    public var recordingsRoot: URL {
        RecordingsLocation.currentRoot(override: deps.recordingsRoot)
    }

    /// Tilde-abbreviated folder for the UI.
    public var recordingsFolderDisplay: String {
        RecordingsLocation.displayPath(for: recordingsRoot)
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
    /// Whether new recordings include the microphone. Off = desktop audio only, the mic is never opened.
    public var recordMicrophone: Bool = true {
        didSet { Preferences.recordMicrophone = recordMicrophone }
    }

    // MARK: - Internals (not observation-tracked)

    @ObservationIgnored private let deps: SidetoneDependencies
    @ObservationIgnored private var currentSession: RecordingSession?
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
    @ObservationIgnored private var meterBridge: MeterBridge?
    /// Loudest mic buffer of the running capture, to flag a mic that recorded only silence.
    @ObservationIgnored private var micPeakDB: Float = -.infinity
    private static let silentMicPeakDB: Float = -45

    private static let recentLimit = 4

    public init(dependencies: SidetoneDependencies) {
        self.deps = dependencies
        self.isSetupComplete = Preferences.didCompleteSetup
    }

    // MARK: - Lifecycle

    /// One-time setup at app launch: load preferences, read permission state, wire callbacks.
    /// Nothing here prompts — the first-run setup (or the first record) asks.
    public func launch() {
        guard !didLaunch else { return }
        didLaunch = true

        loadPreferences()
        refreshPermissionStatus()
        refreshRecordings()
        Log.app.notice("launched \(AppInfo.name, privacy: .public) \(AppInfo.version, privacy: .public) (\(AppInfo.build, privacy: .public))")

        deps.meetings.onChange = { [weak self] in
            Task { @MainActor in self?.refreshMeetings() }
        }
        deps.alerts.onStopRequested = { [weak self] in
            guard let self, self.state != .idle else { return }
            self.saveAndStop(note: "Stopped from notification · ")
        }
        deps.desktop.onFatalError = { [weak self] error in
            DispatchQueue.main.async {
                Log.capture.error("desktop capture failed: \(error.localizedDescription, privacy: .public)")
                self?.post("Desktop audio error: \(error.localizedDescription)", kind: .error)
            }
        }
        deps.mic.onFatalError = { [weak self] error in
            DispatchQueue.main.async {
                Log.capture.error("mic capture failed: \(error.localizedDescription, privacy: .public)")
                self?.post("Mic error: \(error.localizedDescription)", kind: .error)
            }
        }

        if !isSetupComplete { Log.app.notice("first run: setup not completed yet") }
    }

    /// Re-read everything that can change while the panel is closed. Call when the panel opens.
    public func refresh() {
        refreshPermissionStatus()
        refreshMeetings()
        refreshRecordings()
    }

    private func loadPreferences() {
        silenceTimeout = Preferences.silenceTimeout
        silenceThresholdDB = Preferences.silenceThresholdDB
        silenceAutoStopEnabled = Preferences.silenceAutoStop
        recordMicrophone = Preferences.recordMicrophone
    }

    private func refreshPermissionStatus() {
        microphonePermission = deps.permissions.microphoneStatus()
        calendarPermission = deps.meetings.authorizationStatus()
        setIssue(.microphone, active: microphonePermission == .denied)
        setIssue(.calendar, active: calendarPermission == .denied)
    }

    // MARK: - Setup

    /// Finish (or skip) the first-run setup. Persisted, so it opens only once.
    public func completeSetup() {
        guard !isSetupComplete else { return }
        isSetupComplete = true
        Preferences.didCompleteSetup = true
        Log.app.notice("setup completed")
    }

    /// Open the setup window again from Settings.
    public func replaySetup() {
        isSetupComplete = false
        Preferences.didCompleteSetup = false
    }

    /// Ask for the microphone. Safe to call repeatedly; prompts only when undetermined.
    public func requestMicrophoneAccess() async {
        let status = await deps.permissions.requestMicrophone()
        microphonePermission = status
        setIssue(.microphone, active: status == .denied)
        Log.permissions.notice("microphone permission: \(String(describing: status), privacy: .public)")
    }

    /// Ask for calendar read access. Safe to call repeatedly.
    public func requestCalendarAccess() async {
        let granted = await deps.meetings.requestAccess()
        calendarPermission = deps.meetings.authorizationStatus()
        setIssue(.calendar, active: !granted)
        Log.permissions.notice("calendar access granted: \(granted, privacy: .public)")
        if granted { refreshMeetings() }
    }

    /// Let the user pick where takes are saved. Non-destructive: existing recordings stay put.
    public func chooseRecordingsFolder() async {
        let current = recordingsRoot
        try? FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        guard let chosen = await deps.actions.chooseFolder(startingAt: current) else { return }

        if deps.recordingsRoot != nil {
            // Preview / test rig: the injected root stays authoritative.
            Log.model.notice("folder choice ignored under an injected recordings root")
            return
        }
        let resolved = RecordingsLocation.setCustomRoot(chosen)
        Log.model.notice("recordings folder set to \(resolved.path, privacy: .public)")
        refreshRecordings()
        post("Recordings save to \(RecordingsLocation.displayPath(for: resolved))", kind: .success)
    }

    /// Go back to `~/Documents/Recordings`.
    public func useDefaultRecordingsFolder() {
        guard deps.recordingsRoot == nil else { return }
        let resolved = RecordingsLocation.setCustomRoot(nil)
        Log.model.notice("recordings folder reset to \(resolved.path, privacy: .public)")
        refreshRecordings()
    }

    // MARK: - Recording control

    public func startRecording(meeting: Meeting?) {
        guard state == .idle else { return }

        // Without the mic the recording would silently be one-sided; say so instead.
        microphonePermission = deps.permissions.microphoneStatus()
        if recordMicrophone, microphonePermission == .denied {
            setIssue(.microphone, active: true)
            post("Microphone access is off. Grant it in System Settings to record.", kind: .error)
            Log.permissions.error("record refused: microphone denied")
            return
        }

        let now = deps.now()
        let session: RecordingSession
        do {
            session = try RecordingSession.create(
                now: now, meetingTitle: meeting?.title, recordingsRoot: recordingsRoot
            )
        } catch {
            Log.model.error("could not create recording folder: \(error.localizedDescription, privacy: .public)")
            post("Could not create recording folder: \(error.localizedDescription)", kind: .error)
            return
        }

        silenceMonitor = silenceAutoStopEnabled
            ? SilenceMonitor(thresholdDB: silenceThresholdDB, timeout: silenceTimeout) { [weak self] in
                self?.saveAndStop(note: "Stopped after silence · ")
            }
            : nil

        let bridge = meterBridge ?? MeterBridge { [weak self] desktop, mic in
            self?.applyLevels(desktop: desktop, mic: mic)
        }
        meterBridge = bridge
        bridge.reset()

        // Level callbacks arrive on audio threads; the bridge coalesces them to 20 Hz on main.
        deps.desktop.onLevelDB = { [weak bridge] db in bridge?.submit(db, source: .desktop) }
        deps.mic.onLevelDB = { [weak bridge] db in bridge?.submit(db, source: .mic) }

        let useMic = recordMicrophone
        let started = Log.begin("capture start")
        do {
            try deps.desktop.start(writingTo: session.desktopURL)
            if useMic { try deps.mic.start(writingTo: session.micURL) }
        } catch {
            _ = deps.desktop.stop()
            _ = deps.mic.stop()
            try? FileManager.default.removeItem(at: session.folderURL)   // don't leave an empty folder
            silenceMonitor = nil
            bridge.reset()
            handleStartFailure(error)
            return
        }
        started.end("mic \(useMic ? "on" : "off")")

        currentSession = session
        sessionUsesMic = useMic
        micPeakDB = -.infinity
        recordingTitle = meeting?.title
        setIssue(.systemAudio, active: false)
        silenceMonitor?.start()
        waveform.reset()
        desktopLevel = 0
        micLevel = 0

        // Only alert for a meeting that hasn't ended: past meetings are listed too.
        if let meeting, meeting.end > now {
            deps.alerts.scheduleMeetingEndAlert(at: meeting.end, meetingTitle: meeting.title)
        }

        state = .recording
        clearStatus()
        startElapsedClock(at: now)
        Log.model.notice("recording started at \(session.folderURL.path, privacy: .public)")
    }

    public func togglePause() {
        switch state {
        case .recording:
            deps.desktop.setPaused(true)
            deps.mic.setPaused(true)
            silenceMonitor?.stop()
            bankElapsed(at: deps.now())
            state = .paused
            Log.model.notice("recording paused")
        case .paused:
            deps.desktop.setPaused(false)
            deps.mic.setPaused(false)
            silenceMonitor?.start()
            runStartedAt = deps.now()
            state = .recording
            Log.model.notice("recording resumed")
        case .idle:
            break
        }
    }

    /// Stop both captures and mix them in the background. A readable mix becomes a single
    /// `{name}.m4a` and the working files are deleted. They stay only when the mix fails.
    ///
    /// - Parameter note: prefix for the final "Saved …" message (e.g. why it auto-stopped).
    public func saveAndStop(note: String = "") {
        guard state != .idle, let session = currentSession else {
            resetToIdle()
            return
        }

        let desktopResult = deps.desktop.stop()
        // Never ask a mic that wasn't started for its result: it could still hold an earlier take's.
        let micResult = sessionUsesMic ? deps.mic.stop() : CaptureResult()
        let title = recordingTitle
        // A mic that was on but never rose above the noise floor is almost always a wrong/dead input.
        let micWasSilent = sessionUsesMic && micPeakDB.isFinite && micPeakDB < Self.silentMicPeakDB
        finishCaptureSession()

        // Persist alignment data before mixing so a crash mid-mix is still recoverable.
        let info = SessionInfo(
            startedAt: session.startedAt, meetingTitle: title,
            desktop: desktopResult, mic: micResult
        )
        try? info.write(toFolder: session.folderURL)
        Log.capture.notice("capture stopped: desktop \(desktopResult.frameCount, privacy: .public) frames, mic \(micResult.frameCount, privacy: .public) frames")

        let savedName = title.flatMap { $0.isEmpty ? nil : $0 } ?? "recording"
        startMix(
            desktopURL: session.desktopURL, micURL: session.micURL,
            desktopResult: desktopResult, micResult: micResult,
            outputURL: session.outputURL,
            note: micWasSilent ? note + "Mic recorded only silence · " : note,
            savedName: savedName
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
            Log.model.notice("recording discarded: \(session.folderURL.path, privacy: .public)")
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
            note: "", savedName: entry.displayTitle
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
        Log.library.debug("meetings refreshed: \(self.meetings.count, privacy: .public)")
    }

    public func refreshRecordings() {
        let root = recordingsRoot
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue {
            RecordingOutput.promoteFinishedFolders(in: root)
        }
        // The folder of the take in progress is not "recent" — it is not finished yet.
        // Compare names: the library resolves /var → /private/var, the session URL does not,
        // so URL equality would miss it.
        let activeName = currentSession?.folderURL.lastPathComponent
        recentRecordings = RecordingsLibrary.recent(limit: Self.recentLimit, root: root)
            .filter { $0.folderURL.lastPathComponent != activeName }
        Log.library.debug("recordings refreshed: \(self.recentRecordings.count, privacy: .public) in \(root.path, privacy: .public)")
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

    /// Open the recordings folder in Finder (creating it if needed).
    public func openRecordingsFolder() {
        let root = recordingsRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        deps.actions.open(root)
    }

    public func openSettings(for issue: PermissionIssue) {
        Log.permissions.notice("opening System Settings for \(issue.rawValue, privacy: .public)")
        deps.actions.openSettings(for: issue)
    }

    public func quit() {
        Log.app.notice("quit requested")
        deps.actions.quit()
    }

    // MARK: - Mixing

    private func startMix(
        desktopURL: URL, micURL: URL,
        desktopResult: CaptureResult, micResult: CaptureResult,
        outputURL: URL, note: String, savedName: String
    ) {
        // A second click on "Re-mix" while the first is still running would race on the output file.
        guard mixingOutputs.insert(outputURL).inserted else { return }

        mixesInFlight += 1
        post("Mixing…", kind: .info, persistent: true)
        let span = Log.begin("mix \(outputURL.lastPathComponent)", Log.mix)

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
                let promoted = RecordingOutput.promote(folder: outputURL.deletingLastPathComponent())
                span.end("saved \(promoted?.lastPathComponent ?? savedName)")
                self.post("\(note)Saved \(savedName)", kind: .success)
            case .failure(let error):
                Log.mix.error("mix failed (raw files kept): \(error.localizedDescription, privacy: .public)")
                self.post("Mix failed (raw files kept): \(error.localizedDescription)", kind: .error)
            }
            self.refreshRecordings()
        }
    }

    // MARK: - Helpers

    private func applyLevels(desktop: Float?, mic: Float?) {
        if let desktop {
            desktopLevel = meterLevel(fromDB: desktop)
            silenceMonitor?.noteLevel(desktop)
        }
        if let mic {
            micLevel = meterLevel(fromDB: mic)
            micPeakDB = max(micPeakDB, mic)
            silenceMonitor?.noteLevel(mic)
        }
        waveform.append(
            desktop: desktop.map(meterLevel(fromDB:)),
            mic: mic.map(meterLevel(fromDB:))
        )
    }

    private func handleStartFailure(_ error: Error) {
        if case CaptureError.permissionDenied(let source) = error {
            setIssue(source == .desktop ? .systemAudio : .microphone, active: true)
        }
        Log.capture.error("capture start failed: \(error.localizedDescription, privacy: .public)")
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
        switch kind {
        case .error: Log.model.error("\(text, privacy: .public)")
        case .success: Log.model.notice("\(text, privacy: .public)")
        case .info: Log.model.debug("\(text, privacy: .public)")
        }
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
        meterBridge?.reset()
        state = .idle
        desktopLevel = 0
        micLevel = 0
        waveform.reset()
        currentSession = nil
        recordingTitle = nil
        sessionUsesMic = false
    }

    private func resetToIdle() {
        finishCaptureSession()
        elapsed = 0
    }
}
