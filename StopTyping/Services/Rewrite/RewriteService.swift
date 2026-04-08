import Foundation

/// Protocol for swappable rewrite backends.
protocol RewriteService {
    func rewrite(_ text: String, mode: RewriteMode) async throws -> String
}
