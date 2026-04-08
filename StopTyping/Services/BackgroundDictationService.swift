import AVFoundation
import Speech
import UIKit
import Foundation

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
    private var audioLevelUpdateCounter = 0

    private init() {}

    private func log(_ msg: String) {
        print("[BGDictation] \(msg)")
        defaults.appendLog("APP: \(msg)")
        DispatchQueue.main.async { self.debugLog = self.defaults.debugLog }
    }

    // MARK: - Activate Session

    func activateSession() {
        guard !isSessionActive else {
            log("Session already active")
            return
        }

        log("Activating session...")

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async { self?.log("Speech auth: \(status.rawValue)") }
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            log("Audio session active")
        } catch {
            log("Audio session FAILED: \(error)")
            return
        }

        startIdleAudioEngine()

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now(), repeating: 2.0)
        timer.setEventHandler { [weak self] in self?.defaults.writeHeartbeat() }
        timer.resume()
        heartbeatTimer = timer

        defaults.writeHeartbeat()
        defaults.sessionActive = true
        defaults.audioLevel = 0
        isSessionActive = true

        // Listen for keyboard signals
        darwin.observe(DarwinNotificationName.startDictation) { [weak self] in
            self?.log("Received: startDictation")
            self?.startRecording()
        }
        darwin.observe(DarwinNotificationName.stopDictation) { [weak self] in
            self?.log("Received: stopDictation")
            self?.stopRecording()
        }
        darwin.observe(DarwinNotificationName.cancelDictation) { [weak self] in
            self?.log("Received: cancelDictation")
            self?.cancelRecording()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.deactivateSession() }

        log("Session ACTIVE")
    }

    // MARK: - Idle Audio Engine

    private func startIdleAudioEngine() {
        // Stop any existing engine first
        if let engine = audioEngine, engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { _, _ in
            // Discard audio — just keeping the session alive
        }

        engine.prepare()
        do {
            try engine.start()
            self.audioEngine = engine
            log("Idle engine started")
        } catch {
            log("Idle engine FAILED: \(error)")
        }
    }

    // MARK: - Deactivate

    func deactivateSession() {
        log("Deactivating session")
        cleanupRecording()
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
    }

    // MARK: - Start Recording

    private func startRecording() {
        guard isSessionActive, !isCurrentlyRecording else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            log("Speech recognizer unavailable")
            return
        }

        log("Starting recording...")

        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log("Re-activate failed: \(error)")
        }

        currentTranscript = ""
        defaults.isRecording = true
        defaults.audioLevel = 0
        audioLevelUpdateCounter = 0
        DispatchQueue.main.async { self.isCurrentlyRecording = true }

        // Stop idle engine
        if let engine = audioEngine, engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result { self?.currentTranscript = result.bestTranscription.formattedString }
            if let error { self?.log("Recognition error: \(error.localizedDescription)") }
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            // Compute audio level and write to App Group every ~5th callback (~200ms)
            self?.updateAudioLevel(buffer: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            log("Recording engine STARTED")
        } catch {
            log("Recording engine FAILED: \(error)")
            defaults.isRecording = false
            DispatchQueue.main.async { self.isCurrentlyRecording = false }
            startIdleAudioEngine()
        }
    }

    // MARK: - Audio Level Metering

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        audioLevelUpdateCounter += 1
        // Only update every 5th buffer (~200ms at 1024 samples/44100Hz)
        guard audioLevelUpdateCounter % 5 == 0 else { return }

        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        // Normalize: rms of speech is typically 0.01-0.3, scale to 0-1
        let level = min(1.0, rms * 5.0)
        defaults.audioLevel = level
    }

    // MARK: - Stop Recording (save transcript)

    private func stopRecording() {
        guard isCurrentlyRecording else {
            log("Not recording, nothing to stop")
            return
        }

        log("Stopping recording (save)...")
        stopEngine()
        recognitionRequest?.endAudio()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            let rawTranscript = self.currentTranscript
            self.log("Raw ASR: '\(rawTranscript.prefix(80))'")

            self.cleanupRecording()

            if !rawTranscript.isEmpty {
                // Send to Groq LLM for cleanup (async, with fallback to raw)
                Task {
                    let cleanedTranscript = await GroqService.shared.cleanTranscript(rawTranscript)
                    self.log("LLM cleaned: '\(cleanedTranscript.prefix(80))'")

                    await MainActor.run {
                        self.lastTranscript = cleanedTranscript
                        self.defaults.saveTranscript(cleanedTranscript)
                        TranscriptHistoryStore.shared.add(TranscriptItem(text: cleanedTranscript))
                        self.darwin.post(DarwinNotificationName.transcriptReady)
                        self.log("Cleaned transcript saved, notified keyboard")
                    }
                }
            } else {
                self.log("Empty transcript")
            }

            self.defaults.audioLevel = 0
            self.startIdleAudioEngine()
        }
    }

    // MARK: - Cancel Recording (discard, restart immediately)

    private func cancelRecording() {
        guard isCurrentlyRecording else { return }

        log("Canceling recording (discard)")
        stopEngine()
        cleanupRecording()
        defaults.audioLevel = 0

        // Restart idle engine immediately — no delay
        startIdleAudioEngine()
        log("Cancel complete, idle engine restarted")
    }

    // MARK: - Helpers

    private func stopEngine() {
        if let engine = audioEngine, engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    private func cleanupRecording() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        defaults.isRecording = false
        currentTranscript = ""
        DispatchQueue.main.async { self.isCurrentlyRecording = false }
    }
}
