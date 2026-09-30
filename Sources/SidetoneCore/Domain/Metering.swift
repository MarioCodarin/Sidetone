import Foundation

/// dBFS (-inf..0) -> normalized meter 0...1 for the UI. The meter spans -80…0 dBFS.
public func meterLevel(fromDB db: Float) -> Float {
    max(0, min(1, (db + 80) / 80))
}
