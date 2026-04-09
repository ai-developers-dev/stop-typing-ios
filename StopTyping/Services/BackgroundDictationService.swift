import AVFoundation
import Speech
import UIKit
import Foundation
import Accelerate
import ActivityKit

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
    private var previousAudioLevel: Float = 0
    private var currentActivity: Activity<StopTypingWidgetAttributes>?

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

        // Start Live Activity for Dynamic Island (non-blocking)
        startLiveActivity()
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        do {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                log("Live Activities not enabled on this device")
                return
            }

            let attrs = StopTypingWidgetAttributes(sessionId: UUID().uuidString)
            let state = StopTypingWidgetAttributes.ContentState(isRecording: false, mode: "Formal")

            currentActivity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            log("Live Activity started")
        } catch {
            log("Live Activity skipped: \(error.localizedDescription)")
            // Non-fatal — session works fine without Live Activity
        }
    }

    private func updateLiveActivity(isRecording: Bool) {
        guard let activity = currentActivity else { return }
        Task {
            let state = StopTypingWidgetAttributes.ContentState(isRecording: isRecording, mode: "Formal")
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    private func endLiveActivity() {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        log("Live Activity ended")
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
        endLiveActivity()
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
        previousAudioLevel = 0
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
            guard let self else { return }
            if let result {
                self.currentTranscript = result.bestTranscription.formattedString
                if result.isFinal {
                    self.log("ASR final result: '\(self.currentTranscript.prefix(60))'")
                }
            }
            if let error {
                self.log("Recognition error: \(error.localizedDescription)")
            }
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateAudioLevel(buffer: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            log("Recording engine STARTED")
            updateLiveActivity(isRecording: true)
        } catch {
            log("Recording engine FAILED: \(error)")
            defaults.isRecording = false
            DispatchQueue.main.async { self.isCurrentlyRecording = false }
            startIdleAudioEngine()
        }
    }

    // MARK: - Audio Level Metering

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = vDSP_Length(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Hardware-accelerated RMS calculation
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, frameLength)

        // Exponential moving average smoothing — prevents jitter
        let alpha: Float = 0.3
        let smoothed = alpha * rms + (1 - alpha) * previousAudioLevel
        previousAudioLevel = smoothed

        let level = min(1.0, smoothed * 5.0)
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

        defaults.audioLevel = 0
        previousAudioLevel = 0

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let rawTranscript = self.currentTranscript
            self.log("Raw ASR: '\(rawTranscript.prefix(80))'")

            self.cleanupRecording()

            if !rawTranscript.isEmpty {
                Task {
                    let cleanedTranscript = await GroqService.shared.cleanTranscript(rawTranscript)
                    self.log("LLM cleaned: '\(cleanedTranscript.prefix(80))'")

                    await MainActor.run {
                        self.lastTranscript = cleanedTranscript
                        self.defaults.saveTranscript(cleanedTranscript)
                        TranscriptHistoryStore.shared.add(TranscriptItem(text: cleanedTranscript))
                        self.darwin.post(DarwinNotificationName.transcriptReady)
                        self.log("Cleaned transcript saved, notified keyboard")
                        self.updateLiveActivity(isRecording: false)
                    }
                }
            } else {
                self.log("Empty transcript")
            }

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
        previousAudioLevel = 0

        // Restart idle engine immediately — no delay
        startIdleAudioEngine()
        updateLiveActivity(isRecording: false)
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
