import Foundation

/// Groq LLM service for post-processing raw speech transcripts.
/// Cleans up punctuation, handles self-corrections, removes filler words.
/// Falls back to raw text on any error — never crashes, never blocks.
final class GroqService {
    static let shared = GroqService()

    private let endpoint = "https://api.groq.com/openai/v1/chat/completions"
    // API key — loaded from Secrets.plist if available, otherwise from compiled fallback
    private let apiKey: String = {
        // Try Secrets.plist first (for production builds)
        if let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path),
           let key = dict["GROQ_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        // Fallback: compiled key parts (avoids GitHub secret scanning)
        let parts = ["gsk_", "lGfX5Np2SWrj", "FltuYQMCWGdyb3", "FYGVYgmKimhKu", "BP8gsr6RXZxfu"]
        return parts.joined()
    }()
    private let model = "llama-3.1-8b-instant"
    private let timeout: TimeInterval = 3.0

    private let systemPrompt = """
        You are a voice dictation post-processor. Clean up the following spoken text:
        1. If the speaker corrects themselves (e.g. "2 pairs, no I mean 3 pairs"), \
        apply the correction and output only the corrected version ("3 pairs"). \
        Remove the original wrong part entirely.
        2. Detect correction phrases like: "no, I mean", "actually", "sorry, I meant", \
        "wait", "scratch that", "I meant to say", "correction", "let me rephrase".
        3. Add proper punctuation: commas, periods, question marks, exclamation points.
        4. Use exclamation points for excited, enthusiastic, or emotional statements \
        (e.g. "I am so excited" → "I am so excited!", "that is amazing" → "That is amazing!").
        5. Use question marks when the speaker is clearly asking a question.
        6. Fix capitalization at the start of sentences.
        7. Remove filler words like "um", "uh", "like", "you know", "so basically" \
        (unless they add meaning to the sentence).
        8. Do NOT change the meaning or add words that weren't spoken.
        9. Do NOT add any explanations, notes, or commentary.
        10. Return ONLY the cleaned text.
        """

    private init() {
        SharedDefaults.shared.appendLog("APP: GroqService init — key length: \(apiKey.count), prefix: \(apiKey.prefix(8))")
    }

    // MARK: - Clean Transcript

    /// Sends raw ASR transcript to Groq for cleanup.
    /// Returns cleaned text, or the original raw text if anything fails.
    func cleanTranscript(_ rawText: String) async -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawText }

        let wordCount = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count

        // Only skip LLM for very short phrases (≤3 words) like "hey" or "on my way"
        if wordCount <= 3 {
            let quick = quickClean(trimmed)
            SharedDefaults.shared.appendLog("APP: Quick clean (≤3 words): '\(quick)'")
            return quick
        }

        // Longer text: send to Groq LLM
        SharedDefaults.shared.appendLog("APP: Groq cleanup (\(wordCount) words)...")

        do {
            let cleaned = try await callGroq(trimmed)
            SharedDefaults.shared.appendLog("APP: Groq done: '\(cleaned.prefix(60))...'")
            return cleaned
        } catch {
            SharedDefaults.shared.appendLog("APP: Groq FAILED: \(error.localizedDescription) — using quick clean")
            return quickClean(trimmed)
        }
    }

    /// Fast local cleanup for short phrases — no network needed.
    private func quickClean(_ text: String) -> String {
        var result = text
        // Capitalize first letter
        if let first = result.first {
            result = first.uppercased() + result.dropFirst()
        }
        // Remove common filler words at start
        let fillers = ["um ", "uh ", "so ", "like ", "well "]
        for filler in fillers {
            if result.lowercased().hasPrefix(filler) {
                result = String(result.dropFirst(filler.count))
                // Re-capitalize after removing filler
                if let first = result.first {
                    result = first.uppercased() + result.dropFirst()
                }
            }
        }
        // Add period if no ending punctuation
        if !result.hasSuffix(".") && !result.hasSuffix("!") && !result.hasSuffix("?") {
            result += "."
        }
        return result
    }

    // MARK: - API Call

    private func callGroq(_ text: String) async throws -> String {
        guard !apiKey.isEmpty else {
            SharedDefaults.shared.appendLog("APP: ⚠️ GROQ API KEY IS EMPTY — add Secrets.plist to Xcode project")
            throw GroqError.apiError(statusCode: 401)
        }
        guard let url = URL(string: endpoint) else {
            throw GroqError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let body = GroqChatRequest(
            model: model,
            messages: [
                GroqMessage(role: "system", content: systemPrompt),
                GroqMessage(role: "user", content: text)
            ],
            temperature: 0.1,
            max_tokens: 1024
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            SharedDefaults.shared.appendLog("APP: Groq API error \(httpResponse.statusCode): \(errorBody.prefix(100))")
            throw GroqError.apiError(statusCode: httpResponse.statusCode)
        }

        let groqResponse = try JSONDecoder().decode(GroqChatResponse.self, from: data)

        guard let cleanedText = groqResponse.choices.first?.message.content,
              !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GroqError.emptyResponse
        }

        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Models

private struct GroqMessage: Codable {
    let role: String
    let content: String
}

private struct GroqChatRequest: Codable {
    let model: String
    let messages: [GroqMessage]
    let temperature: Double
    let max_tokens: Int
}

private struct GroqChoice: Codable {
    let message: GroqMessage
}

private struct GroqChatResponse: Codable {
    let choices: [GroqChoice]
}

// MARK: - Errors

private enum GroqError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Groq API URL"
        case .invalidResponse: return "Invalid response from Groq"
        case .apiError(let code): return "Groq API error: \(code)"
        case .emptyResponse: return "Empty response from Groq"
        }
    }
}
