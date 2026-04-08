import AVFoundation
import Speech
import SwiftUI

@MainActor
final class PermissionsManager: ObservableObject {
    @Published var microphoneGranted: Bool = false
    @Published var speechStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    var speechGranted: Bool { speechStatus == .authorized }
    var allPermissionsGranted: Bool { microphoneGranted && speechGranted }

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
        speechStatus = SFSpeechRecognizer.authorizationStatus()
    }

    func requestMicrophone() async -> Bool {
        do {
            let granted = try await AVAudioApplication.requestRecordPermission()
            refreshStatus()
            return granted
        } catch {
            refreshStatus()
            return false
        }
    }

    func requestSpeechRecognition() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.refreshStatus()
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    func requestAllPermissions() async -> Bool {
        let mic = await requestMicrophone()
        guard mic else { return false }
        let speech = await requestSpeechRecognition()
        return speech
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Opens the app's own Settings page.
    /// When the keyboard extension is properly installed, iOS automatically
    /// shows a "Keyboards" row in the app's settings. The user taps that row
    /// to enable the keyboard and allow full access.
    /// This is the same approach Wispr Flow uses.
    static func openKeyboardSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
