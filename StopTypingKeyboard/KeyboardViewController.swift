import UIKit
import SwiftUI
import Combine

class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardRootView>?
    /// Observable state that KeyboardRootView subscribes to. Owned here so it
    /// survives view rebuilds. Mutating these @Published properties triggers a
    /// targeted re-render without destroying any @State in the root view —
    /// preserving waveformTimer, waveformBars, etc. across state changes.
    private let keyboardState = KeyboardState()
    // Accessors forward into keyboardState so the existing code paths
    // (startDictation, refreshState, etc.) keep working unchanged.
    private var isAppAlive: Bool {
        get { keyboardState.isAppAlive }
        set { keyboardState.isAppAlive = newValue }
    }
    private var isRecording: Bool {
        get { keyboardState.isRecording }
        set { keyboardState.isRecording = newValue }
    }
    private var heartbeatTimer: Timer?
    private let darwin = DarwinNotificationCenter.shared
    private var lastInsertedTranscriptTimestamp: Date?
    private var darwinObserversRegistered = false

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        hasDictationKey = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        hasDictationKey = false
    }

    private func klog(_ msg: String) {
        SharedDefaults.shared.appendLog("KBD: \(msg)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        hasDictationKey = false

        // Match the exact same color as our SwiftUI keyboard background
        // This fills the area above our VStack so no different-shade gray shows
        view.backgroundColor = .systemGray6
        inputView?.backgroundColor = .systemGray6

        // Liveness is gated on the heartbeat, NOT on sessionActive. sessionActive
        // is sticky — it stays true even when iOS suspends the main app — so
        // relying on it made the keyboard lie: mic button shown, user taps, dead
        // session. isAppAlive() checks whether the main app wrote a heartbeat
        // within the last 10s. Boot-ID check guards against reboot staleness.
        let defaults = SharedDefaults.shared
        isAppAlive = defaults.isAppAlive() && defaults.isCurrentBoot()
        isRecording = defaults.isRecording && isAppAlive

        setupKeyboardView()
        registerDarwinObservers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasDictationKey = false
        // Immediate state check + UI rebuild — don't wait for timer
        refreshState()
        rebuildView()
        startHeartbeatPolling()
        registerDarwinObservers()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Setup

    private func setupKeyboardView() {
        let keyboardView = KeyboardRootView(
            onInsertText: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            },
            onDeleteBackward: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            },
            onNextKeyboard: { [weak self] in
                self?.advanceToNextInputMode()
            },
            onReturnKey: { [weak self] in
                self?.textDocumentProxy.insertText("\n")
            },
            onOpenApp: { [weak self] in
                self?.openMainApp()
            },
            onStartDictation: { [weak self] in
                self?.startDictation()
            },
            onStopDictation: { [weak self] in
                self?.stopDictation()
            },
            onCancelDictation: { [weak self] in
                self?.cancelDictation()
            },
            showGlobe: needsInputModeSwitchKey,
            state: keyboardState
        )

        let host = UIHostingController(rootView: keyboardView)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear

        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hostingController = host
    }

    // MARK: - Darwin Observers

    private func registerDarwinObservers() {
        guard !darwinObserversRegistered else { return }
        darwinObserversRegistered = true

        darwin.observe(DarwinNotificationName.transcriptReady) { [weak self] in
            self?.onTranscriptReady()
        }
        // Fix 2.4: ACK from main app that recording actually started.
        // Confirms local state is correct — nothing to do but log.
        darwin.observe(DarwinNotificationName.recordingStarted) { [weak self] in
            self?.klog("✅ recordingStarted ACK received")
        }
        // Fix 2.4: ACK from main app that recording failed to start.
        // Reset local UI back to the mic button so the user can try again.
        darwin.observe(DarwinNotificationName.recordingFailed) { [weak self] in
            self?.onRecordingFailed()
        }
    }

    private func onRecordingFailed() {
        klog("❌ recordingFailed ACK received — resetting UI + marking app unavailable")
        isRecording = false
        // Optimistically mark the app as unavailable so the toolbar flips to
        // "Start ST" immediately instead of waiting for the 10s heartbeat
        // staleness window. The next refreshState poll will re-confirm from
        // the heartbeat; if the app is actually alive it'll flip back.
        isAppAlive = false
        rebuildView()
    }

    // MARK: - State Management

    private func refreshState() {
        let wasAlive = isAppAlive
        let wasRecording = isRecording
        let defaults = SharedDefaults.shared

        // Heartbeat-based liveness: the main app writes a heartbeat every 2s
        // while alive. When iOS suspends it, the writes stop and within ~10s
        // isAppAlive() flips to false, cueing us to show "Start ST" instead
        // of the mic button. Boot-ID check guards reboot staleness.
        let bootMatches = defaults.isCurrentBoot()
        isAppAlive = defaults.isAppAlive() && bootMatches
        isRecording = isAppAlive ? defaults.isRecording : false

        if isAppAlive != wasAlive || isRecording != wasRecording {
            rebuildView()
        }
    }

    private func startHeartbeatPolling() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshState()
        }
    }

    /// No-op now: state changes flow through keyboardState (@ObservableObject)
    /// and SwiftUI re-renders the dependent parts of KeyboardRootView without
    /// destroying the root view struct. Kept as a named function so existing
    /// call sites don't need to be rewritten.
    private func rebuildView() {
        // Intentionally empty — state is observed directly.
    }

    // MARK: - Actions

    private func openMainApp() {
        klog("Opening main app")
        guard let url = URL(string: "stoptyping://activate") else { return }

        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url)
                return
            }
            responder = r.next
        }

        extensionContext?.open(url) { [weak self] success in
            SharedDefaults.shared.appendLog("KBD: extensionContext result: \(success)")
            if !success {
                // iOS refused to open the URL. Best we can do is nudge the
                // user — they'll need to tap the Stop Typing app icon
                // manually. Insert a short, dismissable hint at the cursor.
                DispatchQueue.main.async {
                    self?.textDocumentProxy.insertText("[open Stop Typing app to continue] ")
                }
            }
        }
    }

    private func startDictation() {
        klog("START dictation")
        isRecording = true
        rebuildView()
        darwin.post(DarwinNotificationName.startDictation)
    }

    private func stopDictation() {
        klog("STOP dictation (save)")
        darwin.post(DarwinNotificationName.stopDictation)
    }

    private func cancelDictation() {
        klog("CANCEL dictation (discard)")
        darwin.post(DarwinNotificationName.cancelDictation)
        isRecording = false
        rebuildView()
    }

    private func onTranscriptReady() {
        klog("transcriptReady received!")

        let defaults = SharedDefaults.shared
        guard let timestamp = defaults.transcriptTimestamp else {
            klog("No transcript timestamp found")
            return
        }

        if let lastInserted = lastInsertedTranscriptTimestamp, timestamp <= lastInserted {
            klog("Already inserted this transcript, skipping")
            return
        }

        guard let transcript = defaults.latestTranscript, !transcript.isEmpty else {
            klog("Transcript is empty")
            return
        }

        klog("Inserting: \(transcript.prefix(80))...")
        textDocumentProxy.insertText(transcript)
        lastInsertedTranscriptTimestamp = timestamp

        isRecording = false
        rebuildView()
    }

    override func textWillChange(_ textInput: UITextInput?) {}
    override func textDidChange(_ textInput: UITextInput?) {}
}
