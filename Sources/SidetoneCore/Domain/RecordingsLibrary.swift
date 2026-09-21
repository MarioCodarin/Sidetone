import Foundation

/// One past recording on disk (a folder under ~/Documents/Recordings).
public struct RecordingEntry: Identifiable, Equatable {
    /// Folder path — stable identity.
    public var id: String { folderURL.path }
    public let folderURL: URL
    /// Parsed meeting title (nil for ad-hoc recordings).
    public let title: String?
    /// Best timestamp for the recording (parsed from the folder name, else file date).
    public let date: Date
    /// audio.m4a, if it exists.
    public let audioURL: URL?

    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return "Recording"
    }
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

    /// The `limit` most recent recording folders, newest first.
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
            guard values?.isDirectory == true else { return nil }

            let audio = url.appendingPathComponent("audio.m4a")
            let hasAudio = fm.fileExists(atPath: audio.path)
            let hasRaw = fm.fileExists(atPath: url.appendingPathComponent("desktop.caf").path)
                || fm.fileExists(atPath: url.appendingPathComponent("mic.caf").path)
            // Only surface folders that actually look like recordings.
            guard hasAudio || hasRaw else { return nil }

            let (parsedDate, title) = parseFolderName(url.lastPathComponent)
            let fileDate = values?.creationDate ?? values?.contentModificationDate ?? .distantPast

            return RecordingEntry(
                folderURL: url,
                title: title,
                date: parsedDate ?? fileDate,
                audioURL: hasAudio ? audio : nil
            )
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
}
