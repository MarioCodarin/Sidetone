import SidetoneCore
import SidetoneAudio
import SidetoneServices

/// Composition root: the only place that knows which concrete implementation backs each port.
@MainActor
enum AppEnvironment {
    static func makeModel() -> SidetoneModel {
        SidetoneModel(dependencies: SidetoneDependencies(
            desktop: SystemAudioTap(),
            mic: MicCapture(),
            mixer: StereoMixer(),
            meetings: CalendarAccess(),
            alerts: NotificationManager(),
            permissions: SystemPermissions(),
            actions: MacSystemActions()
        ))
    }
}
