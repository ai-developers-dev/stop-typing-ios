import Foundation

enum RewriteMode: String, Codable, CaseIterable, Identifiable {
    case shorten = "Shorten"
    case professional = "Professional"
    case friendly = "Friendly"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .shorten: return "scissors"
        case .professional: return "briefcase"
        case .friendly: return "face.smiling"
        }
    }

    var description: String {
        switch self {
        case .shorten: return "Make it shorter"
        case .professional: return "Make it professional"
        case .friendly: return "Make it friendly"
        }
    }
}
