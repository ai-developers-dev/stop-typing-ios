import Foundation
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var transcriptionState: TranscriptionState = .idle
    @Published var currentTranscript: String = ""
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    private lazy var transcriptionService = AppleSpeechService()
    private lazy var sharedState = SharedStateManager.shared
    private lazy var permissions = PermissionsManager()

    var isRecording: Bool { transcriptionState == .recording }
    var isProcessing: Bool { transcriptionState == .processing }

    func startFlow() async {
        // Check permissions first
        if !permissions.microphoneGranted {
            let granted = await permissions.requestMicrophone()
            guard granted else {
                errorMessage = "Microphone access is required. Please enable it in Settings."
                showError = true
                return
            }
        }

        if !permissions.speechGranted {
            let granted = await permissions.requestSpeechRecognition()
            guard granted else {
                errorMessage = "Speech recognition access is required. Please enable it in Settings."
                showError = true
                return
            }
        }

        do {
            try await transcriptionService.startRecording()
            transcriptionState = .recording
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            transcriptionState = .idle
        }
    }

    func stopFlow() async {
        do {
            transcriptionState = .processing
            let transcript = try await transcriptionService.stopRecording()
            currentTranscript = transcript
            transcriptionState = .completed(transcript)

            // Save to shared storage for keyboard extension
            sharedState.saveTranscript(transcript)

            // Save to history
            TranscriptHistoryStore.shared.add(TranscriptItem(text: transcript))
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            transcriptionState = .idle
        }
    }

    func cancelFlow() {
        transcriptionService.cancel()
        transcriptionState = .idle
        currentTranscript = ""
    }

    func copyTranscript() {
        UIPasteboard.general.string = currentTranscript
    }

    func reset() {
        transcriptionState = .idle
        currentTranscript = ""
    }
}
