import Foundation

/// Turns a finished working folder into the one file worth keeping: `{folder name}.m4a`
/// beside the folder. Capture files are removed only after that mix is a readable audio file.
/// Anything else in the folder (a transcript, for example) is left where it is.
public enum RecordingOutput {

    /// Promote every finished folder under `root`. In-progress and failed mixes have no
    /// readable `audio.m4a`, so they are left untouched.
    public static func promoteFinishedFolders(in root: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in items {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            _ = promote(folder: url)
        }
    }

    /// Move a complete `audio.m4a` out of `folder` and delete the capture files.
    ///
    /// - Returns: The m4a to open. Nil when the mix is missing or not a readable audio file;
    ///   nothing is deleted in that case. When the move itself fails, the in-folder m4a is
    ///   returned and the capture files stay, so the recording is not lost.
    @discardableResult
    public static func promote(folder: URL) -> URL? {
        let fm = FileManager.default
        let mix = folder.appendingPathComponent(RecordingFiles.mix)
        guard RecordingsLibrary.duration(ofAudio: mix) != nil else { return nil }

        let dest = uniqueM4A(in: folder.deletingLastPathComponent(), base: folder.lastPathComponent)
        do {
            try fm.moveItem(at: mix, to: dest)
        } catch {
            return mix
        }

        for name in [RecordingFiles.desktop, RecordingFiles.mic, RecordingFiles.info, "audio-partial.m4a"] {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
        if directoryIsEmpty(folder) {
            try? fm.removeItem(at: folder)
        }
        return dest
    }

    private static func uniqueM4A(in parent: URL, base: String) -> URL {
        let fm = FileManager.default
        var n = 1
        while true {
            let name = n == 1 ? "\(base).m4a" : "\(base)-\(n).m4a"
            let candidate = parent.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    /// True when the directory has nothing left except Finder's `.DS_Store`.
    private static func directoryIsEmpty(_ url: URL) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return false }
        return items.allSatisfy { $0 == ".DS_Store" }
    }
}
