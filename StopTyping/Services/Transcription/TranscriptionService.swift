import Foundation

enum TranscriptionState: Equatable {
    case idle
    case recording
    case processing
    case completed(String)
    case error(String)
}

/// Protocol for swappable transcription backends.
protocol TranscriptionService {
    var state: TranscriptionState { get }
    func startRecording() async throws
    func stopRecording() async throws -> String
    func cancel()
}
