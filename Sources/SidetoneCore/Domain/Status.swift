import Foundation

/// A transient message shown in the panel header.
public struct StatusMessage: Equatable, Identifiable {
    public enum Kind: Equatable {
        case info
        case success
        case error
    }

    public let id = UUID()
    public let text: String
    public let kind: Kind

    public init(_ text: String, kind: Kind = .info) {
        self.text = text
        self.kind = kind
    }
}

/// A macOS privacy permission the user has to grant before Sidetone can do its job.
public enum PermissionIssue: String, CaseIterable, Identifiable {
    case microphone
    case systemAudio
    case calendar

    public var id: String { rawValue }

    /// One-line explanation shown next to the "Open Settings" button.
    public var explanation: String {
        switch self {
        case .microphone:  return "Microphone access is off, so your voice can’t be recorded."
        case .systemAudio: return "System Audio Recording access is off, so the other side of the call can’t be recorded."
        case .calendar:    return "Calendar access is off, so meetings can’t be listed."
        }
    }
}
