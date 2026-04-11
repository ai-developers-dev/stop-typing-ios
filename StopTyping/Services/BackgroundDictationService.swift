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
    /// True after a successful foreground setCategory + setActive. iOS disallows
    /// setActive(true) from background when another app (Messages, etc.) holds
    /// audio priority, so we skip that call in startRecordingAsync when this is
    /// already true — the session is still configured from the foreground setup.
    private var audioSessionConfigured = false

    private init() {}

    private func log(_ msg: String) {
        print("[BGDictation] \(msg)")
        defaults.appendLog("APP: \(msg)")
        DispatchQueue.main.async { self.debugLog = self.defaults.debugLog }
    }

    // MARK: - Activate Session

    func activateSession() {
        log("🟢 activateSession() called — inMemory.isSessionActive=\(isSessionActive) defaults.sessionActive=\(defaults.sessionActive) defaults.isRecording=\(defaults.isRecording)")

        // If already active, verify the audio pipeline is healthy.
        // iOS may have deactivated our audio session while suspended — we need to recover.
        if isSessionActive {
            log("  session already active (in-memory) — verifying audio pipeline")
            reactivateAudioPipeline()
            return
        }

        log("  starting fresh activation...")

        // Mark session active AND write bootId synchronously, so even if the user
        // immediately backgrounds the app (before the async audio setup finishes),
        // the keyboard still sees a consistent state: sessionActive=true +
        // bootId=current. Without this, a fast-background left bootId=nil and the
        // keyboard incorrectly showed "Start ST" on return.
        defaults.writeHeartbeat()
        defaults.sessionActive = true
        defaults.bootId = SharedDefaults.currentBootID()
        defaults.audioLevel = 0
        defaults.isRecording = false  // clear any stale state from a crashed session

        // Set in-memory flag SYNCHRONOUSLY on main thread so any incoming Darwin
        // notification (startDictation) sees isSessionActive=true immediately.
        // Previously we used DispatchQueue.main.async which left a race window
        // where the keyboard could tap mic and startRecordingAsync would see
        // isSessionActive=false and bail silently.
        if Thread.isMainThread {
            self.isSessionActive = true
        } else {
            DispatchQueue.main.sync { self.isSessionActive = true }
        }

        // Listen for keyboard signals (lightweight, safe on any thread)
        darwin.observe(DarwinNotificationName.startDictation) { [weak self] in
            guard let self else { return }
            self.log("📥 Darwin: startDictation (inMemory.sessionActive=\(self.isSessionActive) isCurrentlyRecording=\(self.isCurrentlyRecording))")
            self.startRecording()
        }
        darwin.observe(DarwinNotificationName.stopDictation) { [weak self] in
            guard let self else { return }
            self.log("📥 Darwin: stopDictation")
            self.stopRecording()
        }
        darwin.observe(DarwinNotificationName.cancelDictation) { [weak self] in
            guard let self else { return }
            self.log("📥 Darwin: cancelDictation")
            self.cancelRecording()
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

    /// Fix 2.2: Tries to configure + activate the AVAudioSession with layered fallbacks.
    /// Returns true on success, false if all configs failed.
    ///
    /// OSStatus 560557684 = 'int!' = AVAudioSession.ErrorCode.cannotInterruptOthers.
    /// This happens when:
    /// - Another audio session is active and holds interruption priority
    /// - App is not in foreground when setActive fires
    /// - Options like .duckOthers / .notifyOthersOnDeactivation try to interrupt
    ///   but we don't have permission
    ///
    /// The fix: try the MOST PERMISSIVE config first (.mixWithOthers, no
    /// notifyOthersOnDeactivation). Only escalate to more aggressive configs
    /// if the permissive one fails.
    private func setupAudioSessionWithRetry(attempts: Int, backoffMs: Int) async -> Bool {
        log("    audio setup: mic permission = \(micPermissionDescription(AVAudioApplication.shared.recordPermission))")

        let session = AVAudioSession.sharedInstance()

        // Define multiple config candidates in order of most-to-least permissive.
        // The FIRST one that works wins.
        let configs: [(String, AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions, AVAudioSession.SetActiveOptions)] = [
            // Most permissive: coexist with any other audio session. No interruption.
            ("playAndRecord+mixWithOthers",
             .playAndRecord, .measurement,
             [.mixWithOthers, .defaultToSpeaker, .allowBluetooth],
             []),
            // No mixWithOthers but no interruption notification either
            ("playAndRecord+defaultToSpeaker",
             .playAndRecord, .measurement,
             [.defaultToSpeaker, .allowBluetooth],
             []),
            // Minimal record (Apple Speech sample pattern)
            ("record+measurement",
             .record, .measurement,
             [],
             []),
        ]

        for attempt in 1...attempts {
            for (configName, category, mode, categoryOptions, activeOptions) in configs {
                do {
                    try session.setCategory(category, mode: mode, options: categoryOptions)
                    try session.setActive(true, options: activeOptions)
                    log("    audio setup attempt \(attempt): ✓ \(configName)")
                    audioSessionConfigured = true
                    return true
                } catch {
                    let nsErr = error as NSError
                    log("    audio setup attempt \(attempt) [\(configName)]: ✗ code=\(nsErr.code) — \(error.localizedDescription)")
                }
            }
            // All configs failed this attempt — back off and try again
            if attempt < attempts {
                try? await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
            }
        }

        log("    ❌ audio setup: all configs failed after \(attempts) attempts")
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

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            // Use the shared retry helper so all paths use the same config
            let ok = await self.setupAudioSessionWithRetry(attempts: 2, backoffMs: 200)
            guard ok else {
                self.log("reactivateAudioPipeline: audio session setup failed")
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
        log("🌅 handleForeground called (inMem.sessionActive=\(isSessionActive) def.sessionActive=\(defaults.sessionActive))")
        guard isSessionActive else {
            log("  → skipping (session not active in memory)")
            return
        }
        log("  → refreshing pipeline")

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
        audioSessionConfigured = false
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
        log("🎙️ startRecordingAsync ENTRY (inMem.sessionActive=\(isSessionActive) inMem.isCurrentlyRecording=\(isCurrentlyRecording) def.sessionActive=\(defaults.sessionActive) def.isRecording=\(defaults.isRecording))")

        guard isSessionActive else {
            log("❌ BLOCK: isSessionActive=false — session not active (in-memory flag never got set)")
            await setActivationError("Session not active. Open the app and tap Retry.")
            emitRecordingFailed()
            return
        }
        guard !isCurrentlyRecording else {
            log("⚠️ BLOCK: isCurrentlyRecording=true — already recording, ignoring (no ACK)")
            return
        }

        // FAST-FAIL permission checks — bail immediately with a clear error
        // instead of wasting seconds on retries that can never succeed.
        let micPermission = AVAudioApplication.shared.recordPermission
        log("  pre-check: mic permission = \(micPermissionDescription(micPermission))")
        if micPermission != .granted {
            log("❌ BLOCK: mic permission not granted (\(micPermissionDescription(micPermission)))")
            let msg = micPermission == .denied
                ? "Microphone access was denied. Open Settings → Privacy → Microphone → Stop Typing and enable it."
                : "Microphone permission is required. Open the app and grant mic access."
            await setActivationError(msg)
            emitRecordingFailed()
            return
        }

        let speechAuth = SFSpeechRecognizer.authorizationStatus()
        log("  pre-check: speech auth = \(speechAuthDescription(speechAuth))")
        if speechAuth != .authorized {
            log("❌ BLOCK: speech recognition not authorized (\(speechAuthDescription(speechAuth)))")
            let msg = speechAuth == .denied
                ? "Speech recognition was denied. Open Settings → Privacy → Speech Recognition → Stop Typing and enable it."
                : "Speech recognition permission is required. Open the app and grant access."
            await setActivationError(msg)
            emitRecordingFailed()
            return
        }

        // Fix 2.3: Wait for speechRecognizer to be ready. On fresh install the recognizer
        // may briefly be nil or unavailable while Speech framework warms up.
        log("  step 1: checking speech recognizer (initial isAvailable=\(speechRecognizer?.isAvailable ?? false))")
        let recognizer: SFSpeechRecognizer
        if let ready = await waitForSpeechRecognizerReady(timeoutMs: 2000) {
            recognizer = ready
            log("  ✓ step 1 done: speech recognizer ready")
        } else {
            log("❌ BLOCK: speech recognizer never became available within 2s — aborting")
            await setActivationError("Speech recognizer unavailable. Try restarting the app.")
            emitRecordingFailed()
            return
        }

        // Audio session setup. If we already configured the session during
        // foreground activation, SKIP setCategory/setActive — iOS rejects those
        // calls from background with cannotInterruptOthers (error 560557684)
        // when another app (Messages, etc.) holds audio priority. The session
        // is still active from our foreground activation because the idle audio
        // engine keeps it alive under UIBackgroundModes=audio.
        if audioSessionConfigured {
            log("  step 2: audio session already configured from foreground — skipping setCategory/setActive")
        } else {
            log("  step 2: setting up audio session for the first time (retry x3)...")
            let audioReady = await setupAudioSessionWithRetry(attempts: 3, backoffMs: 200)
            guard audioReady else {
                log("❌ BLOCK: audio session not ready after 3 retries")
                await setActivationError("Couldn't configure the microphone. Tap Retry.")
                emitRecordingFailed()
                return
            }
            log("  ✓ step 2 done: audio session ready")
        }

        log("  step 3: cancelling prior recognition task + resetting state")
        // Fix 2.5: Cancel any leftover recognition task from a previous recording.
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
            log("  step 4: stopping idle engine")
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        log("  step 5: creating fresh AVAudioEngine")
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

        log("  step 6: installing input tap + prepare engine")
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateAudioLevel(buffer: buffer)
        }

        engine.prepare()
        log("  step 7: engine.start()...")
        do {
            try engine.start()
            log("✅ RECORDING STARTED — engine running, posting recordingStarted ACK")
            updateLiveActivity(isRecording: true)
            darwin.post(DarwinNotificationName.recordingStarted)
        } catch {
            log("❌ BLOCK: engine.start() threw: \(error.localizedDescription)")
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

    /// Surface a recording-time error to the UI so the user can see what happened
    /// when they next open the app. Clears on successful activation/recording.
    @MainActor
    private func setActivationError(_ message: String) {
        self.activationError = message
    }

    private func micPermissionDescription(_ status: AVAudioApplication.recordPermission) -> String {
        switch status {
        case .granted: return "granted"
        case .denied: return "denied"
        case .undetermined: return "undetermined"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    private func speechAuthDescription(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
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
