import UIKit
import SwiftUI
import Combine

class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardRootView>?
    private var isAppAlive = false
    private var isRecording = false
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

        // Use sessionActive boolean — this persists even when app is backgrounded
        let defaults = SharedDefaults.shared
        isAppAlive = defaults.sessionActive
        isRecording = defaults.isRecording

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
        let appAliveBinding = Binding<Bool>(
            get: { [weak self] in self?.isAppAlive ?? false },
            set: { [weak self] in self?.isAppAlive = $0 }
        )
        let recordingBinding = Binding<Bool>(
            get: { [weak self] in self?.isRecording ?? false },
            set: { [weak self] in self?.isRecording = $0 }
        )

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
            isAppAlive: appAliveBinding,
            isRecording: recordingBinding
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
        klog("❌ recordingFailed ACK received — resetting UI")
        isRecording = false
        rebuildView()
    }

    // MARK: - State Management

    private func refreshState() {
        let wasAlive = isAppAlive
        let wasRecording = isRecording
        let defaults = SharedDefaults.shared

        // Trust sessionActive — it stays true across app backgrounding and sleep.
        // The app uses UIApplication.willTerminateNotification to clear it on termination,
        // and handles AVAudioSession interruptions to self-heal after system suspension.
        isAppAlive = defaults.sessionActive
        isRecording = defaults.isRecording

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

    private func rebuildView() {
        guard let host = hostingController else { return }

        let appAliveBinding = Binding<Bool>(
            get: { [weak self] in self?.isAppAlive ?? false },
            set: { [weak self] in self?.isAppAlive = $0 }
        )
        let recordingBinding = Binding<Bool>(
            get: { [weak self] in self?.isRecording ?? false },
            set: { [weak self] in self?.isRecording = $0 }
        )

        host.rootView = KeyboardRootView(
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
            isAppAlive: appAliveBinding,
            isRecording: recordingBinding
        )
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

        extensionContext?.open(url) { success in
            SharedDefaults.shared.appendLog("KBD: extensionContext result: \(success)")
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
