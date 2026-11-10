import Foundation
import UserNotifications
import SidetoneCore

/// UserNotifications-backed `MeetingAlerting`.
///
/// Owns a self-contained `UNUserNotificationCenterDelegate` (a private inner `NSObject`) so the
/// manager does not rely on the AppDelegate for any notification wiring.
///
/// Authorization is requested **lazily**, the first time an end-of-meeting alert is actually
/// scheduled (or when setup asks for it) — not at launch, so the first thing a new user sees is
/// the app, not a permission prompt.
@MainActor
public final class NotificationManager: MeetingAlerting {

    // MARK: - Identifiers

    private static let categoryIdentifier = "RECORDING"
    /// `nonisolated` so the delegate can compare against it off the main actor.
    nonisolated private static let stopActionIdentifier = "STOP"
    private static let meetingEndRequestIdentifier = "meeting-end"

    // MARK: - Public API

    public var onStopRequested: (() -> Void)?

    public init() {
        // The delegate MUST be set before any request could arrive, and the category must
        // exist before an alert that uses it is scheduled.
        delegate.onStopRequested = { [weak self] in self?.onStopRequested?() }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories([Self.category])
    }

    // MARK: - Authorization & setup

    public func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            Log.permissions.notice("notification permission granted: \(granted, privacy: .public)")
        } catch {
            // Pathological (unsigned) cases fail here; recording still works.
            Log.permissions.error("notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Meeting-end alert

    /// Schedule a one-shot local notification at the meeting's scheduled end. A single fixed
    /// request id means scheduling again replaces the previous alert.
    public func scheduleMeetingEndAlert(at endDate: Date, meetingTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "Meeting ended — still recording"
        content.body = "\(meetingTitle) was scheduled to end. Stop and save?"
        content.categoryIdentifier = Self.categoryIdentifier
        content.interruptionLevel = .timeSensitive
        content.sound = .default

        // UNTimeIntervalNotificationTrigger needs a strictly positive interval.
        let interval = max(1, endDate.timeIntervalSinceNow)
        let request = UNNotificationRequest(
            identifier: Self.meetingEndRequestIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )

        Task { @MainActor in
            await requestAuthorization()
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [Self.meetingEndRequestIdentifier])
            do {
                try await center.add(request)
                Log.alerts.notice("meeting-end alert scheduled in \(interval, format: .fixed(precision: 0)) s")
            } catch {
                Log.alerts.error("could not schedule meeting-end alert: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func cancelMeetingEndAlert() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.meetingEndRequestIdentifier])
    }

    // MARK: - Pieces

    private static var category: UNNotificationCategory {
        let stop = UNNotificationAction(
            identifier: stopActionIdentifier,
            title: "Stop Recording",
            options: []
        )
        return UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [stop],
            intentIdentifiers: [],
            options: []
        )
    }

    /// Strong reference: `UNUserNotificationCenter.delegate` is weak.
    private let delegate = Delegate()

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {

        var onStopRequested: (() -> Void)?

        /// Present the banner + sound even though the accessory app is technically "active".
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }

        /// Only the "STOP" action stops a recording; tapping the banner body just dismisses it.
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse
        ) async {
            guard response.actionIdentifier == NotificationManager.stopActionIdentifier else { return }
            await MainActor.run {
                self.onStopRequested?()
            }
        }
    }
}
