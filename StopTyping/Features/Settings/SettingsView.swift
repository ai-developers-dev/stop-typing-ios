import SwiftUI

struct SettingsView: View {
    @State private var settings = UserSettings.load()
    @StateObject private var permissions = PermissionsManager()

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Transcription Engine
                Section {
                    Picker("Engine", selection: $settings.transcriptionEngine) {
                        ForEach(UserSettings.TranscriptionEngine.allCases, id: \.self) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }
                    .onChange(of: settings.transcriptionEngine) {
                        settings.save()
                    }
                } header: {
                    Text("Transcription")
                } footer: {
                    Text("Apple Speech works on-device. Cloud API requires internet but may be more accurate.")
                }

                // MARK: - Permissions
                Section("Permissions") {
                    HStack {
                        Label("Microphone", systemImage: "mic.fill")
                        Spacer()
                        permissionBadge(granted: permissions.microphoneGranted)
                    }

                    HStack {
                        Label("Speech Recognition", systemImage: "waveform")
                        Spacer()
                        permissionBadge(granted: permissions.speechGranted)
                    }

                    if !permissions.allPermissionsGranted {
                        Button("Open Settings") {
                            permissions.openAppSettings()
                        }
                    }
                }

                // MARK: - Keyboard
                Section {
                    Toggle("Auto-save to Keyboard", isOn: $settings.autoSaveToShared)
                        .onChange(of: settings.autoSaveToShared) {
                            settings.save()
                        }

                    NavigationLink {
                        KeyboardSetupView()
                    } label: {
                        Label("Keyboard Setup", systemImage: "keyboard")
                    }
                } header: {
                    Text("Keyboard Extension")
                } footer: {
                    Text("When enabled, your latest transcript is automatically available in the Stop Typing keyboard.")
                }

                // MARK: - Account Placeholder
                Section("Account") {
                    HStack {
                        Label("Plan", systemImage: "star.fill")
                        Spacer()
                        Text("Free")
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Button("Upgrade to Pro") {
                        // TODO: Subscription paywall
                    }
                }

                // MARK: - About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(AppTheme.secondaryText)
                    }

                    Link("Privacy Policy", destination: URL(string: "https://stoptyping.com/privacy")!)

                    Link("Terms of Service", destination: URL(string: "https://stoptyping.com/terms")!)
                }

                // MARK: - Data
                Section {
                    Button("Clear Shared Transcript") {
                        SharedStateManager.shared.clearTranscript()
                    }

                    Button("Clear All History", role: .destructive) {
                        TranscriptHistoryStore.shared.clearAll()
                    }
                } header: {
                    Text("Data")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func permissionBadge(granted: Bool) -> some View {
        Text(granted ? "Enabled" : "Disabled")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(granted ? .green : .red)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((granted ? Color.green : Color.red).opacity(0.1))
            .clipShape(Capsule())
    }
}

#Preview {
    SettingsView()
}
