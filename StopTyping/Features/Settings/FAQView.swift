import SwiftUI

struct FAQView: View {
    var body: some View {
        List {
            FAQItem(
                question: "Why is there a small mic icon in the bottom-right corner of the keyboard?",
                answer: """
                That's iOS's built-in dictation button — Apple added it to all custom keyboards in iOS 18. It's NOT Stop Typing.

                Use the PURPLE waveform button at the top of our keyboard to access Stop Typing's smart dictation and AI cleanup features.

                To remove Apple's system mic system-wide: Settings → General → Keyboard → turn off "Enable Dictation". This disables it in all keyboards (including Apple's).
                """,
                icon: "mic.slash"
            )

            FAQItem(
                question: "How do I start dictation with Stop Typing?",
                answer: """
                1. Switch to the Stop Typing keyboard (tap the globe icon on iOS's keyboard)
                2. Tap the PURPLE waveform button at the top of our keyboard
                3. Speak naturally — we'll clean up filler words and add punctuation
                4. Tap the checkmark to insert, or X to cancel
                """,
                icon: "waveform"
            )

            FAQItem(
                question: "Why do I have to click 'Start ST' sometimes?",
                answer: """
                iOS suspends background apps to save battery. When our app is suspended, the keyboard shows "Start ST" to bring it back.

                This should happen rarely — if it happens frequently, check Settings → Stop Typing → Background App Refresh is ON.
                """,
                icon: "arrow.clockwise"
            )

            FAQItem(
                question: "Can I insert photos from the keyboard?",
                answer: """
                No — Apple doesn't allow custom keyboards to insert images directly. Use the app's native photo picker (the + button in Messages, etc.) to add photos.
                """,
                icon: "photo"
            )

            FAQItem(
                question: "What do the Formal/Casual/Friendly/Short modes do?",
                answer: """
                These will rewrite your transcript in different tones. This feature is coming soon — currently the mode selector only affects the Dynamic Island display.
                """,
                icon: "text.bubble"
            )

            FAQItem(
                question: "Can't send a photo in Messages?",
                answer: """
                This is usually not a Stop Typing issue. Check:

                1. Settings → Messages → Enable "MMS Messaging"
                2. Ensure you have cellular signal (MMS doesn't work on WiFi-only with most carriers)
                3. Try a JPG photo instead of HEIC (Settings → Camera → Formats → "Most Compatible")
                4. Check for iOS updates (Settings → General → Software Update)
                """,
                icon: "exclamationmark.bubble"
            )
        }
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FAQItem: View {
    let question: String
    let answer: String
    let icon: String

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.purple)
                        .frame(width: 24)

                    Text(question)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                Text(answer)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 36)
                    .padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        FAQView()
    }
}
