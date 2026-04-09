import ActivityKit
import WidgetKit
import SwiftUI

// StopTypingWidgetAttributes is defined in Shared/StopTypingActivity.swift

struct StopTypingWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StopTypingWidgetAttributes.self) { context in
            // LOCK SCREEN presentation (all iPhones iOS 16.1+)
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.7), Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stop Typing")
                        .font(.system(size: 14, weight: .semibold))

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

        } dynamicIsland: { context in
            DynamicIsland {
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
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.purple)

            } compactTrailing: {
                Image(systemName: context.state.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 12))
                    .foregroundStyle(context.state.isRecording ? .red : .secondary)

            } minimal: {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.purple)
            }
        }
    }
}
