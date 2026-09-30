import Foundation

/// User-facing alerts (local notifications in production).
@MainActor
public protocol MeetingAlerting: AnyObject {
    /// Fired on main when the user taps the alert's "Stop Recording" action.
    var onStopRequested: (() -> Void)? { get set }

    func requestAuthorization() async
    /// One-shot "meeting ended — still recording" alert. Replaces any pending one.
    func scheduleMeetingEndAlert(at endDate: Date, meetingTitle: String)
    func cancelMeetingEndAlert()
}
