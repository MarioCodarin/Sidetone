import Foundation
import AVFoundation

/// One past recording on disk. A finished take is a single `.m4a` in ~/Documents/Recordings.
/// A take that never finished mixing is still the working folder.
public struct RecordingEntry: Identifiable, Equatable {
    /// File path for a finished mix, folder path for one that still needs mixing.
    public var id: String { folderURL.path }
    public let folderURL: URL
    /// Parsed meeting title (nil for ad-hoc recordings).
    public let title: String?
    /// Best timestamp for the recording (parsed from the folder name, else file date).
    public let date: Date
    /// audio.m4a, if it exists.
    public let audioURL: URL?
    /// Length in seconds. From `session.json` while the take is still a folder, otherwise from the m4a.
    public let duration: TimeInterval?

    public init(folderURL: URL, title: String?, date: Date, audioURL: URL?, duration: TimeInterval? = nil) {
        self.folderURL = folderURL
        self.title = title
        self.date = date
        self.audioURL = audioURL
        self.duration = duration
    }

    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return "Recording"
    }

    /// Raw captures exist but the stereo mix does not (crash, quit mid-mix, failed mix).
    public var needsMix: Bool { audioURL == nil }
}

/// Reads the on-disk recordings library so the panel can show prior recordings
/// after a restart — the in-memory list doesn't survive relaunches.
public enum RecordingsLibrary {

    /// ~/Documents/Recordings (not created here).
    public static func recordingsRoot() -> URL? {
        guard let documents = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return nil }
        return documents.appendingPathComponent("Recordings", isDirectory: true)
    }

    /// The `limit` most recent recordings, newest first. Finished takes are `.m4a` files;
    /// a take that still needs mixing is its working folder.
    ///
    /// - Parameter root: override for tests. `nil` uses `recordingsRoot()`.
    public static func recent(limit: Int, root: URL? = nil) -> [RecordingEntry] {
        let fm = FileManager.default
        guard let root = root ?? recordingsRoot(),
              let items = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let entries: [RecordingEntry] = items.compactMap { url in
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .creationDateKey, .contentModificationDateKey,
            ])
            if values?.isDirectory == true {
                return folderEntry(url, values: values, fm: fm)
            }
            return fileEntry(url, values: values)
        }

        return Array(entries.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// Parse "yyyy-M-d-HHmm[-title][-N]" into (date, title). Best-effort.
    public static func parseFolderName(_ name: String) -> (Date?, String?) {
        let parts = name.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              parts[3].count == 4, let hhmm = Int(parts[3]) else {
            return (nil, name.isEmpty ? nil : name)
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hhmm / 100
        components.minute = hhmm % 100
        let date = Calendar(identifier: .gregorian).date(from: components)

        // Title is everything after the date/time, minus a trailing numeric
        // collision suffix (e.g. "-2") added when two recordings share a minute.
        var titleParts = Array(parts.dropFirst(4))
        if let last = titleParts.last, last.count <= 3, !last.isEmpty, last.allSatisfy(\.isNumber) {
            titleParts.removeLast()
        }
        let title = titleParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (date, title.isEmpty ? nil : title)
    }

    private static func folderEntry(_ url: URL, values: URLResourceValues?, fm: FileManager) -> RecordingEntry? {
        let audio = url.appendingPathComponent(RecordingFiles.mix)
        let hasAudio = fm.fileExists(atPath: audio.path)
        let hasRaw = fm.fileExists(atPath: url.appendingPathComponent(RecordingFiles.desktop).path)
            || fm.fileExists(atPath: url.appendingPathComponent(RecordingFiles.mic).path)
        // A folder that only holds a transcript, or anything else, is not a recording.
        guard hasAudio || hasRaw else { return nil }

        let (parsedDate, title) = parseFolderName(url.lastPathComponent)
        let fileDate = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
        let fromSession = SessionInfo.read(fromFolder: url).flatMap(duration(of:))

        return RecordingEntry(
            folderURL: url,
            title: title,
            date: parsedDate ?? fileDate,
            audioURL: hasAudio ? audio : nil,
            duration: fromSession ?? (hasAudio ? duration(ofAudio: audio) : nil)
        )
    }

    private static func fileEntry(_ url: URL, values: URLResourceValues?) -> RecordingEntry? {
        guard url.pathExtension.lowercased() == "m4a",
              url.lastPathComponent != "audio-partial.m4a" else { return nil }

        let (parsedDate, title) = parseFolderName(url.deletingPathExtension().lastPathComponent)
        let fileDate = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
        return RecordingEntry(
            folderURL: url,
            title: title,
            date: parsedDate ?? fileDate,
            audioURL: url,
            duration: duration(ofAudio: url)
        )
    }

    /// Header-only read. Nil when the file is missing, not audio, or empty.
    static func duration(ofAudio url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let rate = file.fileFormat.sampleRate
        guard rate > 0, file.length > 0 else { return nil }
        return TimeInterval(file.length) / rate
    }

    /// Longer of the two captures. A channel with no rate is ignored (nothing was written).
    private static func duration(of info: SessionInfo) -> TimeInterval? {
        let longest = max(seconds(info.desktop), seconds(info.mic))
        return longest > 0 ? longest : nil
    }

    private static func seconds(_ capture: CaptureResult) -> TimeInterval {
        guard capture.sampleRate > 0 else { return 0 }
        return TimeInterval(capture.frameCount) / capture.sampleRate
    }
}
