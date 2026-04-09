import Foundation

/// Thread-safe read/write access to the App Group shared UserDefaults.
final class SharedDefaults {
    static let shared = SharedDefaults()

    private let defaults: UserDefaults

    private init() {
        guard let suite = UserDefaults(suiteName: AppGroupConfig.suiteName) else {
            fatalError("App Group '\(AppGroupConfig.suiteName)' not configured. Add it to both targets.")
        }
        self.defaults = suite
    }

    // MARK: - Latest Transcript

    var latestTranscript: String? {
        get { defaults.string(forKey: AppGroupConfig.latestTranscriptKey) }
        set { defaults.set(newValue, forKey: AppGroupConfig.latestTranscriptKey) }
    }

    var transcriptTimestamp: Date? {
        get { defaults.object(forKey: AppGroupConfig.transcriptTimestampKey) as? Date }
        set { defaults.set(newValue, forKey: AppGroupConfig.transcriptTimestampKey) }
    }

    // MARK: - Rewrite Mode

    var recentRewriteMode: String? {
        get { defaults.string(forKey: AppGroupConfig.recentRewriteModeKey) }
        set { defaults.set(newValue, forKey: AppGroupConfig.recentRewriteModeKey) }
    }

    // MARK: - Convenience

    func saveTranscript(_ text: String) {
        latestTranscript = text
        transcriptTimestamp = Date()
    }

    func clearTranscript() {
        latestTranscript = nil
        transcriptTimestamp = nil
    }

    // MARK: - Session Heartbeat

    var heartbeat: Date? {
        get {
            defaults.synchronize()
            return defaults.object(forKey: AppGroupConfig.heartbeatKey) as? Date
        }
        set {
            defaults.set(newValue, forKey: AppGroupConfig.heartbeatKey)
            defaults.synchronize()
        }
    }

    var isRecording: Bool {
        get {
            defaults.synchronize()
            return defaults.bool(forKey: AppGroupConfig.isRecordingKey)
        }
        set {
            defaults.set(newValue, forKey: AppGroupConfig.isRecordingKey)
            defaults.synchronize()
        }
    }

    var sessionActive: Bool {
        get {
            defaults.synchronize()
            return defaults.bool(forKey: AppGroupConfig.sessionActiveKey)
        }
        set {
            defaults.set(newValue, forKey: AppGroupConfig.sessionActiveKey)
            defaults.synchronize()
        }
    }

    /// Returns true if the main app heartbeat is recent (within 5 seconds).
    func isAppAlive() -> Bool {
        defaults.synchronize()
        guard let beat = defaults.object(forKey: AppGroupConfig.heartbeatKey) as? Date else { return false }
        return Date().timeIntervalSince(beat) < 10.0
    }

    func writeHeartbeat() {
        defaults.set(Date(), forKey: AppGroupConfig.heartbeatKey)
        defaults.synchronize()
    }

    /// Audio level (0.0 to 1.0) written by the app ~10x/sec, read by the keyboard for waveform.
    /// No synchronize() — OS syncs fast enough at this rate, reduces disk I/O.
    var audioLevel: Float {
        get { defaults.float(forKey: AppGroupConfig.audioLevelKey) }
        set { defaults.set(newValue, forKey: AppGroupConfig.audioLevelKey) }
    }

    func clearSession() {
        heartbeat = nil
        isRecording = false
        sessionActive = false
        audioLevel = 0
    }

    // MARK: - Debug Log (persists to App Group so both app and keyboard can read)

    var debugLog: String {
        get { defaults.string(forKey: "debugLog") ?? "" }
        set { defaults.set(newValue, forKey: "debugLog") }
    }

    func appendLog(_ msg: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(timestamp)] \(msg)\n"
        var log = debugLog
        // Keep last 30 lines
        let lines = log.components(separatedBy: "\n")
        if lines.count > 30 {
            log = lines.suffix(20).joined(separator: "\n")
        }
        log += line
        debugLog = log
    }

    func clearDebugLog() {
        debugLog = ""
    }
}
