import Foundation

// MARK: - Notification Names

enum DarwinNotificationName {
    static let startDictation = "com.stormacq.StopTypingiOS.startDictation"
    static let stopDictation = "com.stormacq.StopTypingiOS.stopDictation"
    static let cancelDictation = "com.stormacq.StopTypingiOS.cancelDictation"
    static let transcriptReady = "com.stormacq.StopTypingiOS.transcriptReady"

    /// ACK from main app to keyboard: recording successfully started.
    /// Keyboard uses this to confirm its local state matches reality.
    static let recordingStarted = "com.stormacq.StopTypingiOS.recordingStarted"

    /// ACK from main app to keyboard: recording failed to start (permission, engine, etc).
    /// Keyboard uses this to reset its local UI back to the mic button.
    static let recordingFailed = "com.stormacq.StopTypingiOS.recordingFailed"
}

// MARK: - Darwin Notification Center

/// Cross-process notification helper using CFNotificationCenterGetDarwinNotifyCenter.
/// Darwin notifications work between the main app and keyboard extension.
/// They carry NO payload — use App Group UserDefaults for data.
final class DarwinNotificationCenter {
    static let shared = DarwinNotificationCenter()

    private let center = CFNotificationCenterGetDarwinNotifyCenter()
    private var callbacks: [String: () -> Void] = [:]

    private init() {}

    /// Post a Darwin notification (cross-process).
    func post(_ name: String) {
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }

    /// Observe a Darwin notification (cross-process).
    /// The callback fires on the main thread.
    func observe(_ name: String, callback: @escaping () -> Void) {
        callbacks[name] = callback

        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, notificationName, _, _ in
                guard let observer, let name = notificationName?.rawValue as String? else { return }
                let center = Unmanaged<DarwinNotificationCenter>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async {
                    center.callbacks[name]?()
                }
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Remove observer for a specific notification.
    func removeObserver(_ name: String) {
        CFNotificationCenterRemoveObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name as CFString),
            nil
        )
        callbacks.removeValue(forKey: name)
    }

    /// Remove all observers.
    func removeAllObservers() {
        CFNotificationCenterRemoveEveryObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque()
        )
        callbacks.removeAll()
    }
}
