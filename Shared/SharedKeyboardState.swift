import Foundation

/// The data contract between the main app and the keyboard extension.
/// Both targets must include this file.
struct SharedKeyboardState {
    let transcript: String?
    let timestamp: Date?
    let rewriteMode: String?

    var hasTranscript: Bool {
        guard let t = transcript else { return false }
        return !t.isEmpty
    }

    var transcriptAge: String? {
        guard let ts = timestamp else { return nil }
        let interval = Date().timeIntervalSince(ts)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    /// Read current state from shared App Group storage.
    static func load() -> SharedKeyboardState {
        let d = SharedDefaults.shared
        return SharedKeyboardState(
            transcript: d.latestTranscript,
            timestamp: d.transcriptTimestamp,
            rewriteMode: d.recentRewriteMode
        )
    }
}
