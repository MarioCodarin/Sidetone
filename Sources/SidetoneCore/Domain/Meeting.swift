import Foundation

/// A calendar event the user might record.
public struct Meeting: Identifiable, Equatable {
    /// EKEvent.eventIdentifier (or a synthesized uuid).
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date

    public init(id: String, title: String, start: Date, end: Date) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
    }

    /// start <= now <= end
    public func isInProgress(_ now: Date) -> Bool {
        start <= now && now <= end
    }

    /// True once the scheduled end has passed.
    public func hasEnded(_ now: Date) -> Bool {
        end < now
    }

    /// Make a title filesystem-safe:
    /// - strip `/ : \ ? % * | " < >` and control characters
    /// - collapse runs of whitespace to a single `-`
    /// - cap to ~40 characters
    /// - trim leading `.`/`-`
    /// - empty result -> "meeting"
    public static func sanitize(_ raw: String) -> String {
        let illegal: Set<Character> = ["/", ":", "\\", "?", "%", "*", "|", "\"", "<", ">"]

        var cleaned = ""
        cleaned.reserveCapacity(raw.count)
        for ch in raw {
            if illegal.contains(ch) { continue }
            if ch.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { continue }
            cleaned.append(ch)
        }

        var collapsed = cleaned
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "-")

        if collapsed.count > 40 {
            collapsed = String(collapsed.prefix(40))
        }

        // Avoid hidden / odd folder names, and dashes left over from capping/collapsing.
        while let first = collapsed.first, first == "." || first == "-" {
            collapsed.removeFirst()
        }
        while let last = collapsed.last, last == "-" {
            collapsed.removeLast()
        }

        return collapsed.isEmpty ? "meeting" : collapsed
    }

    /// The slice of a start-sorted meeting list worth showing: the last two that already
    /// finished, whatever is in progress, and the next two upcoming — in chronological order.
    public static func window(around now: Date, from meetings: [Meeting]) -> [Meeting] {
        let past = meetings.filter { $0.hasEnded(now) }
        let current = meetings.filter { $0.isInProgress(now) }
        let upcoming = meetings.filter { $0.start > now }

        // A meeting can satisfy two partitions at a boundary instant; dedup defensively.
        var seen = Set<String>()
        let combined = (past.suffix(2) + current + upcoming.prefix(2)).filter { seen.insert($0.id).inserted }
        return combined.sorted { $0.start < $1.start }
    }
}
