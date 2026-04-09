import ActivityKit
import SwiftUI
import WidgetKit

struct StopTypingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StopTypingAttributes.self) { context in
            // LOCK SCREEN presentation (all iPhones iOS 16.1+)
            HStack(spacing: 12) {
                // Waveform logo
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.65, green: 0.55, blue: 0.98),
                                     Color(red: 0.49, green: 0.23, blue: 0.93)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stop Typing")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(context.state.isRecording ? "Recording..." : "Ready to dictate")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(context.state.mode)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
            .padding(16)
            .background(Color(.systemBackground))

        } dynamicIsland: { context in
            DynamicIsland {
                // EXPANDED view (long press on Dynamic Island)
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.purple)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.isRecording ? "Recording" : "Ready")
                            .font(.system(size: 15, weight: .semibold))
                        Text(context.state.mode)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 18))
                        .foregroundStyle(context.state.isRecording ? .red : .secondary)
                }

            } compactLeading: {
                // Small logo in compact Dynamic Island — left side
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.purple)

            } compactTrailing: {
                // Recording indicator — right side
                Image(systemName: context.state.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 12))
                    .foregroundStyle(context.state.isRecording ? .red : .secondary)

            } minimal: {
                // When multiple Live Activities — just the logo
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.purple)
            }
        }
    }
}

// Widget bundle
@main
struct StopTypingWidgetBundle: WidgetBundle {
    var body: some Widget {
        StopTypingLiveActivity()
    }
}
