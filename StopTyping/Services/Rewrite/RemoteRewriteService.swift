import Foundation

/// Placeholder for an AI-powered rewrite service (e.g., Claude, GPT, etc.).
final class RemoteRewriteService: RewriteService {

    // TODO: Replace with your actual API endpoint and key
    private let apiEndpoint = "https://api.example.com/rewrite"
    private let apiKey = "YOUR_API_KEY"

    func rewrite(_ text: String, mode: RewriteMode) async throws -> String {
        let prompt: String
        switch mode {
        case .shorten:
            prompt = "Shorten this text while keeping the key message: \(text)"
        case .professional:
            prompt = "Rewrite this text in a professional tone: \(text)"
        case .friendly:
            prompt = "Rewrite this text in a warm, friendly tone: \(text)"
        }

        var request = URLRequest(url: URL(string: apiEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["prompt": prompt, "max_tokens": 500]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw RewriteError.apiFailed
        }

        struct APIResponse: Codable { let text: String }
        let result = try JSONDecoder().decode(APIResponse.self, from: data)
        return result.text
    }
}

enum RewriteError: LocalizedError {
    case apiFailed

    var errorDescription: String? {
        switch self {
        case .apiFailed: return "The rewrite service is currently unavailable."
        }
    }
}
