import Foundation

/// Everything `SidetoneModel` talks to, injected so the state machine is testable
/// without hardware. `SidetoneApp`'s `AppEnvironment` builds the live set; tests build fakes.
public struct SidetoneDependencies {
    public var desktop: AudioCapturing
    public var mic: AudioCapturing
    public var mixer: AudioMixing
    public var meetings: MeetingProviding
    public var alerts: MeetingAlerting
    public var permissions: PermissionsProviding
    public var actions: SystemActions
    /// Override for tests; `nil` uses `~/Documents/Recordings`.
    public var recordingsRoot: URL?
    /// Injected clock so elapsed-time accounting is deterministic in tests.
    public var now: () -> Date

    public init(
        desktop: AudioCapturing,
        mic: AudioCapturing,
        mixer: AudioMixing,
        meetings: MeetingProviding,
        alerts: MeetingAlerting,
        permissions: PermissionsProviding,
        actions: SystemActions,
        recordingsRoot: URL? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.desktop = desktop
        self.mic = mic
        self.mixer = mixer
        self.meetings = meetings
        self.alerts = alerts
        self.permissions = permissions
        self.actions = actions
        self.recordingsRoot = recordingsRoot
        self.now = now
    }
}
