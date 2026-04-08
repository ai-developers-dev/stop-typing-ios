import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.secondaryText.opacity(0.5))

            Text(title)
                .font(AppTheme.title)
                .foregroundStyle(AppTheme.primaryText)

            Text(message)
                .font(AppTheme.body)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.paddingLarge)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView(
        icon: "mic.slash",
        title: "No Transcripts Yet",
        message: "Tap Start Flow to record your first transcript."
    )
}
