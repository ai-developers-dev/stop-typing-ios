import ActivityKit
import Foundation

/// Shared between main app and widget extension.
/// The main app starts/updates/ends activities.
/// The widget extension renders the Dynamic Island UI.
struct StopTypingWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isRecording: Bool
        var mode: String
    }

    var sessionId: String
}
