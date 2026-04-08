import SwiftUI

/// Full-screen recording view — optional alternative to inline recording on Home.
/// Can be presented as a sheet for a more immersive recording experience.
struct RecordingView: View {
    @StateObject private var viewModel = HomeViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Waveform visualization placeholder
            ZStack {
                Circle()
                    .fill(viewModel.isRecording ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                    .frame(width: 200, height: 200)
                    .scaleEffect(viewModel.isRecording ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: viewModel.isRecording)

                Circle()
                    .fill(viewModel.isRecording ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                    .frame(width: 140, height: 140)

                Image(systemName: viewModel.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(viewModel.isRecording ? .red : .blue)
            }

            Text(statusText)
                .font(AppTheme.title)
                .foregroundStyle(AppTheme.primaryText)

            if !viewModel.currentTranscript.isEmpty {
                Text(viewModel.currentTranscript)
                    .font(AppTheme.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.paddingLarge)
                    .lineLimit(5)
            }

            Spacer()

            // Controls
            HStack(spacing: 24) {
                if viewModel.isRecording {
                    Button {
                        viewModel.cancelFlow()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 24))
                            .frame(width: 56, height: 56)
                            .background(AppTheme.secondaryBackground)
                            .clipShape(Circle())
                    }

                    Button {
                        Task { await viewModel.stopFlow() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                            .frame(width: 80, height: 80)
                            .background(Color.red)
                            .clipShape(Circle())
                            .shadow(color: .red.opacity(0.4), radius: 12)
                    }
                } else if case .completed = viewModel.transcriptionState {
                    PrimaryButton("Done", icon: "checkmark") {
                        dismiss()
                    }
                } else {
                    Button {
                        Task { await viewModel.startFlow() }
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                            .frame(width: 80, height: 80)
                            .background(AppTheme.flowGradient)
                            .clipShape(Circle())
                            .shadow(color: .blue.opacity(0.4), radius: 12)
                    }
                }
            }

            Spacer().frame(height: AppTheme.paddingXL)
        }
        .background(AppTheme.background)
    }

    private var statusText: String {
        switch viewModel.transcriptionState {
        case .idle: return "Tap to Record"
        case .recording: return "Listening…"
        case .processing: return "Processing…"
        case .completed: return "Done!"
        case .error(let msg): return msg
        }
    }
}

#Preview {
    RecordingView()
}
