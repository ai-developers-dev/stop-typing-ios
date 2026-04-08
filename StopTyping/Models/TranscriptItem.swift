import Foundation

struct TranscriptItem: Identifiable, Codable {
    let id: UUID
    let text: String
    let createdAt: Date
    var rewriteMode: RewriteMode?

    init(text: String, rewriteMode: RewriteMode? = nil) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.rewriteMode = rewriteMode
    }

    var preview: String {
        if text.count <= 80 { return text }
        return String(text.prefix(80)) + "…"
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}
