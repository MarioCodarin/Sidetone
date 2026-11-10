import SwiftUI
import SidetoneCore

/// How each `RecorderState` looks. One mapping shared by the menu-bar glyph, the panel and the
/// setup window.
extension RecorderState {
    public var label: String {
        switch self {
        case .idle:      return "Ready"
        case .recording: return "Recording"
        case .paused:    return "Paused"
        }
    }

    /// Split-circle at rest (the L/R brand); record / pause glyphs while capturing.
    public var symbolName: String {
        switch self {
        case .idle:      return "circle.lefthalf.filled"
        case .recording: return "record.circle.fill"
        case .paused:    return "pause.circle.fill"
        }
    }

    public var tint: Color {
        switch self {
        case .idle:      return DS.Palette.accent
        case .recording: return DS.Palette.record
        case .paused:    return DS.Palette.attention
        }
    }

    /// What the two channels are doing, in one quiet line.
    public func channelSummary(micEnabled: Bool) -> String {
        micEnabled ? "Them left · You right" : "Them left · mic off"
    }
}
