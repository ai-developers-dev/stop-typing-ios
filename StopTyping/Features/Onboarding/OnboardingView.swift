import SwiftUI

// MARK: - Root Onboarding View
//
// Lightweight wrapper that only owns navigation state. No expensive @StateObject
// at this level — pages that need system services (permissions, speech) own their
// own StateObjects so they're created lazily when the user actually reaches them.

struct OnboardingView: View {
    @AppStorage("onboardingCurrentPage") private var currentPage = 0
    var onComplete: () -> Void

    private let totalSegments = 3

    var body: some View {
        ZStack {
            AppTheme.surface.ignoresSafeArea()

            pageView
        }
        .onAppear {
            if currentPage > 6 { currentPage = 0 }
        }
    }

    @ViewBuilder
    private var pageView: some View {
        switch currentPage {
        case 0:
            WelcomeHeroPage(onNext: { goTo(1) })
        case 1:
            ValuePropsPage(
                onBack: { goBack() },
                onNext: { goTo(2) },
                totalSegments: totalSegments
            )
        case 2:
            MicrophonePermissionPage(
                onBack: { goBack() },
                onNext: { goTo(3) },
                totalSegments: totalSegments
            )
        case 3:
            SetupIntroPage(
                onBack: { goBack() },
                onNext: { goTo(4) },
                totalSegments: totalSegments
            )
        case 4:
            KeyboardSettingsPage(
                onBack: { goBack() },
                onNext: { goTo(5) },
                totalSegments: totalSegments
            )
        case 5:
            TestDictationPage(
                onBack: { goBack() },
                onNext: { goTo(6) },
                totalSegments: totalSegments
            )
        default:
            UseKeyboardPage(
                onBack: { goBack() },
                onComplete: onComplete,
                totalSegments: totalSegments
            )
        }
    }

    private func goTo(_ page: Int) {
        withAnimation(.easeInOut(duration: 0.3)) { currentPage = page }
    }

    private func goBack() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage = max(0, currentPage - 1)
        }
    }
}

// MARK: - Screen 0: Welcome Hero

struct WelcomeHeroPage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Waveform logo in purple gradient circle
            Image(systemName: "waveform")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#A78BFA"), Color(hex: "#7C3AED")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .padding(.bottom, 20)

            Text("Stop\nTyping")
                .font(AppTheme.onboardingHeroHeading)
                .foregroundStyle(AppTheme.onSurface)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)

            (
                Text("Your voice, ")
                    .foregroundStyle(AppTheme.onSurface)
                +
                Text("4x faster")
                    .foregroundStyle(AppTheme.accentOrange)
                    .italic()
                +
                Text(" than typing")
                    .foregroundStyle(AppTheme.onSurface)
            )
            .font(AppTheme.onboardingHeading)
            .multilineTextAlignment(.center)

            Spacer()

            DarkCTAButton(title: "Get Started", action: onNext)
                .padding(.horizontal, AppTheme.paddingLarge)
                .padding(.bottom, AppTheme.paddingXL)
        }
    }
}

// MARK: - Screen 1: Value Props

struct ValuePropsPage: View {
    let onBack: () -> Void
    let onNext: () -> Void
    let totalSegments: Int

    var body: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(
                showBack: true, onBack: onBack,
                currentSegment: 0, totalSegments: totalSegments
            )

            Spacer()

            OnboardingHeading(
                text: "Your voice works\neverywhere",
                highlight: "everywhere",
                highlightColor: AppTheme.accentOrange
            )
            .padding(.bottom, 32)

            VStack(spacing: 12) {
                BenefitRow(icon: "message.fill", text: "Dictate messages instantly")
                BenefitRow(icon: "envelope.fill", text: "Write emails in seconds")
                BenefitRow(icon: "note.text", text: "Capture ideas on the go")
            }
            .padding(.horizontal, AppTheme.paddingLarge)

            Spacer()

            DarkCTAButton(title: "Next", action: onNext)
                .padding(.horizontal, AppTheme.paddingLarge)
                .padding(.bottom, AppTheme.paddingXL)
        }
    }
}

// MARK: - Screen 2: Microphone Permission
//
// This is the FIRST page that needs PermissionsManager. It owns its own
// @StateObject so the system APIs are only touched when the user reaches
// this screen, not at app launch.

struct MicrophonePermissionPage: View {
    let onBack: () -> Void
    let onNext: () -> Void
    let totalSegments: Int

    @StateObject private var permissions = PermissionsManager()

    var body: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(
                showBack: true, onBack: onBack,
                currentSegment: 1, totalSegments: totalSegments
            )

            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#A78BFA"), Color(hex: "#7C3AED")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
                .padding(.bottom, 24)

            OnboardingHeading(text: "Enable your\nmicrophone")
                .padding(.bottom, 12)

            Text("Stop Typing needs microphone access\nto transcribe your voice.")
                .font(AppTheme.onboardingSubhead)
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .multilineTextAlignment(.center)

            Spacer()

            if permissions.microphoneGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.successGreen)
                    Text("Microphone enabled")
                        .font(AppTheme.onboardingBody)
                        .foregroundStyle(AppTheme.onSurface)
                }
                .padding(.bottom, 16)

                DarkCTAButton(title: "Continue", action: onNext)
                    .padding(.horizontal, AppTheme.paddingLarge)
            } else {
                DarkCTAButton(title: "Enable Microphone") {
                    Task {
                        let mic = await permissions.requestMicrophone()
                        if mic {
                            _ = await permissions.requestSpeechRecognition()
                        }
                        if permissions.microphoneGranted {
                            onNext()
                        }
                    }
                }
                .padding(.horizontal, AppTheme.paddingLarge)

                SkipLink(title: "Skip for now", action: onNext)
                    .padding(.top, 12)
            }

            Spacer().frame(height: AppTheme.paddingXL)
        }
    }
}

// MARK: - Screen 3: Setup Intro

struct SetupIntroPage: View {
    let onBack: () -> Void
    let onNext: () -> Void
    let totalSegments: Int

    var body: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(
                showBack: true, onBack: onBack,
                currentSegment: 2, totalSegments: totalSegments
            )

            Spacer()

            OnboardingHeading(
                text: "Let's set up\nStop Typing",
                highlight: "set up",
                size: AppTheme.onboardingHeroHeading
            )
            .padding(.bottom, 16)

            Text("This only takes a moment")
                .font(AppTheme.onboardingSubhead)
                .foregroundStyle(AppTheme.onSurfaceVariant)

            Spacer()

            SoftCTAButton(title: "Set up", action: onNext)
                .padding(.horizontal, AppTheme.paddingLarge)
                .padding(.bottom, AppTheme.paddingXL)
        }
    }
}

// MARK: - Screen 4: Keyboard Settings

struct KeyboardSettingsPage: View {
    let onBack: () -> Void
    let onNext: () -> Void
    let totalSegments: Int

    var body: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(
                showBack: true, onBack: onBack,
                currentSegment: 2, totalSegments: totalSegments
            )

            ScrollView {
                VStack(spacing: 24) {
                    OnboardingHeading(text: "Set up your Stop Typing\nKeyboard in Settings")
                        .padding(.top, 16)

                    SettingsMockCard(rows: [
                        SettingsMockRow(icon: "keyboard", title: "Keyboards", hasChevron: true),
                        SettingsMockRow(icon: "keyboard", title: "Stop Typing", hasToggle: true, toggleOn: false),
                        SettingsMockRow(icon: "keyboard", title: "Allow Full Access", hasToggle: true, toggleOn: false),
                    ])
                    .padding(.horizontal, AppTheme.paddingLarge)

                    Text("We provide 100% privacy. We never store or read what you say. Full Keyboard Access just allows Stop Typing to work across your apps.")
                        .font(AppTheme.onboardingPrivacyFont)
                        .foregroundStyle(AppTheme.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.paddingLarge)

                    DarkCTAButton(title: "Go to Settings") {
                        PermissionsManager.openKeyboardSettings()
                    }
                    .padding(.horizontal, AppTheme.paddingLarge)

                    VStack(alignment: .leading, spacing: 8) {
                        instructionRow(icon: "keyboard", text: "Click Keyboards", color: .green)
                        instructionRow(icon: "togglepower", text: "Turn on Stop Typing", color: .green)
                        instructionRow(icon: "checkmark.square", text: "Turn on Allow Full Access", color: .green)
                        instructionRow(icon: "hand.tap", text: "Tap Allow on the popup", color: .green)
                        instructionRow(icon: "arrow.uturn.backward", text: "Come back to this app", color: .green)
                    }
                    .padding(AppTheme.paddingMedium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.ctaDark)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, AppTheme.paddingLarge)

                    SoftCTAButton(title: "I've enabled it — Next", action: onNext)
                        .padding(.horizontal, AppTheme.paddingLarge)

                    SkipLink(title: "Skip for now", action: onNext)
                        .padding(.bottom, AppTheme.paddingXL)
                }
            }
        }
    }

    private func instructionRow(icon: String, text: String, color: Color) -> some View {
        Label {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Screen 5: Test Dictation
//
// This is the ONLY page that needs AppleSpeechService + PermissionsManager.
// They're owned here so they're only created when the user reaches this screen.

struct TestDictationPage: View {
    let onBack: () -> Void
    let onNext: () -> Void
    let totalSegments: Int

    @StateObject private var permissions = PermissionsManager()
    @StateObject private var speechService = AppleSpeechService()

    @State private var testTranscript = ""
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var showTestSuccess = false
    @State private var testError = ""

    var body: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(
                showBack: true, onBack: onBack,
                showSkip: true, onSkip: onNext,
                currentSegment: 2, totalSegments: totalSegments
            )

            VStack(spacing: 16) {
                OnboardingHeading(text: "Say anything and see\nit appear like magic ✨")
                    .padding(.top, 24)

                // Text field card
                VStack(alignment: .leading) {
                    if testTranscript.isEmpty {
                        Text("Say something!")
                            .font(AppTheme.onboardingBody)
                            .foregroundStyle(AppTheme.accentOrange.opacity(0.6))
                    } else {
                        Text(testTranscript)
                            .font(AppTheme.onboardingBody)
                            .foregroundStyle(AppTheme.onSurface)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
                .shadow(color: Color(hex: "#1B1B22").opacity(0.04), radius: 8, x: 0, y: 2)

                if showTestSuccess {
                    Text("Congrats on your first dictation 🎉")
                        .font(AppTheme.onboardingBody)
                        .foregroundStyle(AppTheme.onSurface)
                        .padding(.top, 8)

                    DarkCTAButton(title: "Next", action: onNext)
                } else if isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Processing...")
                            .font(AppTheme.onboardingSubhead)
                            .foregroundStyle(AppTheme.onSurfaceVariant)
                    }
                    .padding(.top, 16)
                } else if isRecording {
                    recordingControls
                } else {
                    startControls
                }
            }
            .padding(.horizontal, AppTheme.paddingLarge)

            Spacer()
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<9, id: \.self) { _ in
                    Circle()
                        .fill(AppTheme.onSurface)
                        .frame(width: 8, height: 8)
                        .opacity(Double.random(in: 0.3...1.0))
                }
            }

            Text("Listening...")
                .font(AppTheme.onboardingSubhead)
                .foregroundStyle(AppTheme.onSurfaceVariant)

            HStack(spacing: 24) {
                Button {
                    speechService.cancel()
                    isRecording = false
                    testTranscript = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.onSurface)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.surfaceContainerHigh)
                        .clipShape(Circle())
                }

                Button {
                    Task {
                        isRecording = false
                        isProcessing = true
                        do {
                            let transcript = try await speechService.stopRecording()
                            testTranscript = transcript
                            showTestSuccess = true
                        } catch {
                            testError = error.localizedDescription
                            testTranscript = ""
                        }
                        isProcessing = false
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.ctaDark)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.top, 16)
    }

    private var startControls: some View {
        VStack {
            if !testError.isEmpty {
                Text(testError)
                    .font(AppTheme.onboardingPrivacyFont)
                    .foregroundStyle(AppTheme.error)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            HStack {
                Text("Tap the mic to start speaking →")
                    .font(AppTheme.onboardingSubhead)
                    .foregroundStyle(AppTheme.onSurfaceVariant)

                Button {
                    Task {
                        testError = ""
                        if !permissions.microphoneGranted {
                            let granted = await permissions.requestMicrophone()
                            guard granted else {
                                testError = "Microphone access is needed."
                                return
                            }
                        }
                        if !permissions.speechGranted {
                            let granted = await permissions.requestSpeechRecognition()
                            guard granted else {
                                testError = "Speech recognition access is needed."
                                return
                            }
                        }
                        do {
                            try await speechService.startRecording()
                            isRecording = true
                        } catch {
                            testError = error.localizedDescription
                        }
                    }
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.ctaDark)
                        .clipShape(Circle())
                }
            }
            .padding(.top, 16)
        }
    }
}

// MARK: - Screen 6: Use Keyboard (LAST)

struct UseKeyboardPage: View {
    let onBack: () -> Void
    let onComplete: () -> Void
    let totalSegments: Int

    var body: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(
                showBack: true, onBack: onBack,
                currentSegment: 2, totalSegments: totalSegments
            )

            Spacer()

            OnboardingHeading(text: "Now use your\nStop Typing keyboard")
                .padding(.bottom, 16)

            Text("In any text field, tap and hold 🌐\nthen select Stop Typing")
                .font(AppTheme.onboardingSubhead)
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.bottom, 32)

            // Mock keyboard switcher
            VStack(spacing: 0) {
                switcherRow("Keyboard Settings...", selected: false, divider: true)
                switcherRow("English (US)", selected: false, divider: true)
                switcherRow("Emoji", selected: false, divider: true)
                switcherRow("Stop Typing", selected: true, divider: false)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color(hex: "#1B1B22").opacity(0.1), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 60)

            Spacer()

            DarkCTAButton(title: "Start Using Stop Typing", action: onComplete)
                .padding(.horizontal, AppTheme.paddingLarge)
                .padding(.bottom, AppTheme.paddingXL)
        }
    }

    private func switcherRow(_ title: String, selected: Bool, divider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? .blue : AppTheme.onSurface)
                    .fontWeight(selected ? .medium : .regular)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if divider {
                Divider().padding(.leading, 16)
            }
        }
    }
}

#Preview {
    OnboardingView { }
}
