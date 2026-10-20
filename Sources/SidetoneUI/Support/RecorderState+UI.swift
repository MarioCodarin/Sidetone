import SwiftUI
import SidetoneCore

/// How each `RecorderState` looks. One mapping shared by the menu-bar glyph and the panel header.
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
        case .idle:      return .secondary
        case .recording: return .red
        case .paused:    return .orange
        }
    }
}
