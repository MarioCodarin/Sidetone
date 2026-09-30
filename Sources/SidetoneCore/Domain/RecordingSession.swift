import Foundation

/// File names inside a recording folder. One place, so the writer, the mixer and the
/// library can never disagree.
public enum RecordingFiles {
    public static let desktop = "desktop.caf"
    public static let mic = "mic.caf"
    public static let mix = "audio.m4a"
    public static let info = "session.json"
}

/// The folder + file URLs for one recording.
public struct RecordingSession {
    /// ~/Documents/Recordings/{yyyy-M-d}-{HHmm}[-title][-N]/
    public let folderURL: URL
    public let desktopURL: URL
    public let micURL: URL
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

        var folderName = "\(Self.dateFormatter.string(from: now))-\(Self.timeFormatter.string(from: now))"
        if let title = meetingTitle {
            folderName += "-\(Meeting.sanitize(title))"
        }

        var folderURL = root.appendingPathComponent(folderName, isDirectory: true)
        // Never overwrite a prior recording made in the same minute: pick the next free `-N`.
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
            desktopURL: folderURL.appendingPathComponent(RecordingFiles.desktop),
            micURL: folderURL.appendingPathComponent(RecordingFiles.mic),
            outputURL: folderURL.appendingPathComponent(RecordingFiles.mix),
            startedAt: now,
            meetingTitle: meetingTitle
        )
    }

    private static let dateFormatter = posixFormatter("yyyy-M-d")
    private static let timeFormatter = posixFormatter("HHmm")

    private static func posixFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = format
        return f
    }
}

/// What must survive a crash or a failed mix so the recording can be re-mixed later:
/// each capture's alignment data. Written next to the raw files as `session.json`.
public struct SessionInfo: Codable, Equatable {
    public var startedAt: Date
    public var meetingTitle: String?
    public var desktop: CaptureResult
    public var mic: CaptureResult

    public init(startedAt: Date, meetingTitle: String?, desktop: CaptureResult, mic: CaptureResult) {
        self.startedAt = startedAt
        self.meetingTitle = meetingTitle
        self.desktop = desktop
        self.mic = mic
    }

    public func write(toFolder folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(
            to: folder.appendingPathComponent(RecordingFiles.info),
            options: .atomic
        )
    }

    /// nil when the file is missing or unreadable (older recordings, or a crash before Save).
    public static func read(fromFolder folder: URL) -> SessionInfo? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(RecordingFiles.info)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionInfo.self, from: data)
    }
}
