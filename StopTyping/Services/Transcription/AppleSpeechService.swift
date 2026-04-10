import AVFoundation
import Speech
import Foundation

final class AppleSpeechService: TranscriptionService, ObservableObject {
    @Published private(set) var state: TranscriptionState = .idle

    private lazy var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private lazy var audioEngine = AVAudioEngine()
    private var currentTranscript = ""

    func startRecording() async throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .error("Speech recognizer not available")
            throw TranscriptionError.notAvailable
        }

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw TranscriptionError.requestCreationFailed
        }
        recognitionRequest.shouldReportPartialResults = true

        // On-device recognition when available (iOS 13+)
        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        // Start recognition task
        currentTranscript = ""
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                self.currentTranscript = result.bestTranscription.formattedString
                self.state = .recording
            }

            if let error {
                self.state = .error(error.localizedDescription)
                self.stopAudioEngine()
            }
        }

        // Install audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        state = .recording
    }

    func stopRecording() async throws -> String {
        state = .processing
        stopAudioEngine()
        recognitionRequest?.endAudio()

        // Wait briefly for final results
        try await Task.sleep(nanoseconds: 500_000_000)

        let transcript = currentTranscript
        cleanup()

        if transcript.isEmpty {
            state = .error("No speech detected")
            throw TranscriptionError.noSpeechDetected
        }

        state = .completed(transcript)
        return transcript
    }

    func cancel() {
        stopAudioEngine()
        cleanup()
        state = .idle
    }

    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func cleanup() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
}

enum TranscriptionError: LocalizedError {
    case notAvailable
    case requestCreationFailed
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "Speech recognition is not available on this device."
        case .requestCreationFailed: return "Could not create speech recognition request."
        case .noSpeechDetected: return "No speech was detected. Please try again."
        }
    }
}
