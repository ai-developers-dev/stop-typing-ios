import SwiftUI

/// Activation screen shown when opened via stoptyping://activate.
/// Matches Wispr Flow's "Swipe right to speak" pattern.
/// Does NOT auto-record — just activates the background session.
struct DictationOverlayView: View {
    @ObservedObject private var service = BackgroundDictationService.shared
    @Environment(\.dismiss) private var dismiss
    let onClose: () -> Void

    init(onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            // Close button
            HStack {
                Spacer()
                Button {
                    service.deactivateSession()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // Fix 3.3: Activation error card with Retry button
            if let error = service.activationError {
                activationErrorCard(message: error)
            }

            Spacer()

            // Heading
            Text("Swipe right to speak")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .foregroundStyle(Color(UIColor.label))
                .padding(.bottom, 24)

            // Phone mockup card
            VStack(spacing: 16) {
                // Mock message bar
                HStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor.systemGray5))
                        .frame(height: 36)
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        )
                }
                .padding(.horizontal, 16)

                // Mock keyboard area with waveform
                VStack(spacing: 8) {
                    // Checkmark button
                    HStack {
                        Spacer()
                        Circle()
                            .fill(Color(UIColor.darkGray))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                    }
                    .padding(.horizontal, 16)

                    // Waveform
                    HStack(spacing: 3) {
                        ForEach(0..<11, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color(UIColor.darkGray))
                                .frame(width: 3, height: [16, 6, 16, 4, 24, 4, 6, 24, 4, 16, 6][i])
                        }
                    }
                    .padding(.vertical, 12)

                    Text("Listening")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                    Text("iPhone Microphone")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)

                // Home bar
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(UIColor.darkGray))
                    .frame(width: 120, height: 5)
                    .padding(.bottom, 8)
            }
            .padding(.vertical, 20)
            .background(Color(UIColor.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 40)

            Spacer()

            // Explanation text
            Text("We wish you didn't have to switch apps to use Stop Typing, but Apple now requires this to activate the microphone.")
                .font(.system(size: 16))
                .foregroundStyle(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

            // Swipe instruction
            Divider()
                .padding(.horizontal, 60)

            HStack(spacing: 8) {
                Text("Swipe right at the bottom")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(UIColor.label))
                Image(systemName: "hand.draw")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(UIColor.secondaryLabel))
            }
            .padding(.vertical, 20)

            // Debug log — remove before shipping
            if !service.debugLog.isEmpty {
                ScrollView {
                    Text(service.debugLog)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(.horizontal, 16)
                .background(Color(UIColor.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
            }

            Spacer().frame(height: 20)
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            service.activateSession()
        }
    }

    // MARK: - Activation Error Card (Fix 3.3)

    private func activationErrorCard(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("Activation Failed")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(UIColor.label))

            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(UIColor.label))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(UIColor.systemGray4))
                        .clipShape(Capsule())
                }

                Button {
                    service.retryActivation()
                } label: {
                    Text("Retry")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.65, green: 0.55, blue: 0.98),
                                         Color(red: 0.49, green: 0.23, blue: 0.93)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

#Preview {
    DictationOverlayView()
}
