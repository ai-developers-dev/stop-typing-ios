import Foundation

enum AppGroupConfig {
    static let suiteName = "group.com.stormacq.StopTypingiOS.shared"

    static let latestTranscriptKey = "latestTranscript"
    static let transcriptTimestampKey = "transcriptTimestamp"
    static let recentRewriteModeKey = "recentRewriteMode"
    static let userPreferencesKey = "userPreferences"

    // Session / heartbeat keys
    static let heartbeatKey = "sessionHeartbeat"
    static let isRecordingKey = "isRecording"
    static let sessionActiveKey = "sessionActive"
    static let audioLevelKey = "audioLevel"
}
