import AVFoundation
import Speech
import UIKit
import Foundation

/// Manages the persistent background dictation session.
final class BackgroundDictationService: ObservableObject {
    static let shared = BackgroundDictationService()

    @Published var isSessionActive = false
    @Published var isCurrentlyRecording = false
    @Published var lastTranscript = ""
    @Published var debugLog = ""

    private var heartbeatTimer: DispatchSourceTimer?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var currentTranscript = ""
    private let defaults = SharedDefaults.shared
    private let darwin = DarwinNotificationCenter.shared

    private init() {}

    private func log(_ msg: String) {
        print("[BackgroundDictation] \(msg)")
        defaults.appendLog("APP: \(msg)")
        DispatchQueue.main.async {
            self.debugLog = self.defaults.debugLog
        }
    }

    // MARK: - Activate Session

    func activateSession() {
        guard !isSessionActive else {
            log("Session already active, skipping")
            return
        }

        log("Activating session...")

        // Request speech recognition permission
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.log("Speech auth status: \(status.rawValue)")
            }
        }

        // Set up audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            log("Audio session activated: category=\(session.category.rawValue)")
        } catch {
            log("Audio session FAILED: \(error.localizedDescription)")
            return
        }

        // Start heartbeat using GCD timer (works in background, unlike Timer)
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: 3.0)
        timer.setEventHandler { [weak self] in
            self?.defaults.writeHeartbeat()
        }
        timer.resume()
        heartbeatTimer = timer

        defaults.writeHeartbeat()
        defaults.sessionActive = true
        isSessionActive = true
        log("Heartbeat started, session active")

        // Listen for keyboard signals
        darwin.observe(DarwinNotificationName.startDictation) { [weak self] in
            self?.log("Received startDictation from keyboard")
            self?.startRecording()
        }
        darwin.observe(DarwinNotificationName.stopDictation) { [weak self] in
            self?.log("Received stopDictation from keyboard")
            self?.stopRecording()
        }

        // Clean up on app termination
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.log("App terminating, deactivating session")
            self?.deactivateSession()
        }

        log("Session fully activated, waiting for keyboard signals")
    }

    // MARK: - Deactivate Session

    func deactivateSession() {
        log("Deactivating session...")
        stopRecordingInternal()
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        darwin.removeAllObservers()
        defaults.clearSession()
        isSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false)
        log("Session deactivated")
    }

    // MARK: - Start Recording

    private func startRecording() {
        guard isSessionActive else {
            log("Cannot record: session not active")
            return
        }
        guard !isCurrentlyRecording else {
            log("Already recording, skipping")
            return
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            log("Speech recognizer NOT available")
            return
        }

        log("Starting recording...")

        // Re-activate audio session (may have been interrupted)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(true)
            log("Audio session re-activated")
        } catch {
            log("Audio session re-activation failed: \(error)")
        }

        currentTranscript = ""
        defaults.isRecording = true

        DispatchQueue.main.async {
            self.isCurrentlyRecording = true
        }

        // Create fresh audio engine each time
        let engine = AVAudioEngine()
        self.audioEngine = engine

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            log("Failed to create recognition request")
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
            log("Using on-device recognition")
        } else {
            log("Using server-based recognition")
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.currentTranscript = result.bestTranscription.formattedString
                self.log("Partial: \(self.currentTranscript.prefix(50))...")
            }
            if let error {
                self.log("Recognition error: \(error.localizedDescription)")
            }
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        log("Recording format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            log("Audio engine STARTED — listening for speech")
        } catch {
            log("Audio engine start FAILED: \(error.localizedDescription)")
            defaults.isRecording = false
            DispatchQueue.main.async { self.isCurrentlyRecording = false }
        }
    }

    // MARK: - Stop Recording

    private func stopRecording() {
        log("Stopping recording...")
        stopRecordingInternal()

        // Wait for final results
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }

            let transcript = self.currentTranscript
            self.log("Final transcript: '\(transcript)'")

            self.recognitionTask?.cancel()
            self.recognitionTask = nil
            self.recognitionRequest = nil

            self.defaults.isRecording = false
            self.isCurrentlyRecording = false

            if !transcript.isEmpty {
                self.lastTranscript = transcript
                self.defaults.saveTranscript(transcript)
                self.log("Transcript saved to App Group")

                DispatchQueue.main.async {
                    TranscriptHistoryStore.shared.add(TranscriptItem(text: transcript))
                }

                self.darwin.post(DarwinNotificationName.transcriptReady)
                self.log("Posted transcriptReady notification")
            } else {
                self.log("No transcript captured")
            }
        }
    }

    private func stopRecordingInternal() {
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            log("Audio engine stopped")
        }
        recognitionRequest?.endAudio()
    }
}
