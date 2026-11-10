import Foundation
import os

/// The app's logging entry points.
///
/// One `Logger` per concern, all under one subsystem, so the live log is readable:
///
/// ```sh
/// log stream --level debug --predicate 'subsystem == "com.mariocodarin.Sidetone"'
/// ```
///
/// Rules: lifecycle at `.notice`, failures at `.error`, per-buffer detail at `.debug`.
/// Nothing here is called from a realtime audio thread.
public enum Log {
    public static let subsystem = AppInfo.bundleIdentifier

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let model = Logger(subsystem: subsystem, category: "model")
    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let mix = Logger(subsystem: subsystem, category: "mix")
    public static let library = Logger(subsystem: subsystem, category: "library")
    public static let permissions = Logger(subsystem: subsystem, category: "permissions")
    public static let alerts = Logger(subsystem: subsystem, category: "alerts")

    /// Start of a span, paired with `end`. Logs duration at `.notice`.
    public struct Span {
        let logger: Logger
        let name: String
        let started: DispatchTime

        public func end(_ detail: String = "") {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
            if detail.isEmpty {
                logger.notice("\(name, privacy: .public) finished in \(ms, format: .fixed(precision: 1)) ms")
            } else {
                logger.notice("\(name, privacy: .public) finished in \(ms, format: .fixed(precision: 1)) ms — \(detail, privacy: .public)")
            }
        }
    }

    public static func begin(_ name: String, _ logger: Logger = Log.model) -> Span {
        logger.notice("\(name, privacy: .public) started")
        return Span(logger: logger, name: name, started: .now())
    }
}

/// Identity of the running bundle, with sensible fallbacks for the check/preview executables
/// (which have no Info.plist).
public enum AppInfo {
    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.mariocodarin.Sidetone"
    }

    public static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Sidetone"
    }

    /// `1.2` from `CFBundleShortVersionString`; `"dev"` outside an app bundle.
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// `CFBundleVersion` (the build number).
    public static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
