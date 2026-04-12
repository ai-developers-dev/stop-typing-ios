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
    /// Pipeline reconnection status for the overlay banner. Flipped to
    /// .rebuilding when rebuildAudioPipelineFromScratch starts, .ready when
    /// it completes, .idle by default.
    @Published var pipelineStatus: PipelineStatus = .idle

    enum PipelineStatus: Equatable {
        case idle
        case rebuilding
        case ready
    }

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
    /// Re-entry guard for rebuildAudioPipelineFromScratch. Multiple callers
    /// (scenePhase.active → handleForeground, URL scheme → activateSession,
    /// mediaServicesReset, etc.) can race into a rebuild simultaneously.
    /// Without this guard, the second rebuild tears down the engine the
    /// first one just built, leaving the pipeline half-broken.
    private var rebuildInProgress = false
    /// Re-entry guard for reactivateAudioPipeline. Same reasoning as
    /// rebuildInProgress — also cross-checked against rebuildInProgress so
    /// reactivate never runs in parallel with a rebuild (the race that
    /// produced the "two idle engines, hardware locked" bug).
    private var reactivateInProgress = false
    /// Debounce for reactivateAudioPipeline so handleForeground +
    /// DictationOverlayView.onAppear don't both trigger full pipeline
    /// restarts in parallel when the user returns to the app.
    private var lastReactivation: Date = .distantPast
    private let reactivationDebounceSeconds: TimeInterval = 1.5

    // Diagnostic counters for the current recording session. Reset in
    // startRecordingAsync, logged in stopRecording. Tell us whether the tap
    // callback is firing, whether the recognition task is emitting partial
    // results, and the current state when the user hit stop.
    private var currentTapBufferCount: Int = 0
    private var currentPartialResultCount: Int = 0
    private var currentRecordingStartTime: Date = .distantPast
    private var recognitionIsFinal: Bool = false

    private init() {}

    private func log(_ msg: String) {
        print("[BGDictation] \(msg)")
        defaults.appendLog("APP: \(msg)")
        DispatchQueue.main.async { self.debugLog = self.defaults.debugLog }
    }

    // MARK: - Activate Session

    func activateSession() {
        log("🟢 activateSession() called — inMemory.isSessionActive=\(isSessionActive) defaults.sessionActive=\(defaults.sessionActive) defaults.isRecording=\(defaults.isRecording)")

        // If already active, write a fresh heartbeat and bail. handleForeground
        // (fired by scenePhase .active BEFORE DictationOverlayView.onAppear
        // calls us) owns the pipeline refresh/rebuild path. Calling
        // reactivateAudioPipeline here raced with handleForeground's rebuild
        // and created a second idle engine in parallel — the orphan held
        // the mic hardware and made later engine.start() calls fail with
        // OSStatus 2003329396 ('what' — kAUStartIO refused).
        if isSessionActive {
            log("  session already active (in-memory) — writing heartbeat only (handleForeground owns refresh)")
            defaults.writeHeartbeat()
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
            guard let self else { return }
            self.log("AVAudioEngine config changed — marking session stale + restarting idle engine")
            // Route/config change means the session may be in a limbo state.
            // Force full re-setup on next startRecording.
            self.audioSessionConfigured = false
            self.reactivateAudioPipeline()
        }

        // Apple's documented "your audio state is toast, rebuild everything"
        // signals. From the mediaServicesWereReset doc:
        //   "Respond to these events by reinitializing your app's audio
        //    objects and resetting your audio session's category, options,
        //    and mode configuration."
        // We cannot do that from background (setActive will fail with
        // cannotInterruptOthers). Instead: mark session stale, zero the
        // heartbeat so the keyboard shows "Start ST", and let the foreground
        // path run the full rebuild.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.log("🚨 mediaServicesWereReset — session is toast, marking stale and zeroing heartbeat")
            self.audioSessionConfigured = false
            self.defaults.heartbeat = nil
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.log("🚨 mediaServicesWereLost — session is toast, marking stale and zeroing heartbeat")
            self.audioSessionConfigured = false
            self.defaults.heartbeat = nil
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

    /// Tracks whether warmUpColdStart has already run once this process lifetime.
    /// Guards against repeated calls from scenePhase transitions during onboarding.
    private var didWarmUpOnce = false

    func warmUpColdStart() async {
        // If real activation already ran, skip (no cost, but log confirms)
        guard !isSessionActive else {
            log("🔥 Warmup skipped — session already active")
            return
        }

        // Only warm up once per process lifetime. Scene phase can cycle through
        // active/inactive multiple times during onboarding (permission prompts)
        // and we don't need to re-warm each time.
        guard !didWarmUpOnce else {
            return
        }
        didWarmUpOnce = true

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

        // Zombie-session teardown: if iOS left us with a half-dead session after
        // an interruption or config change, a fresh setCategory/setActive will
        // hit error 561017449 ('cannot interrupt others') in a loop. Tearing
        // down first gives the audio daemon a clean slate.
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            log("    audio setup: pre-teardown setActive(false) OK")
        } catch {
            // Best-effort — log but continue. If the session was already
            // inactive or in a weird state, setCategory below will still try.
            let nsErr = error as NSError
            log("    audio setup: pre-teardown setActive(false) ignored (code=\(nsErr.code))")
        }
        // Tiny breathing room so the AV daemon notices the deactivation
        // before we immediately ask it to re-activate.
        try? await Task.sleep(nanoseconds: 80_000_000)

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

                    // Force a route refresh. After wake-from-idle or a stale
                    // Bluetooth route, setCategory+setActive can succeed while
                    // the hardware mic silently delivers zeros. Explicitly
                    // requesting a preferred input forces iOS to re-bind the
                    // audio route to a live device.
                    forcePreferredBuiltInMic(session: session)

                    log("    audio setup attempt \(attempt): ✓ \(configName)")
                    logCurrentRoute(session: session, tag: "after \(configName)")
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

    /// Log current input/output route so we can see WHICH device iOS picked.
    /// Critical for diagnosing "session active but mic silent" — usually means
    /// a stale Bluetooth input or no input at all.
    private func logCurrentRoute(session: AVAudioSession, tag: String) {
        let route = session.currentRoute
        let inputs = route.inputs.map { "\($0.portName)[\($0.portType.rawValue)]" }.joined(separator: ",")
        let outputs = route.outputs.map { "\($0.portName)[\($0.portType.rawValue)]" }.joined(separator: ",")
        log("    🎧 route (\(tag)): inputs=[\(inputs.isEmpty ? "NONE" : inputs)] outputs=[\(outputs.isEmpty ? "NONE" : outputs)]")
    }

    /// Try to force the built-in mic as the preferred input. After a stale
    /// wake, the route may still point at a disconnected Bluetooth headset
    /// causing silent capture. Switching to built-in mic refreshes the
    /// hardware binding. Best-effort: logs and continues on error.
    private func forcePreferredBuiltInMic(session: AVAudioSession) {
        guard let inputs = session.availableInputs, !inputs.isEmpty else {
            log("    🎤 forcePreferredInput: no availableInputs — skipping")
            return
        }

        // Prefer built-in mic when available (most reliable after stale wake).
        let builtIn = inputs.first { $0.portType == .builtInMic }
        let target = builtIn ?? inputs.first!

        do {
            try session.setPreferredInput(target)
            log("    🎤 forcePreferredInput: set to \(target.portName)[\(target.portType.rawValue)]")
        } catch {
            let nsErr = error as NSError
            log("    🎤 forcePreferredInput: FAILED code=\(nsErr.code) — \(error.localizedDescription) — continuing anyway")
        }
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
            log("Audio interruption BEGAN (wasSuspended: \(wasSuspended)) — marking session stale")
            // iOS has deactivated our audio session. The next recording attempt
            // MUST re-run setCategory/setActive from scratch — without this flag
            // reset, startRecordingAsync would skip setup and record silence.
            audioSessionConfigured = false

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
    /// Cross-guarded against rebuildAudioPipelineFromScratch so the two
    /// never run in parallel.
    private func reactivateAudioPipeline() {
        if isCurrentlyRecording {
            log("reactivateAudioPipeline: skipping (recording in progress)")
            return
        }

        // CRITICAL: never run alongside a rebuild. Prior to this guard,
        // activateSession's already-active branch called reactivate while
        // handleForeground called rebuild, creating TWO idle engines in
        // parallel. The orphaned one held the mic hardware and later caused
        // engine.start() to fail with OSStatus 2003329396 (kAUStartIO refused).
        if rebuildInProgress {
            log("reactivateAudioPipeline: skipping (rebuild in progress)")
            return
        }
        if reactivateInProgress {
            log("reactivateAudioPipeline: skipping (another reactivate in progress)")
            return
        }

        let now = Date()
        if now.timeIntervalSince(lastReactivation) < reactivationDebounceSeconds {
            log("reactivateAudioPipeline: debounced (last ran \(String(format: "%.1f", now.timeIntervalSince(lastReactivation)))s ago)")
            return
        }
        lastReactivation = now
        reactivateInProgress = true

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer { self.reactivateInProgress = false }

            let ok = await self.setupAudioSessionWithRetry(attempts: 2, backoffMs: 200)
            guard ok else {
                self.log("reactivateAudioPipeline: audio session setup failed — zeroing heartbeat so keyboard shows 'Start ST' CTA")
                self.audioSessionConfigured = false
                // Signal to the keyboard that the app is effectively dead.
                // isAppAlive() checks heartbeat freshness, so clearing it
                // flips the keyboard to the "Start ST" inactive toolbar
                // within its next 3s poll. Leave sessionActive=true so that
                // when the user foregrounds the app, activateSession's
                // already-active branch runs the rebuild path.
                self.defaults.heartbeat = nil
                return
            }
            self.startIdleAudioEngine()
            self.defaults.writeHeartbeat()
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
            log("Was recording when backgrounded — cleaning up, swapping to idle tap")
            // Swap to idle tap instead of stop+start — keeps engine running so
            // the audio hardware isn't released (prevents 2003329396 on next record)
            swapToIdleTap()
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
        }
    }

    func handleForeground() {
        log("🌅 handleForeground called (inMem.sessionActive=\(isSessionActive) def.sessionActive=\(defaults.sessionActive))")
        guard isSessionActive else {
            log("  → skipping (session not active in memory)")
            return
        }

        // Write heartbeat immediately so timestamp is fresh — this flips
        // the keyboard out of "Start ST" state even before the rebuild
        // completes, so the UI feels responsive.
        defaults.writeHeartbeat()

        // Restart heartbeat timer if it was suspended
        if heartbeatTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
            timer.schedule(deadline: .now(), repeating: 2.0)
            timer.setEventHandler { [weak self] in self?.defaults.writeHeartbeat() }
            timer.resume()
            heartbeatTimer = timer
        }

        // Decide whether to do the full rebuild or just a lightweight refresh.
        // Full rebuild is needed when the session is stale (audioSessionConfigured==false)
        // OR the idle engine is dead. When we're in foreground, setCategory/setActive
        // is actually allowed by iOS, so the rebuild can succeed.
        let idleEngineRunning = audioEngine?.isRunning == true
        if !audioSessionConfigured || !idleEngineRunning {
            log("  → rebuildAudioPipelineFromScratch (audioSessionConfigured=\(audioSessionConfigured), idleEngineRunning=\(idleEngineRunning))")
            Task.detached(priority: .userInitiated) { [weak self] in
                await self?.rebuildAudioPipelineFromScratch()
            }
        } else {
            log("  → pipeline looks healthy, debounced refresh only")
            reactivateAudioPipeline()
        }

        // Restart Live Activity if it was dismissed
        if currentActivity == nil {
            startLiveActivity()
        }
    }

    /// Apple's documented recovery path for `mediaServicesWereReset` and
    /// similar "your audio state is toast" signals. Unlike reactivateAudioPipeline
    /// (which only re-runs setCategory+setActive), this method fully tears down
    /// and rebuilds the engine graph, which is what Apple explicitly recommends:
    ///
    ///   "Respond to these events by reinitializing your app's audio objects
    ///    and resetting your audio session's category, options, and mode
    ///    configuration."
    ///
    /// Only safe to call when the app is in the foreground — setActive will
    /// fail with cannotInterruptOthers from background.
    private func rebuildAudioPipelineFromScratch() async {
        // Re-entry guard: if a rebuild is already in flight, the caller's
        // intent is already being served. Skipping duplicates is safe because
        // callers (handleForeground, URL scheme, mediaServicesReset) are all
        // fire-and-forget signals, not workflows that wait on the result.
        if rebuildInProgress {
            log("🔨 rebuildAudioPipelineFromScratch: ALREADY IN PROGRESS — skipping duplicate call")
            return
        }
        // Cross-guard: if reactivate is mid-flight, wait for it to finish
        // rather than stomping on its in-progress setActive. Poll briefly
        // (reactivate's work is ~200-500ms). Without this, rebuild's
        // setActive(false) would tear down the session reactivate just built.
        var waitedMs = 0
        while reactivateInProgress && waitedMs < 1500 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waitedMs += 50
        }
        if reactivateInProgress {
            log("🔨 rebuildAudioPipelineFromScratch: reactivate still in flight after 1.5s — proceeding anyway")
        }
        rebuildInProgress = true
        defer { rebuildInProgress = false }

        log("🔨 rebuildAudioPipelineFromScratch: starting (audioSessionConfigured=\(audioSessionConfigured), idleEngineRunning=\(audioEngine?.isRunning == true))")
        await MainActor.run { self.pipelineStatus = .rebuilding }

        // 1. Stop current engine, remove taps
        if let engine = audioEngine {
            if engine.isRunning {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
            }
        }
        audioEngine = nil
        log("  🔨 old engine stopped and released")

        // 2. Cancel any lingering recognition state
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // 3-6. Setup session from clean state (includes setActive(false)
        //      teardown + setCategory/setMode/setActive + forcePreferredBuiltInMic
        //      + route logging, all inside setupAudioSessionWithRetry).
        audioSessionConfigured = false
        let ok = await setupAudioSessionWithRetry(attempts: 3, backoffMs: 200)
        guard ok else {
            log("  🔨 rebuild FAILED at session setup — leaving heartbeat nil so keyboard keeps 'Start ST'")
            defaults.heartbeat = nil
            await MainActor.run { self.pipelineStatus = .idle }
            await setActivationError("iOS refused the microphone even from the foreground. Close another audio app (Music, call) and tap Retry.")
            return
        }

        // 7-9. Rebuild idle engine
        startIdleAudioEngine()

        // 10. Fresh session marks
        defaults.writeHeartbeat()
        defaults.bootId = SharedDefaults.currentBootID()
        await MainActor.run {
            self.activationError = nil
            self.pipelineStatus = .ready
        }

        log("  🔨 rebuildAudioPipelineFromScratch: COMPLETE")
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        do {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                log("Live Activities not enabled on this device")
                return
            }

            // Reuse-or-clean: enumerate every existing Activity of this type
            // (including orphans from prior crashes, force-quits, missed end
            // calls, or any future bug). If exactly one is alive AND matches
            // our local reference, reuse it. Otherwise end them all and start
            // fresh. This is the canonical "always exactly one" pattern from
            // Apple's ActivityKit docs and sample code.
            let existing = Activity<StopTypingWidgetAttributes>.activities
            if existing.count == 1, let only = existing.first, only.id == currentActivity?.id {
                log("Live Activity already running, reusing (id=\(only.id))")
                return
            }

            if !existing.isEmpty {
                log("Found \(existing.count) existing Live Activities — ending all before starting fresh")
                let finalState = StopTypingWidgetAttributes.ContentState(isRecording: false, mode: "Formal")
                for activity in existing {
                    Task {
                        await activity.end(
                            ActivityContent(state: finalState, staleDate: nil),
                            dismissalPolicy: .immediate
                        )
                    }
                }
                currentActivity = nil
            }

            let attrs = StopTypingWidgetAttributes(sessionId: UUID().uuidString)
            let state = StopTypingWidgetAttributes.ContentState(isRecording: false, mode: "Formal")

            currentActivity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            log("Live Activity started (id=\(currentActivity?.id ?? "nil"))")
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
        // Pass an EXPLICIT final ContentState. Calling activity.end(nil, ...)
        // is the canonical "doesn't actually remove the card" bug — iOS keeps
        // the lock screen card visible indefinitely when the final state is
        // nil. Apple's sample code (Emoji Rangers) always passes an explicit
        // ActivityContent for the same reason.
        let finalState = StopTypingWidgetAttributes.ContentState(isRecording: false, mode: "Formal")
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
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
        // foreground activation AND the idle engine is still running (proof the
        // session is alive), SKIP setCategory/setActive — iOS rejects those
        // calls from background with cannotInterruptOthers (error 560557684)
        // when another app holds audio priority.
        //
        // CRITICAL: The idle-engine check is what saves us after an interruption
        // recovery fails. Previously we trusted audioSessionConfigured alone,
        // which left a hole: a failed reactivateAudioPipeline would leave the
        // flag true but the session/engine dead → we'd record pure silence.
        let idleEngineRunning = audioEngine?.isRunning == true
        let sessionLooksHealthy = audioSessionConfigured && idleEngineRunning
        if sessionLooksHealthy {
            log("  step 2: audio session already configured from foreground — skipping setCategory/setActive")
        } else {
            if !idleEngineRunning {
                log("  step 2: idle engine NOT running (audioSessionConfigured=\(audioSessionConfigured)) — session is stale, re-running setup")
                audioSessionConfigured = false
            } else {
                log("  step 2: setting up audio session for the first time (retry x3)...")
            }
            let audioReady = await setupAudioSessionWithRetry(attempts: 3, backoffMs: 200)
            guard audioReady else {
                log("❌ BLOCK: audio session not ready after 3 retries (likely another app holds the audio route — Messages, call, Bluetooth, etc.)")
                await setActivationError("iOS won't release the microphone right now. Open Stop Typing and tap Retry — bringing the app to the foreground usually fixes this.")
                emitRecordingFailed()
                return
            }
            log("  ✓ step 2 done: audio session ready (fresh setup)")
        }

        log("  step 3: cancelling prior recognition task + resetting state")
        // Fix 2.5: Cancel any leftover recognition task from a previous recording.
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        currentTranscript = ""
        currentTapBufferCount = 0
        currentPartialResultCount = 0
        audioLevelLogCounter = 0
        recognitionIsFinal = false
        currentRecordingStartTime = Date()
        defaults.isRecording = true
        defaults.audioLevel = 0
        previousAudioLevel = 0
        await MainActor.run { self.isCurrentlyRecording = true }

        // === CORE FIX: Swap taps on the RUNNING engine instead of stop+create+start ===
        //
        // After an audio interruption (e.g. phone call, Siri, media controls),
        // iOS's CoreAudio HAL will NOT allow a new AVAudioEngine to call startIO
        // from a backgrounded app — it fails with error 2003329396
        // (kAudioUnitErr_FailedInitialization / 'what'). This was the root cause
        // of the recurring "dictation stops working after ~1 day" bug.
        //
        // The fix: KEEP the idle engine running and swap its input tap handler
        // from "discard audio" to "feed into SFSpeechRecognitionRequest". No
        // engine.stop(), no engine = AVAudioEngine(), no engine.start().
        // The engine holds the audio hardware from the foreground activation,
        // and we just redirect where the buffers go.
        //
        // If the engine ISN'T running (e.g. after a cold start or a failed
        // reactivation), fall back to the old create+start path — which should
        // only happen when the app is in the foreground.

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
                self.currentPartialResultCount += 1
                if self.currentPartialResultCount == 1 {
                    let elapsed = Date().timeIntervalSince(self.currentRecordingStartTime)
                    self.log("  🗣️ first partial result after \(String(format: "%.2f", elapsed))s: '\(self.currentTranscript.prefix(40))'")
                }
                if result.isFinal {
                    self.recognitionIsFinal = true
                    self.log("ASR final result: '\(self.currentTranscript.prefix(60))'")
                }
            }
            if let error {
                self.log("Recognition error: \(error.localizedDescription)")
            }
        }

        if let engine = audioEngine, engine.isRunning {
            // === FAST PATH: engine is already running — just swap the tap ===
            log("  step 4-7: engine already running — swapping tap from idle to recording")

            engine.inputNode.removeTap(onBus: 0)
            let format = engine.inputNode.outputFormat(forBus: 0)

            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                self.recognitionRequest?.append(buffer)
                self.updateAudioLevel(buffer: buffer)
                self.currentTapBufferCount += 1
                if self.currentTapBufferCount == 1 {
                    let elapsed = Date().timeIntervalSince(self.currentRecordingStartTime)
                    self.log("  🎤 first audio buffer after \(String(format: "%.2f", elapsed))s")
                }
            }

            log("✅ RECORDING STARTED (tap-swap, no engine restart) — posting recordingStarted ACK")
            updateLiveActivity(isRecording: true)
            darwin.post(DarwinNotificationName.recordingStarted)

        } else {
            // === SLOW PATH: engine not running — full create+start (foreground only) ===
            log("  step 4: no running engine — creating fresh AVAudioEngine (foreground path)")

            let engine = AVAudioEngine()
            self.audioEngine = engine
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }
                self.recognitionRequest?.append(buffer)
                self.updateAudioLevel(buffer: buffer)
                self.currentTapBufferCount += 1
                if self.currentTapBufferCount == 1 {
                    let elapsed = Date().timeIntervalSince(self.currentRecordingStartTime)
                    self.log("  🎤 first audio buffer after \(String(format: "%.2f", elapsed))s")
                }
            }

            engine.prepare()
            log("  step 7: engine.start() (slow path)...")
            do {
                try engine.start()
                log("✅ RECORDING STARTED (new engine) — posting recordingStarted ACK")
                updateLiveActivity(isRecording: true)
                darwin.post(DarwinNotificationName.recordingStarted)
            } catch {
                let nsErr = error as NSError
                log("❌ BLOCK: engine.start() threw: code=\(nsErr.code) \(error.localizedDescription)")
                defaults.isRecording = false
                await MainActor.run { self.isCurrentlyRecording = false }
                recognitionTask?.cancel()
                recognitionTask = nil
                recognitionRequest = nil
                audioSessionConfigured = false
                audioEngine = nil
                defaults.heartbeat = nil
                emitRecordingFailed()
            }
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

    /// Counter used to sample-log audioLevel values periodically during
    /// recording, so we can see in the debug log what values the keyboard
    /// is actually seeing.
    private var audioLevelLogCounter: Int = 0

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = vDSP_Length(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Hardware-accelerated RMS calculation
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, frameLength)

        // Convert RMS to dB, then normalize to 0...1 range.
        // Speech RMS is typically 0.005 (quiet) to 0.1 (loud) linear.
        // In dB that's roughly -46dB to -20dB.
        // Anything below -55dB is effectively silence.
        let minDb: Float = -55.0
        let maxDb: Float = -15.0
        let db = 20.0 * log10(max(rms, 0.00001))
        let normalized = max(0, min(1, (db - minDb) / (maxDb - minDb)))

        // Snappier EMA smoothing (alpha=0.6 = 60% weight on new sample).
        // Old value was 0.3 which made the waveform lag noticeably behind
        // the voice.
        let alpha: Float = 0.6
        let smoothed = alpha * normalized + (1 - alpha) * previousAudioLevel
        previousAudioLevel = smoothed

        defaults.audioLevel = smoothed

        // Log every ~10 buffers (roughly 250ms at 43Hz buffer rate) so we
        // can see the actual levels flowing through without flooding the log.
        audioLevelLogCounter += 1
        if audioLevelLogCounter % 10 == 0 {
            log("  📊 audioLevel: rms=\(String(format: "%.4f", rms)) db=\(String(format: "%.1f", db)) normalized=\(String(format: "%.3f", normalized)) smoothed=\(String(format: "%.3f", smoothed))")
        }
    }

    // MARK: - Stop Recording (save transcript)

    private func stopRecording() {
        guard isCurrentlyRecording else {
            log("Not recording, nothing to stop")
            return
        }

        let elapsed = Date().timeIntervalSince(currentRecordingStartTime)
        log("⏹ Stopping recording after \(String(format: "%.2f", elapsed))s (bufferCount=\(currentTapBufferCount) partials=\(currentPartialResultCount) currentTranscript='\(currentTranscript.prefix(40))')")

        // Swap the recording tap back to the idle tap — keep the engine running
        // so the audio hardware isn't released. This is what prevents error
        // 2003329396 on the next recording from background.
        swapToIdleTap()
        recognitionRequest?.endAudio()

        defaults.audioLevel = 0
        previousAudioLevel = 0

        // Update Live Activity and recording state immediately — don't wait for transcript processing
        defaults.isRecording = false
        DispatchQueue.main.async { self.isCurrentlyRecording = false }
        updateLiveActivity(isRecording: false)

        Task { [weak self] in
            guard let self else { return }

            let maxWaitMs = 3000
            var waited = 0
            while waited < maxWaitMs {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 100
                if self.recognitionIsFinal { break }
            }

            let rawTranscript = self.currentTranscript
            self.log("ASR wait: \(waited)ms (isFinal=\(self.recognitionIsFinal), transcript='\(rawTranscript.prefix(60))')")

            self.recognitionTask?.cancel()
            self.recognitionTask = nil
            self.recognitionRequest = nil
            self.currentTranscript = ""

            if !rawTranscript.isEmpty {
                let cleanedTranscript = await GroqService.shared.cleanTranscript(rawTranscript)
                self.log("LLM cleaned: '\(cleanedTranscript.prefix(80))'")

                await MainActor.run {
                    self.lastTranscript = cleanedTranscript
                    self.defaults.saveTranscript(cleanedTranscript)
                    TranscriptHistoryStore.shared.add(TranscriptItem(text: cleanedTranscript))
                    self.darwin.post(DarwinNotificationName.transcriptReady)
                    self.log("Cleaned transcript saved, notified keyboard")
                }
            } else {
                self.log("Empty transcript after \(waited)ms wait")
            }

            // Engine stays running with idle tap — no startIdleAudioEngine() needed
        }
    }

    // MARK: - Cancel Recording (discard, restart immediately)

    private func cancelRecording() {
        guard isCurrentlyRecording else { return }

        log("Canceling recording (discard)")
        // Swap back to idle tap — keep engine running
        swapToIdleTap()
        cleanupRecording()
        defaults.audioLevel = 0
        previousAudioLevel = 0

        updateLiveActivity(isRecording: false)
        log("Cancel complete, swapped back to idle tap")
    }

    /// Swap the current input tap back to the "discard audio" idle tap.
    /// Keeps the engine running so the audio hardware isn't released.
    /// This is the counterpart to the "swap to recording tap" path in startRecordingAsync.
    private func swapToIdleTap() {
        guard let engine = audioEngine, engine.isRunning else {
            log("swapToIdleTap: engine not running — falling back to startIdleAudioEngine")
            startIdleAudioEngine()
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        let format = engine.inputNode.outputFormat(forBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { _, _ in
            // Discard audio — just keeping the session alive
        }
        log("Swapped back to idle tap (engine still running)")
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
