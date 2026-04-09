import ActivityKit
import Foundation

struct StopTypingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var isRecording: Bool
        var mode: String
    }

    var sessionId: String
}
