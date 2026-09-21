import Foundation
import AVFoundation

// MARK: - RecorderState

public enum RecorderState: Equatable {
    case idle
    case recording
    case paused
}

// MARK: - CaptureResult

/// Returned by a capture's `stop()`.
public struct CaptureResult {
    /// mach host time (mach_absolute_time domain) of the FIRST sample written; nil if nothing captured.
    public var firstHostTime: UInt64?
    /// actual capture sample rate.
    public var sampleRate: Double
    /// number of audio frames written.
    public var frameCount: AVAudioFramePosition

    public init(firstHostTime: UInt64? = nil, sampleRate: Double = 0, frameCount: AVAudioFramePosition = 0) {
        self.firstHostTime = firstHostTime
        self.sampleRate = sampleRate
        self.frameCount = frameCount
    }
}

// MARK: - Meeting

public struct Meeting: Identifiable, Equatable {
    /// EKEvent.eventIdentifier (or a synthesized uuid).
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    /// Display names of the organizer + invitees (best-effort; may be empty).
    public let attendees: [String]

    public init(id: String, title: String, start: Date, end: Date, attendees: [String] = []) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.attendees = attendees
    }

    /// start <= now <= end
    public func isInProgress(_ now: Date) -> Bool {
        start <= now && now <= end
    }

    /// Filesystem-safe suffix derived from the title.
    var folderSuffix: String {
        Meeting.sanitize(title)
    }

    /// Make a title filesystem-safe:
    /// - strip `/ : \ ? % * | " < >` and control characters
    /// - collapse runs of whitespace to a single `-`
    /// - cap to ~40 characters
    /// - trim leading `.`/`-`
    /// - empty result -> "meeting"
    public static func sanitize(_ raw: String) -> String {
        let illegal: Set<Character> = ["/", ":", "\\", "?", "%", "*", "|", "\"", "<", ">"]

        // Remove illegal + control characters.
        var cleaned = ""
        cleaned.reserveCapacity(raw.count)
        for ch in raw {
            if illegal.contains(ch) { continue }
            if ch.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { continue }
            cleaned.append(ch)
        }

        // Collapse whitespace runs to a single dash.
        let pieces = cleaned.split(whereSeparator: { $0.isWhitespace })
        var collapsed = pieces.joined(separator: "-")

        // Cap length to ~40 chars.
        if collapsed.count > 40 {
            collapsed = String(collapsed.prefix(40))
        }

        // Trim leading '.' and '-' (avoid hidden / odd folder names).
        while let first = collapsed.first, first == "." || first == "-" {
            collapsed.removeFirst()
        }
        // Also trim trailing dashes left over from capping/collapsing.
        while let last = collapsed.last, last == "-" {
            collapsed.removeLast()
        }

        return collapsed.isEmpty ? "meeting" : collapsed
    }
}

// MARK: - RecordingSession

public struct RecordingSession {
    /// ~/Documents/Recordings/{yyyy-M-d}-{HHmm}[-suffix]/
    public let folderURL: URL
    /// folderURL + "desktop.caf"
    public let desktopURL: URL
    /// folderURL + "mic.caf"
    public let micURL: URL
    /// folderURL + "audio.m4a"
    public let outputURL: URL
    public let startedAt: Date
    public let meetingTitle: String?

    /// Creates the dated folder and returns the session. Throws on filesystem error.
    ///
    /// - Parameter recordingsRoot: override for tests. `nil` uses `~/Documents/Recordings`.
    public static func create(now: Date, meetingTitle: String?, recordingsRoot: URL? = nil) throws -> RecordingSession {
        let fm = FileManager.default

        let root: URL
        if let recordingsRoot {
            root = recordingsRoot
        } else {
            let documents = try fm.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            root = documents.appendingPathComponent("Recordings", isDirectory: true)
        }

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        dateFmt.calendar = Calendar(identifier: .gregorian)
        dateFmt.dateFormat = "yyyy-M-d"

        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        timeFmt.calendar = Calendar(identifier: .gregorian)
        timeFmt.dateFormat = "HHmm"

        var folderName = "\(dateFmt.string(from: now))-\(timeFmt.string(from: now))"
        if let title = meetingTitle {
            folderName += "-\(Meeting.sanitize(title))"
        }

        var folderURL = root.appendingPathComponent(folderName, isDirectory: true)
        // Avoid clobbering a prior recording made in the same minute (e.g. save-then-record
        // again, or a meeting whose sanitized title matches): if the folder already exists,
        // pick the next free `-N` suffix so we never overwrite existing raw files.
        if fm.fileExists(atPath: folderURL.path) {
            var n = 2
            var candidate = root.appendingPathComponent("\(folderName)-\(n)", isDirectory: true)
            while fm.fileExists(atPath: candidate.path) {
                n += 1
                candidate = root.appendingPathComponent("\(folderName)-\(n)", isDirectory: true)
            }
            folderURL = candidate
        }
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        return RecordingSession(
            folderURL: folderURL,
            desktopURL: folderURL.appendingPathComponent("desktop.caf"),
            micURL: folderURL.appendingPathComponent("mic.caf"),
            outputURL: folderURL.appendingPathComponent("audio.m4a"),
            startedAt: now,
            meetingTitle: meetingTitle
        )
    }
}

// MARK: - Meter mapping

/// dBFS (-inf..0) -> normalized meter 0...1 for the UI.
public func meterLevel(fromDB db: Float) -> Float {
    max(0, min(1, (db + 80) / 80))
}
