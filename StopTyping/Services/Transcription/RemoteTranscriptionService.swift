import AVFoundation
import Foundation

/// Placeholder for a remote transcription API (e.g., Groq, Whisper API, Deepgram).
/// Records audio locally, sends the audio file to a remote endpoint for transcription.
final class RemoteTranscriptionService: TranscriptionService, ObservableObject {
    @Published private(set) var state: TranscriptionState = .idle

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("recording.m4a")
    }

    // TODO: Replace with your actual API endpoint and key
    private let apiEndpoint = "https://api.example.com/transcribe"
    private let apiKey = "YOUR_API_KEY"

    func startRecording() async throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement)
        try audioSession.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        audioRecorder?.record()
        state = .recording
    }

    func stopRecording() async throws -> String {
        audioRecorder?.stop()
        state = .processing

        let audioData = try Data(contentsOf: recordingURL)
        let transcript = try await sendToAPI(audioData: audioData)

        // Clean up temp file
        try? FileManager.default.removeItem(at: recordingURL)

        state = .completed(transcript)
        return transcript
    }

    func cancel() {
        audioRecorder?.stop()
        try? FileManager.default.removeItem(at: recordingURL)
        state = .idle
    }

    private func sendToAPI(audioData: Data) async throws -> String {
        var request = URLRequest(url: URL(string: apiEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TranscriptionError.notAvailable
        }

        // Adjust JSON parsing to match your API's response format
        struct APIResponse: Codable { let text: String }
        let result = try JSONDecoder().decode(APIResponse.self, from: data)
        return result.text
    }
}
