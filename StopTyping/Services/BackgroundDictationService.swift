import AVFoundation
import Speech
import UIKit
import Foundation

/// Manages the persistent background dictation session.
/// Keeps the app alive by running the audio engine continuously.
/// Only attaches speech recognition when the user taps mic.
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
        print("[BGDictation] \(msg)")
        defaults.appendLog("APP: \(msg)")
        DispatchQueue.main.async {
            self.debugLog = self.defaults.debugLog
        }
    }

    // MARK: - Activate Session

    func activateSession() {
        guard !isSessionActive else {
            log("Session already active")
            return
        }

        log("Activating session...")

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.log("Speech auth: \(status.rawValue)")
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
            log("Audio session active")
        } catch {
            log("Audio session FAILED: \(error)")
            return
        }

        // Start audio engine immediately — this keeps the app alive in background.
        // We capture audio but discard it until startDictation is received.
        startIdleAudioEngine()

        // Start heartbeat
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.defaults.writeHeartbeat()
        }
        timer.resume()
        heartbeatTimer = timer

        defaults.writeHeartbeat()
        defaults.sessionActive = true
        isSessionActive = true
        log("Session ACTIVE — audio engine running, heartbeat started")

        // Listen for keyboard signals
        darwin.observe(DarwinNotificationName.startDictation) { [weak self] in
            self?.log("Received startDictation")
            self?.startRecording()
        }
        darwin.observe(DarwinNotificationName.stopDictation) { [weak self] in
            self?.log("Received stopDictation")
            self?.stopRecording()
        }

        // Clean up on app termination
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.deactivateSession()
        }
    }

    // MARK: - Idle Audio Engine

    /// Starts the audio engine with a tap that discards audio.
    /// This keeps the background audio session truly active so iOS doesn't suspend us.
    private func startIdleAudioEngine() {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Install a tap that does nothing — just keeps audio flowing
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { _, _ in
            // Intentionally empty — audio is discarded in idle mode.
            // This tap keeps the audio session alive in the background.
        }

        engine.prepare()
        do {
            try engine.start()
            self.audioEngine = engine
            log("Idle audio engine STARTED (keeping app alive)")
        } catch {
            log("Idle audio engine FAILED: \(error)")
        }
    }

    // MARK: - Deactivate Session

    func deactivateSession() {
        log("Deactivating session")
        stopRecordingInternal()

        if let engine = audioEngine, engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil

        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        darwin.removeAllObservers()
        defaults.clearSession()
        isSessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false)
        log("Session deactivated")
    }

    // MARK: - Start Recording (speech recognition)

    private func startRecording() {
        guard isSessionActive else {
            log("Cannot record: session not active")
            return
        }
        guard !isCurrentlyRecording else {
            log("Already recording")
            return
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            log("Speech recognizer NOT available")
            return
        }

        log("Starting speech recognition...")

        currentTranscript = ""
        defaults.isRecording = true
        DispatchQueue.main.async { self.isCurrentlyRecording = true }

        // Stop idle engine — we'll restart with speech recognition
        if let engine = audioEngine, engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            log("Stopped idle engine")
        }

        // Create fresh engine for recording
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
            log("On-device recognition")
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.currentTranscript = result.bestTranscription.formattedString
            }
            if let error {
                self.log("Recognition error: \(error.localizedDescription)")
            }
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            log("Recording engine STARTED — listening for speech")
        } catch {
            log("Recording engine FAILED: \(error)")
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
            self.log("Final transcript: '\(transcript.prefix(80))'")

            self.recognitionTask?.cancel()
            self.recognitionTask = nil
            self.recognitionRequest = nil

            self.defaults.isRecording = false
            self.isCurrentlyRecording = false

            if !transcript.isEmpty {
                self.lastTranscript = transcript
                self.defaults.saveTranscript(transcript)
                self.log("Saved to App Group")

                DispatchQueue.main.async {
                    TranscriptHistoryStore.shared.add(TranscriptItem(text: transcript))
                }

                self.darwin.post(DarwinNotificationName.transcriptReady)
                self.log("Posted transcriptReady")
            } else {
                self.log("Empty transcript")
            }

            // Restart idle engine to keep app alive
            self.startIdleAudioEngine()
        }
    }

    private func stopRecordingInternal() {
        if let engine = audioEngine, engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        recognitionRequest?.endAudio()
    }
}
