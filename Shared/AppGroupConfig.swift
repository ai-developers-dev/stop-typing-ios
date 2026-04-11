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
    /// Estimated system boot time at the moment the session was activated.
    /// Used by the keyboard to detect reboots — if the stored bootId doesn't
    /// match the current one, the phone rebooted and the app is definitely not
    /// running anymore, so the keyboard shows "Start ST".
    static let bootIdKey = "bootId"
}
