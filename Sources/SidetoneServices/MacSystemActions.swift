import Foundation
import AppKit
import SidetoneCore

/// AppKit-backed `SystemActions`.
@MainActor
public final class MacSystemActions: SystemActions {

    public init() {}

    public func copyFileToPasteboard(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    public func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func openSettings(for issue: PermissionIssue) {
        let pane: String
        switch issue {
        case .microphone:  pane = "Privacy_Microphone"
        case .systemAudio: pane = "Privacy_AudioCapture"
        case .calendar:    pane = "Privacy_Calendars"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    public func quit() {
        NSApp.terminate(nil)
    }
}
