import Foundation

struct UserSettings: Codable {
    var transcriptionEngine: TranscriptionEngine
    var hasCompletedOnboarding: Bool
    var autoSaveToShared: Bool

    enum TranscriptionEngine: String, Codable, CaseIterable {
        case appleSpeech = "Apple Speech"
        case remote = "Cloud API"
    }

    static let `default` = UserSettings(
        transcriptionEngine: .appleSpeech,
        hasCompletedOnboarding: false,
        autoSaveToShared: true
    )

    // MARK: - Persistence (local, not shared)

    private static let storageKey = "userSettings"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func load() -> UserSettings {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let settings = try? JSONDecoder().decode(UserSettings.self, from: data) else {
            return .default
        }
        return settings
    }
}
