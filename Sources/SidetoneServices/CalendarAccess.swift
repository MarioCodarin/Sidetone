import Foundation
import EventKit
import SidetoneCore

/// EventKit-backed `MeetingProviding`.
///
/// Owns a single, long-lived `EKEventStore` (releasing it would invalidate every `EKEvent` it
/// vended). Everything runs on the main actor; the `.EKEventStoreChanged` observer hops to main
/// before invoking `onChange`.
@MainActor
public final class CalendarAccess: MeetingProviding {

    public var onChange: (() -> Void)?

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    /// Fetch window around "now".
    private let windowBack: TimeInterval = -2 * 3600    // 2 hours behind
    private let windowForward: TimeInterval = 8 * 3600  // 8 hours ahead

    public init() {
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onChange?() }
        }
    }

    deinit {
        if let token = changeObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Authorization

    /// Requests full calendar access (write-only cannot read existing events). Switches on the
    /// `EKAuthorizationStatus` CASE, never the raw value: `.authorized` and `.fullAccess` collide on 3.
    public func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) ?? false
        case .writeOnly, .denied, .restricted, .authorized:
            // Can't read; the user has to change it in System Settings.
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Fetching

    /// Timed meetings across all calendars in the (now-2h … now+8h) window, trimmed to roughly
    /// the last 2 + current + next 2. Drops all-day and untitled events; dedups by event id.
    public func meetingsAroundNow(_ now: Date) -> [Meeting] {
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(windowBack),
            end: now.addingTimeInterval(windowForward),
            calendars: nil   // all calendars; matches any event OVERLAPPING the window
        )

        var seen = Set<String>()
        let meetings: [Meeting] = store.events(matching: predicate)   // synchronous, unordered
            .filter { !$0.isAllDay && ($0.title?.isEmpty == false) }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            .compactMap { event -> Meeting? in
                guard let start = event.startDate, let end = event.endDate, let title = event.title else { return nil }
                // Recurring/synced calendars can surface duplicates: dedup on the real event id,
                // falling back to title+start when there is none.
                let key = event.eventIdentifier ?? "\(title)|\(start.timeIntervalSince1970)"
                guard seen.insert(key).inserted else { return nil }
                return Meeting(id: event.eventIdentifier ?? UUID().uuidString, title: title, start: start, end: end)
            }

        return Meeting.window(around: now, from: meetings)
    }
}
