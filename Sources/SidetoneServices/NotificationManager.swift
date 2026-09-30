import Foundation
import UserNotifications
import SidetoneCore

/// UserNotifications-backed `MeetingAlerting`.
///
/// Owns a self-contained `UNUserNotificationCenterDelegate` (a private inner
/// `NSObject`) so the manager stays fully self-contained: it does not rely on
/// the AppDelegate for any notification wiring.
///
/// Responsibilities:
///   * Register the "RECORDING" category with a "STOP" action ("Stop Recording"). Only that
///     action stops the recording; tapping the banner body just dismisses it, so a stray click
///     can't end a meeting recording.
///   * Request `[.alert, .sound]` authorization (delegate is set FIRST).
///   * Present banners while the accessory app is "active" (`willPresent`).
///   * Schedule / cancel the one-shot "meeting ended — still recording" alert.
///
/// The app must be code-signed (ad-hoc is fine) with a stable bundle id, or the
/// authorization prompt never appears and notifications are silently dropped.
@MainActor
public final class NotificationManager: MeetingAlerting {

    // MARK: - Identifiers

    /// Category that carries the "Stop Recording" action button.
    private static let categoryIdentifier = "RECORDING"
    /// Action identifier for the "Stop Recording" button.
    /// `nonisolated` so the (nonisolated) notification-center delegate can compare
    /// against it off the main actor; it is an immutable compile-time constant.
    nonisolated private static let stopActionIdentifier = "STOP"
    /// Pending-request identifier for the single meeting-end alert.
    private static let meetingEndRequestIdentifier = "meeting-end"

    // MARK: - Public API

    /// Fired when the user taps the "Stop Recording" action. Always delivered on the main actor.
    public var onStopRequested: (() -> Void)?

    public init() {}

    // MARK: - Delegate

    /// Strong reference to the delegate — `UNUserNotificationCenter.delegate`
    /// is `weak`, so the manager must retain it for the app's lifetime.
    private let delegate = Delegate()

    // MARK: - Authorization & setup

    /// Wire the delegate, register the "RECORDING" category, then request
    /// authorization. The delegate MUST be assigned before requesting so that
    /// `willPresent` / `didReceive` callbacks are never missed.
    public func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()

        // Bridge the inner delegate's "stop" tap back to this manager (main).
        delegate.onStopRequested = { [weak self] in
            self?.onStopRequested?()
        }

        // 1. Set the delegate FIRST.
        center.delegate = delegate

        // 2. Register the "RECORDING" category with its "STOP" action.
        let stopAction = UNNotificationAction(
            identifier: Self.stopActionIdentifier,
            title: "Stop Recording",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [stopAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

        // 3. Request authorization. Failure is non-fatal for the rest of the
        //    app (recording still works; we just won't post the end alert).
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Ad-hoc unsigned apps often fail this request; recording still works.
        }
    }

    // MARK: - Meeting-end alert

    /// Schedule a one-shot local notification at the meeting's scheduled end.
    /// If recording stops before then, `cancelMeetingEndAlert()` removes it.
    ///
    /// Uses a single fixed request id ("meeting-end"), so scheduling again
    /// replaces any previously scheduled alert.
    public func scheduleMeetingEndAlert(at endDate: Date, meetingTitle: String) {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Meeting ended — still recording"
        content.body = "\(meetingTitle) was scheduled to end. Stop and save?"
        content.categoryIdentifier = Self.categoryIdentifier
        content.interruptionLevel = .timeSensitive   // pierce Focus when timely
        content.sound = .default

        // UNTimeIntervalNotificationTrigger requires a strictly positive
        // interval; clamp to at least 1 second (e.g. if the meeting end is
        // already in the past, fire essentially immediately).
        let interval = max(1, endDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)

        let request = UNNotificationRequest(
            identifier: Self.meetingEndRequestIdentifier,
            content: content,
            trigger: trigger
        )

        // Replace any existing scheduled alert before adding the new one.
        center.removePendingNotificationRequests(withIdentifiers: [Self.meetingEndRequestIdentifier])
        center.add(request)
    }

    /// Remove the pending meeting-end alert (if any).
    public func cancelMeetingEndAlert() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.meetingEndRequestIdentifier])
    }

    // MARK: - Inner delegate

    /// Self-contained `UNUserNotificationCenterDelegate`. Kept as a separate
    /// `NSObject` (rather than conforming `NotificationManager` itself) so the
    /// manager can remain a `@MainActor` Swift class without the Objective-C
    /// protocol-conformance friction.
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {

        /// Invoked on the MAIN thread when the user taps the "STOP" action.
        var onStopRequested: (() -> Void)?

        /// Present the banner + sound even though the accessory ("foreground")
        /// app is technically active.
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }

        /// Handle a tap on the "STOP" action. Tapping the banner body does nothing.
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse
        ) async {
            guard response.actionIdentifier == NotificationManager.stopActionIdentifier else { return }

            // The model performs the actual save/stop, on the main actor.
            await MainActor.run {
                self.onStopRequested?()
            }
        }
    }
}
