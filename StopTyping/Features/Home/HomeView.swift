import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var showCopiedToast = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.paddingLarge) {
                    headerSection
                    actionSection
                    if !viewModel.currentTranscript.isEmpty {
                        transcriptResultSection
                    }
                    latestSharedSection
                }
                .padding(AppTheme.paddingMedium)
            }
            .background(AppTheme.background)
            .navigationTitle("Stop Typing")
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .overlay(alignment: .bottom) {
                if showCopiedToast {
                    copiedToast
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.flowGradient)

            Text("Speak. Insert. Done.")
                .font(AppTheme.title)
                .foregroundStyle(AppTheme.primaryText)

            Text("Record your voice, then use the keyboard\nto insert your transcript anywhere.")
                .font(AppTheme.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, AppTheme.paddingMedium)
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionSection: some View {
        switch viewModel.transcriptionState {
        case .idle:
            PrimaryButton("Start Flow", icon: "mic.fill") {
                Task { await viewModel.startFlow() }
            }

        case .recording:
            VStack(spacing: 16) {
                recordingIndicator
                PrimaryButton("Stop Recording", icon: "stop.fill") {
                    Task { await viewModel.stopFlow() }
                }
                Button("Cancel") {
                    viewModel.cancelFlow()
                }
                .foregroundStyle(AppTheme.destructive)
            }

        case .processing:
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Processing…")
                    .font(AppTheme.body)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.paddingLarge)

        case .completed:
            VStack(spacing: 12) {
                Label("Transcript Ready", systemImage: "checkmark.circle.fill")
                    .font(AppTheme.headline)
                    .foregroundStyle(.green)

                PrimaryButton("New Recording", icon: "mic.fill") {
                    viewModel.reset()
                }
            }

        case .error(let msg):
            VStack(spacing: 12) {
                Label(msg, systemImage: "exclamationmark.triangle")
                    .font(AppTheme.body)
                    .foregroundStyle(.red)

                PrimaryButton("Try Again", icon: "arrow.clockwise") {
                    viewModel.reset()
                }
            }
        }
    }

    // MARK: - Recording Indicator

    private var recordingIndicator: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
                .modifier(PulseModifier())

            Text("Recording…")
                .font(AppTheme.headline)
                .foregroundStyle(AppTheme.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
    }

    // MARK: - Transcript Result

    private var transcriptResultSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Transcript")
                .font(AppTheme.headline)
                .foregroundStyle(AppTheme.primaryText)

            Text(viewModel.currentTranscript)
                .font(AppTheme.body)
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))

            HStack(spacing: 12) {
                SecondaryButton("Copy", icon: "doc.on.doc") {
                    viewModel.copyTranscript()
                    withAnimation { showCopiedToast = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation { showCopiedToast = false }
                    }
                }

                SecondaryButton("Share", icon: "square.and.arrow.up") {
                    // Share sheet could go here
                }
            }

            Text("Switch to any app and use the Stop Typing keyboard to insert this transcript.")
                .font(AppTheme.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.top, 4)
        }
    }

    // MARK: - Latest Shared

    private var latestSharedSection: some View {
        Group {
            if let transcript = SharedStateManager.shared.latestTranscript,
               !transcript.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Available in Keyboard")
                            .font(AppTheme.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        Image(systemName: "keyboard")
                            .foregroundStyle(.blue)
                    }
                    Text(transcript.prefix(100) + (transcript.count > 100 ? "…" : ""))
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.primaryText)
                }
                .cardStyle()
            }
        }
    }

    // MARK: - Toast

    private var copiedToast: some View {
        Text("Copied to clipboard")
            .font(AppTheme.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(.black.opacity(0.8)))
            .padding(.bottom, 32)
    }
}

// MARK: - Pulse Animation

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

#Preview {
    HomeView()
}
