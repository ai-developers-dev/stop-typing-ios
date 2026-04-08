import Foundation

/// Manages the shared state between the main app and keyboard extension.
@MainActor
final class SharedStateManager: ObservableObject {
    static let shared = SharedStateManager()

    @Published var latestTranscript: String?
    @Published var transcriptTimestamp: Date?

    private let defaults = SharedDefaults.shared

    private init() {
        refresh()
    }

    func refresh() {
        latestTranscript = defaults.latestTranscript
        transcriptTimestamp = defaults.transcriptTimestamp
    }

    func saveTranscript(_ text: String) {
        defaults.saveTranscript(text)
        latestTranscript = text
        transcriptTimestamp = Date()
    }

    func saveRewriteMode(_ mode: RewriteMode) {
        defaults.recentRewriteMode = mode.rawValue
    }

    func clearTranscript() {
        defaults.clearTranscript()
        latestTranscript = nil
        transcriptTimestamp = nil
    }
}
