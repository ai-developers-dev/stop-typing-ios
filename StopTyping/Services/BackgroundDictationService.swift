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
    /// Fix 3.3: Non-nil when activation failed. DictationOverlayView shows
    /// a Retry button when this is set. Cleared on successful activation.
    @Published var activationError: String? = nil

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
        // If already active, verify the audio pipeline is healthy.
        // iOS may have deactivated our audio session while suspended — we need to recover.
        if isSessionActive {
            log("Session already active — verifying audio pipeline")
            reactivateAudioPipeline()
            return
        }

        log("Activating session...")

        // Mark session active AND write bootId synchronously, so even if the user
        // immediately backgrounds the app (before the async audio setup finishes),
        // the keyboard still sees a consistent state: sessionActive=true +
        // bootId=current. Without this, a fast-background left bootId=nil and the
        // keyboard incorrectly showed "Start ST" on return.
        defaults.writeHeartbeat()
        defaults.sessionActive = true
        defaults.bootId = SharedDefaults.currentBootID()
        defaults.audioLevel = 0
        DispatchQueue.main.async { self.isSessionActive = true }

        // Listen for keyboard signals (lightweight, safe on any thread)
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

        // Handle audio session interruptions (incoming calls, Siri, AND app suspension recovery)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            self?.handleAudioInterruption(notification)
        }

        // Handle audio engine config changes (route changes, wake from sleep)
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.log("AVAudioEngine config changed — restarting idle engine")
            self?.reactivateAudioPipeline()
        }

        // Heavy audio work OFF the main thread — this is what was blocking the UI.
        // Uses an async Task so we can await the speech authorization result properly
        // (Fix 2.1) instead of fire-and-forget.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Fix 2.1: Await speech recognition permission before activating the audio pipeline.
            // On fresh install this was a race — we'd try to start the engine before the user
            // had granted permission, resulting in a "works but doesn't work" state.
            let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status)
                }
            }
            self.log("Speech auth result: \(speechStatus.rawValue)")

            if speechStatus != .authorized {
                self.log("⚠️ Speech not authorized — activation will still set up audio, but startRecording will fail until user grants permission")
                // Don't clear the session — user might grant permission later in Settings.
                // startRecording's guards will handle it and emit recordingFailed.
            }

            // Fix 2.2: Set up audio session with retry/backoff.
            // On fresh install, the audio daemon can briefly reject setActive while
            // permissions propagate. Retry up to 3 times with 300ms backoff.
            let audioSetupSucceeded = await self.setupAudioSessionWithRetry(attempts: 3, backoffMs: 300)

            guard audioSetupSucceeded else {
                self.log("❌ Audio session setup FAILED after retries")
                // Fix 3.3: Surface the error to the UI so user can retry
                let errorMsg: String
                if speechStatus != .authorized {
                    errorMsg = "Microphone or speech permission is required. Open Settings and enable them, then tap Retry."
                } else {
                    errorMsg = "Couldn't start microphone. Tap Retry."
                }
                await MainActor.run {
                    self.defaults.clearSession()
                    self.isSessionActive = false
                    self.activationError = errorMsg
                }
                return
            }

            self.startIdleAudioEngine()

            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
            timer.schedule(deadline: .now(), repeating: 2.0)
            timer.setEventHandler { [weak self] in self?.defaults.writeHeartbeat() }
            timer.resume()
            self.heartbeatTimer = timer

            // bootId is already written synchronously at the top of activateSession()
            // so we don't need to write it again here.

            self.log("✅ Session ACTIVE")

            // Fix 3.3: Clear any prior activation error — activation succeeded
            await MainActor.run { self.activationError = nil }

            // Start Live Activity for Dynamic Island
            self.startLiveActivity()
        }
    }

    // MARK: - Retry Activation (Fix 3.3)
    //
    // User-facing retry path when activation fails. Clears error state, resets
    // in-memory flags, and re-runs activateSession. Safe to call from main thread.

    func retryActivation() {
        log("🔄 Retry activation requested")
        DispatchQueue.main.async {
            self.activationError = nil
            self.isSessionActive = false
        }
        defaults.sessionActive = false
        // Tiny delay to let the @Published updates propagate before re-entering activate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.activateSession()
        }
    }

    // MARK: - Cold-Start Warmup (Fix 3.2)
    //
    // Fired once on first scene .active. Pre-touches expensive system APIs so
    // the user's first activation tap doesn't pay cold-start cost. This is
    // READ-ONLY — it never requests permissions or starts the engine, so it has
    // no side effects on the user.

    func warmUpColdStart() async {
        // If real activation already ran, skip (no cost, but log confirms)
        guard !isSessionActive else {
            log("🔥 Warmup skipped — session already active")
            return
        }

        log("🔥 Warming up cold-start services...")

        // 1. Touch SharedDefaults keys — pulls App Group container into memory
        _ = defaults.sessionActive
        _ = defaults.isRecording
        _ = defaults.heartbeat

        // 2. Touch AVAudioSession singleton — wakes the AV daemon without
        //    changing category or activating. Safe, no side effects.
        _ = AVAudioSession.sharedInstance().currentRoute

        // 3. Touch SFSpeechRecognizer — initializes the Speech framework
        _ = speechRecognizer?.isAvailable

        // 4. Read current speech authorization status (does NOT prompt)
        let status = SFSpeechRecognizer.authorizationStatus()
        log("🔥 Warmup complete (speech auth status: \(status.rawValue))")
    }

    /// Fix 2.2: Tries to configure + activate the AVAudioSession, retrying on failure.
    /// Returns true on success, false if all attempts failed.
    private func setupAudioSessionWithRetry(attempts: Int, backoffMs: Int) async -> Bool {
        for attempt in 1...attempts {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .measurement,
                                        options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                log("Audio session active (attempt \(attempt)/\(attempts))")
                return true
            } catch {
                log("Audio session setup attempt \(attempt)/\(attempts) failed: \(error.localizedDescription)")
                if attempt < attempts {
                    try? await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
                }
            }
        }
        return false
    }

    // MARK: - Audio Interruption Handling
    //
    // Per Apple docs: "Starting in iOS 10, the system deactivates an app's audio session
    // when it suspends the app process. When the app starts running again, it receives an
    // interruption notification that the system has deactivated its audio session."
    // We handle this by reactivating the audio pipeline on interruption .ended.

    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            let wasSuspended = (userInfo[AVAudioSessionInterruptionWasSuspendedKey] as? Bool) ?? false
            log("Audio interruption BEGAN (wasSuspended: \(wasSuspended))")
            // Don't change session state — we want to recover, not tear down

        case .ended:
            log("Audio interruption ENDED")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                log("  shouldResume: \(options.contains(.shouldResume))")
            }
            // Always reactivate — iOS tells us we can resume
            reactivateAudioPipeline()

        @unknown default:
            break
        }
    }

    /// Self-healing audio pipeline restart. Safe to call repeatedly.
    /// Reactivates AVAudioSession and restarts the idle engine from scratch.
    private func reactivateAudioPipeline() {
        // Don't interfere with active recording
        if isCurrentlyRecording {
            log("reactivateAudioPipeline: skipping (recording in progress)")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .measurement,
                                        options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                self.log("Audio session reactivated")
            } catch {
                self.log("Audio session reactivate FAILED: \(error)")
                return
            }

            self.startIdleAudioEngine()
            self.defaults.writeHeartbeat()
            // Refresh bootId on every successful recovery — safety net in case
            // the initial activation's synchronous bootId write got wiped somehow.
            self.defaults.bootId = SharedDefaults.currentBootID()
        }
    }

    // MARK: - App Lifecycle

    func handleBackground() {
        guard isSessionActive else { return }
        log("App entering background — session stays active")

        // Session stays active, Live Activity stays visible, sessionActive stays true.
        // The heartbeat timer will be suspended by iOS automatically — that's fine
        // because the keyboard now checks sessionActive (not heartbeat) to decide state.

        // If actively recording, clean up since the audio engine will be suspended
        if isCurrentlyRecording {
            log("Was recording when backgrounded — cleaning up")
            stopEngine()
            recognitionRequest?.endAudio()

            let rawTranscript = currentTranscript
            cleanupRecording()
            updateLiveActivity(isRecording: false)

            // Save whatever transcript we had
            if !rawTranscript.isEmpty {
                Task {
                    let cleaned = await GroqService.shared.cleanTranscript(rawTranscript)
                    await MainActor.run {
                        self.lastTranscript = cleaned
                        self.defaults.saveTranscript(cleaned)
                        TranscriptHistoryStore.shared.add(TranscriptItem(text: cleaned))
                        self.darwin.post(DarwinNotificationName.transcriptReady)
                        self.log("Saved in-progress transcript on background")
                    }
                }
            }

            startIdleAudioEngine()
        }
    }

    func handleForeground() {
        guard isSessionActive else { return }
        log("App returning to foreground — refreshing pipeline")

        // Write heartbeat immediately so timestamp is fresh
        defaults.writeHeartbeat()

        // Restart heartbeat timer if it was suspended
        if heartbeatTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
            timer.schedule(deadline: .now(), repeating: 2.0)
            timer.setEventHandler { [weak self] in self?.defaults.writeHeartbeat() }
            timer.resume()
            heartbeatTimer = timer
        }

        // ALWAYS reactivate audio pipeline — iOS may have deactivated it during suspend
        reactivateAudioPipeline()

        // Restart Live Activity if it was dismissed
        if currentActivity == nil {
            startLiveActivity()
        }
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
    //
    // Darwin observer entry point. Kicks off the async recording path and returns
    // immediately so we don't block the notification delivery thread.

    private func startRecording() {
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.startRecordingAsync()
        }
    }

    /// Fix 2.3 + 2.4 + 2.5: robust startRecording with retry, ACK, and task cleanup.
    private func startRecordingAsync() async {
        guard isSessionActive else {
            log("❌ startRecording blocked: session not active")
            emitRecordingFailed()
            return
        }
        guard !isCurrentlyRecording else {
            log("⚠️ startRecording called but already recording — ignoring")
            // Don't emit failed — we're in a valid state, the keyboard's UI is correct
            return
        }

        // Fix 2.3: Wait for speechRecognizer to be ready. On fresh install the recognizer
        // may briefly be nil or unavailable while Speech framework warms up.
        let recognizer: SFSpeechRecognizer
        if let ready = await waitForSpeechRecognizerReady(timeoutMs: 2000) {
            recognizer = ready
        } else {
            log("❌ Speech recognizer never became available — aborting")
            emitRecordingFailed()
            return
        }

        log("Starting recording...")

        // Full audio session setup with retry. This is cheap if the category
        // and active state are already correct, but it also recovers from the
        // case where the user backgrounded the app mid-activation — the initial
        // setup Task may never have completed, so we can't assume the audio
        // session is properly configured.
        let audioReady = await setupAudioSessionWithRetry(attempts: 3, backoffMs: 200)
        guard audioReady else {
            log("❌ Audio session not ready for recording")
            emitRecordingFailed()
            return
        }

        // Fix 2.5: Cancel any leftover recognition task from a previous recording.
        // Without this, the Speech framework can hang onto a stale task and silently
        // reject the new one.
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        currentTranscript = ""
        defaults.isRecording = true
        defaults.audioLevel = 0
        previousAudioLevel = 0
        await MainActor.run { self.isCurrentlyRecording = true }

        // Stop idle engine
        if let engine = audioEngine, engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
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
            log("✅ Recording engine STARTED")
            updateLiveActivity(isRecording: true)
            // Fix 2.4: Tell the keyboard recording actually started successfully
            darwin.post(DarwinNotificationName.recordingStarted)
        } catch {
            log("❌ Recording engine FAILED: \(error.localizedDescription)")
            defaults.isRecording = false
            await MainActor.run { self.isCurrentlyRecording = false }
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            startIdleAudioEngine()
            emitRecordingFailed()
        }
    }

    /// Fix 2.3: Poll for speechRecognizer availability. Returns the recognizer if it
    /// becomes ready within the timeout, nil otherwise.
    private func waitForSpeechRecognizerReady(timeoutMs: Int) async -> SFSpeechRecognizer? {
        // Quick path — already ready
        if let r = speechRecognizer, r.isAvailable {
            return r
        }

        log("Speech recognizer not ready — waiting up to \(timeoutMs)ms")
        let pollIntervalMs = 100
        let maxPolls = timeoutMs / pollIntervalMs

        for _ in 0..<maxPolls {
            try? await Task.sleep(nanoseconds: UInt64(pollIntervalMs) * 1_000_000)
            if let r = speechRecognizer, r.isAvailable {
                log("Speech recognizer became ready")
                return r
            }
        }

        return nil
    }

    /// Fix 2.4: Emit the recordingFailed ACK so the keyboard can reset its local UI.
    /// Also clears defaults.isRecording so polling observers see the correct state.
    private func emitRecordingFailed() {
        defaults.isRecording = false
        defaults.audioLevel = 0
        darwin.post(DarwinNotificationName.recordingFailed)
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

        // Update Live Activity and recording state immediately — don't wait for transcript processing
        defaults.isRecording = false
        DispatchQueue.main.async { self.isCurrentlyRecording = false }
        updateLiveActivity(isRecording: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let rawTranscript = self.currentTranscript
            self.log("Raw ASR: '\(rawTranscript.prefix(80))'")

            self.recognitionTask?.cancel()
            self.recognitionTask = nil
            self.recognitionRequest = nil
            self.currentTranscript = ""

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
