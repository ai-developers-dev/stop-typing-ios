import SwiftUI

struct OnboardingView: View {
    @StateObject private var permissions = PermissionsManager()
    @StateObject private var speechService = AppleSpeechService()
    @AppStorage("onboardingCurrentPage") private var currentPage = 0
    @State private var testTranscript = ""
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var showTestSuccess = false
    @State private var testError = ""
    var onComplete: () -> Void

    private let totalSegments = 3

    var body: some View {
        ZStack {
            AppTheme.onboardingBackground.ignoresSafeArea()

            Group {
                switch currentPage {
                case 0: welcomeHeroPage       // Welcome
                case 1: valuePropsPage        // Value props
                case 2: microphonePage        // Mic permission
                case 3: setupIntroPage        // "Let's set up"
                case 4: keyboardSettingsPage  // Mock settings + Go to Settings
                case 5: testDictationPage     // Real dictation test
                case 6: useKeyboardPage       // How to switch to Stop Typing keyboard
                default: useKeyboardPage
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .animation(.easeInOut(duration: 0.3), value: currentPage)
        }
        .onAppear {
            if currentPage > 6 { currentPage = 0 }
        }
    }

    private func goTo(_ page: Int) {
        withAnimation { currentPage = page }
    }

    private func goBack() {
        withAnimation { currentPage = max(0, currentPage - 1) }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Screen 0: Welcome Hero
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var welcomeHeroPage: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(AppTheme.flowGradient)
                .padding(.bottom, 24)

            Text("Stop Typing")
                .font(AppTheme.onboardingHeroHeading)
                .foregroundStyle(AppTheme.onboardingPrimaryText)
                .padding(.bottom, 12)

            (
                Text("Your voice, ")
                    .foregroundStyle(AppTheme.onboardingPrimaryText)
                +
                Text("4x faster")
                    .foregroundStyle(AppTheme.accentOrange)
                    .italic()
                +
                Text("\nthan typing")
                    .foregroundStyle(AppTheme.onboardingPrimaryText)
            )
            .font(AppTheme.onboardingHeading)
            .multilineTextAlignment(.center)

            Spacer()

            DarkCTAButton(title: "Get Started") {
                goTo(1)
            }
            .padding(.horizontal, AppTheme.paddingLarge)
            .padding(.bottom, AppTheme.paddingXL)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Screen 1: Value Props
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var valuePropsPage: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(
                showBack: true, onBack: goBack,
                currentSegment: 0, totalSegments: totalSegments
            )

            Spacer()

            OnboardingHeading(text: "Your voice works\neverywhere")
                .padding(.bottom, 32)

            VStack(spacing: 12) {
                BenefitRow(icon: "message.fill", text: "Dictate messages instantly")
                BenefitRow(icon: "envelope.fill", text: "Write emails in seconds")
                BenefitRow(icon: "note.text", text: "Capture ideas on the go")
            }
            .padding(.horizontal, AppTheme.paddingLarge)

            Spacer()

            DarkCTAButton(title: "Next") {
                goTo(2)
            }
            .padding(.horizontal, AppTheme.paddingLarge)
            .padding(.bottom, AppTheme.paddingXL)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Screen 2: Microphone Permission
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var microphonePage: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(
                showBack: true, onBack: goBack,
                currentSegment: 1, totalSegments: totalSegments
            )

            Spacer()

            Image(systemName: "mic.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(AppTheme.flowGradient)
                .padding(.bottom, 24)

            OnboardingHeading(text: "Enable your\nmicrophone")
                .padding(.bottom, 12)

            Text("Stop Typing needs microphone access\nto transcribe your voice.")
                .font(AppTheme.onboardingSubhead)
                .foregroundStyle(AppTheme.onboardingSecondaryText)
                .multilineTextAlignment(.center)

            Spacer()

            if permissions.microphoneGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.successGreen)
                    Text("Microphone enabled")
                        .font(AppTheme.onboardingBody)
                        .foregroundStyle(AppTheme.onboardingPrimaryText)
                }
                .padding(.bottom, 16)

                DarkCTAButton(title: "Continue") {
                    goTo(3)
                }
                .padding(.horizontal, AppTheme.paddingLarge)
            } else {
                DarkCTAButton(title: "Enable Microphone") {
                    Task {
                        let mic = await permissions.requestMicrophone()
                        if mic {
                            // Also request speech recognition so user doesn't get
                            // a second popup later on the dictation test screen
                            await permissions.requestSpeechRecognition()
                        }
                        if permissions.microphoneGranted {
                            goTo(3)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.paddingLarge)

                SkipLink(title: "Skip for now") { goTo(3) }
                    .padding(.top, 12)
            }

            Spacer().frame(height: AppTheme.paddingXL)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Screen 3: Setup Intro
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var setupIntroPage: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(
                showBack: true, onBack: goBack,
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
                .foregroundStyle(AppTheme.onboardingSecondaryText)

            Spacer()

            SoftCTAButton(title: "Set up") {
                goTo(4)
            }
            .padding(.horizontal, AppTheme.paddingLarge)
            .padding(.bottom, AppTheme.paddingXL)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Screen 4: Keyboard Settings (Mock UI)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var keyboardSettingsPage: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(
                showBack: true, onBack: goBack,
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

                    (
                        Text("We provide 100% privacy. We ")
                            .font(AppTheme.onboardingPrivacyFont)
                            .foregroundStyle(AppTheme.onboardingSecondaryText)
                        +
                        Text("never store or read")
                            .font(AppTheme.onboardingPrivacyFont)
                            .bold()
                            .foregroundStyle(AppTheme.onboardingSecondaryText)
                        +
                        Text(" what you say. Full Keyboard Access just allows Stop Typing to work across your apps.")
                            .font(AppTheme.onboardingPrivacyFont)
                            .foregroundStyle(AppTheme.onboardingSecondaryText)
                    )
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.paddingLarge)

                    DarkCTAButton(title: "Go to Settings") {
                        PermissionsManager.openKeyboardSettings()
                    }
                    .padding(.horizontal, AppTheme.paddingLarge)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Click Keyboards", systemImage: "keyboard")
                        Label("Turn on Stop Typing", systemImage: "togglepower")
                        Label("Turn on Allow Full Access", systemImage: "checkmark.square")
                        Label("Tap Allow on the popup", systemImage: "hand.tap")
                        Label("Come back to this app", systemImage: "arrow.uturn.backward")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(AppTheme.paddingMedium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.ctaDark)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, AppTheme.paddingLarge)

                    SoftCTAButton(title: "I've enabled it — Next") {
                        goTo(5)
                    }
                    .padding(.horizontal, AppTheme.paddingLarge)

                    SkipLink(title: "Skip for now") { goTo(5) }
                        .padding(.bottom, AppTheme.paddingXL)
                }
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Screen 5: Test Dictation
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var testDictationPage: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(
                showBack: true, onBack: goBack,
                showSkip: true, onSkip: { goTo(6) },
                currentSegment: 2, totalSegments: totalSegments
            )

            VStack(spacing: 16) {
                OnboardingHeading(text: "Say anything and see\nit appear like magic ✨")
                    .padding(.top, 24)

                VStack(alignment: .leading) {
                    if testTranscript.isEmpty {
                        Text("Say something!")
                            .font(AppTheme.onboardingBody)
                            .foregroundStyle(AppTheme.onboardingSecondaryText.opacity(0.5))
                    } else {
                        Text(testTranscript)
                            .font(AppTheme.onboardingBody)
                            .foregroundStyle(AppTheme.onboardingPrimaryText)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                .padding()
                .background(AppTheme.onboardingCardBg)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)

                if showTestSuccess {
                    Text("Congrats on your first dictation 🎉")
                        .font(AppTheme.onboardingBody)
                        .foregroundStyle(AppTheme.onboardingPrimaryText)
                        .padding(.top, 8)

                    DarkCTAButton(title: "Next") {
                        goTo(6)
                    }
                } else if isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Processing...")
                            .font(AppTheme.onboardingSubhead)
                            .foregroundStyle(AppTheme.onboardingSecondaryText)
                    }
                    .padding(.top, 16)
                } else if isRecording {
                    VStack(spacing: 12) {
                        HStack(spacing: 4) {
                            ForEach(0..<9, id: \.self) { _ in
                                Circle()
                                    .fill(AppTheme.onboardingPrimaryText)
                                    .frame(width: 8, height: 8)
                                    .opacity(Double.random(in: 0.3...1.0))
                            }
                        }

                        Text("Listening...")
                            .font(AppTheme.onboardingSubhead)
                            .foregroundStyle(AppTheme.onboardingSecondaryText)

                        HStack(spacing: 24) {
                            Button {
                                speechService.cancel()
                                isRecording = false
                                testTranscript = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(AppTheme.onboardingPrimaryText)
                                    .frame(width: 44, height: 44)
                                    .background(AppTheme.settingsRowBg)
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
                } else {
                    if !testError.isEmpty {
                        Text(testError)
                            .font(AppTheme.onboardingPrivacyFont)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }

                    HStack {
                        Text("Tap the mic to start speaking →")
                            .font(AppTheme.onboardingSubhead)
                            .foregroundStyle(AppTheme.onboardingSecondaryText)

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
            .padding(.horizontal, AppTheme.paddingLarge)

            Spacer()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Screen 6: How to Use Keyboard (LAST)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var useKeyboardPage: some View {
        VStack(spacing: 0) {
            OnboardingNavBar(
                showBack: true, onBack: goBack,
                currentSegment: 2, totalSegments: totalSegments
            )

            Spacer()

            OnboardingHeading(text: "Now use your\nStop Typing keyboard")
                .padding(.bottom, 16)

            Text("In any text field, tap and hold 🌐\nthen select Stop Typing")
                .font(AppTheme.onboardingSubhead)
                .foregroundStyle(AppTheme.onboardingSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.bottom, 32)

            // Mock keyboard switcher
            VStack(spacing: 0) {
                switcherRow("Keyboard Settings...", selected: false, divider: true)
                switcherRow("English (US)", selected: false, divider: true)
                switcherRow("Emoji", selected: false, divider: true)
                switcherRow("Stop Typing", selected: true, divider: false)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
            .padding(.horizontal, 60)

            Spacer()

            DarkCTAButton(title: "Start Using Stop Typing") {
                onComplete()
            }
            .padding(.horizontal, AppTheme.paddingLarge)
            .padding(.bottom, AppTheme.paddingXL)
        }
    }

    private func switcherRow(_ title: String, selected: Bool, divider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? .blue : AppTheme.onboardingPrimaryText)
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
