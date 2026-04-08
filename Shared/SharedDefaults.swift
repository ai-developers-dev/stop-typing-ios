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
}
