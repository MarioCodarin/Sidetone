import Foundation

/// Source of calendar meetings (EventKit in production).
@MainActor
public protocol MeetingProviding: AnyObject {
    /// Invoked on main whenever the underlying calendar data changes.
    var onChange: (() -> Void)? { get set }

    /// Ask for read access; returns whether it was granted.
    func requestAccess() async -> Bool
    /// Timed meetings around `now`, already trimmed to the slice the UI shows.
    func meetingsAroundNow(_ now: Date) -> [Meeting]
}
