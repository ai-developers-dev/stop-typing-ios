import SwiftUI

struct KeyboardSetupView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.paddingLarge) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.system(size: 56))
                        .foregroundStyle(.purple)

                    Text("Set Up Your Keyboard")
                        .font(AppTheme.title)

                    Text("Follow these steps to enable the Stop Typing keyboard on your iPhone.")
                        .font(AppTheme.body)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, AppTheme.paddingMedium)

                // Steps
                VStack(spacing: 0) {
                    setupStepRow(
                        number: 1,
                        title: "Open Settings App",
                        detail: "Open the Settings app on your iPhone (the gear icon on your home screen)",
                        icon: "gear"
                    )

                    Divider().padding(.leading, 52)

                    setupStepRow(
                        number: 2,
                        title: "Go to General",
                        detail: "Scroll down and tap General",
                        icon: "slider.horizontal.3"
                    )

                    Divider().padding(.leading, 52)

                    setupStepRow(
                        number: 3,
                        title: "Open Keyboard Settings",
                        detail: "Tap Keyboard, then tap Keyboards at the top",
                        icon: "keyboard"
                    )

                    Divider().padding(.leading, 52)

                    setupStepRow(
                        number: 4,
                        title: "Add New Keyboard",
                        detail: "Tap Add New Keyboard… and find \"Stop Typing\" in the third-party keyboards list",
                        icon: "plus.circle"
                    )

                    Divider().padding(.leading, 52)

                    setupStepRow(
                        number: 5,
                        title: "Allow Full Access",
                        detail: "Go back to Keyboards, tap Stop Typing, then toggle Allow Full Access on. This lets the keyboard read your transcripts and use rewrite features.",
                        icon: "lock.open"
                    )
                }
                .background(AppTheme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                // Important note
                VStack(spacing: 8) {
                    Label("Why can't we open it for you?", systemImage: "info.circle")
                        .font(AppTheme.headline)
                        .foregroundStyle(AppTheme.primaryText)

                    Text("iOS does not allow apps to open the system keyboard settings directly. You'll need to navigate to Settings → General → Keyboard → Keyboards manually.")
                        .font(AppTheme.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                // Privacy note
                VStack(spacing: 8) {
                    Label("Your Privacy Matters", systemImage: "lock.shield")
                        .font(AppTheme.headline)
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Stop Typing does not log your keystrokes or read what you type in other apps. Full Access is only used to read your latest transcript from shared storage and to connect to rewrite services.")
                        .font(AppTheme.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color.blue.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))

                // How to use
                VStack(alignment: .leading, spacing: 12) {
                    Text("How to Use")
                        .font(AppTheme.headline)

                    howToRow(icon: "1.circle.fill", text: "Record a transcript in the Stop Typing app")
                    howToRow(icon: "2.circle.fill", text: "Switch to Messages, Mail, Notes, or any app")
                    howToRow(icon: "3.circle.fill", text: "Tap the globe icon 🌐 to switch to Stop Typing keyboard")
                    howToRow(icon: "4.circle.fill", text: "Tap \"Insert Latest\" to paste your transcript")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .padding(AppTheme.paddingMedium)
        }
        .background(AppTheme.background)
        .navigationTitle("Keyboard Setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setupStepRow(number: Int, title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.blue))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTheme.headline)
                Text(detail)
                    .font(AppTheme.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Image(systemName: icon)
                .foregroundStyle(.blue.opacity(0.6))
        }
        .padding()
    }

    private func howToRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
                .font(AppTheme.body)
        }
    }
}

#Preview {
    NavigationStack {
        KeyboardSetupView()
    }
}
