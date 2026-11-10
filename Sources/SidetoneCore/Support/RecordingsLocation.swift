import Foundation

/// Resolves where recordings live.
///
/// A public app must never assume the author's folder: the default is
/// `~/Documents/Recordings`, but the user can point it anywhere (an external drive, a synced
/// folder) from setup or Settings. Nothing outside the chosen folder is ever touched.
public enum RecordingsLocation {

    /// `~/Documents/Recordings`, the folder used until the user picks another one.
    public static var defaultRoot: URL {
        if let documents = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) {
            return documents.appendingPathComponent("Recordings", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    /// Resolve the configured path (or the default). Never creates the folder.
    ///
    /// - Parameter override: used by tests and previews; wins over the preference.
    public static func root(customPath: String?, override: URL? = nil) -> URL {
        if let override { return override }
        guard let path = customPath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return defaultRoot
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// The root the app is using right now.
    public static func currentRoot(override: URL? = nil) -> URL {
        root(customPath: Preferences.recordingsFolderPath, override: override)
    }

    /// Persist a user choice and return the resolved folder. Passing `nil` restores the default.
    @discardableResult
    public static func setCustomRoot(_ url: URL?) -> URL {
        if let url {
            Preferences.recordingsFolderPath = url.path
        } else {
            Preferences.recordingsFolderPath = nil
        }
        return root(customPath: Preferences.recordingsFolderPath)
    }

    /// Compact, human path for the UI: `~/Documents/Recordings` instead of `/Users/name/...`.
    public static func displayPath(for url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
