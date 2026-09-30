import Foundation

/// The bits of macOS the model triggers but must not import AppKit for.
@MainActor
public protocol SystemActions: AnyObject {
    /// Put the file on the clipboard (paste into Finder / Mail / …).
    func copyFileToPasteboard(_ url: URL)
    /// Select the item in Finder.
    func reveal(_ url: URL)
    /// Open with the default app (Finder for folders, the audio player for m4a).
    func open(_ url: URL)
    /// Jump to the System Settings pane where the user can grant `issue`.
    func openSettings(for issue: PermissionIssue)
    /// Quit the app.
    func quit()
}
