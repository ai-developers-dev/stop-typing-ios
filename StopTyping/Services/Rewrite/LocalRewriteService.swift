import Foundation

/// Simple local text transformations — no network needed.
final class LocalRewriteService: RewriteService {
    func rewrite(_ text: String, mode: RewriteMode) async throws -> String {
        switch mode {
        case .shorten:
            return shorten(text)
        case .professional:
            return makeProfessional(text)
        case .friendly:
            return makeFriendly(text)
        }
    }

    private func shorten(_ text: String) -> String {
        // Split into sentences and take the most important ones
        let sentences = text.components(separatedBy: ". ")
        if sentences.count <= 2 { return text }
        // Keep roughly half the sentences
        let keepCount = max(1, sentences.count / 2)
        return sentences.prefix(keepCount).joined(separator: ". ") + "."
    }

    private func makeProfessional(_ text: String) -> String {
        var result = text
        // Capitalize first letter
        if let first = result.first {
            result = first.uppercased() + result.dropFirst()
        }
        // Basic informal → formal substitutions
        let replacements: [(String, String)] = [
            ("hey ", "Hello, "),
            ("hi ", "Hello, "),
            ("gonna", "going to"),
            ("wanna", "want to"),
            ("gotta", "need to"),
            ("yeah", "yes"),
            ("nah", "no"),
            ("cool", "acceptable"),
            ("awesome", "excellent"),
            ("thanks", "Thank you"),
            ("asap", "at your earliest convenience"),
        ]
        for (informal, formal) in replacements {
            result = result.replacingOccurrences(
                of: informal,
                with: formal,
                options: .caseInsensitive
            )
        }
        // Ensure it ends with a period
        if !result.hasSuffix(".") && !result.hasSuffix("!") && !result.hasSuffix("?") {
            result += "."
        }
        return result
    }

    private func makeFriendly(_ text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            ("Hello", "Hey"),
            ("Dear ", "Hi "),
            ("Sincerely", "Thanks"),
            ("Regards", "Cheers"),
            ("at your earliest convenience", "when you get a chance"),
            ("I would like to", "I'd love to"),
            ("Please be advised", "Just a heads up"),
            ("per our conversation", "like we talked about"),
        ]
        for (formal, friendly) in replacements {
            result = result.replacingOccurrences(
                of: formal,
                with: friendly,
                options: .caseInsensitive
            )
        }
        // Add a friendly touch if it ends with a period
        if result.hasSuffix(".") && !result.hasSuffix("!") {
            result = String(result.dropLast()) + "!"
        }
        return result
    }
}
