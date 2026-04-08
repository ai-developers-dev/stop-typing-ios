import SwiftUI

struct TranscriptCard: View {
    let item: TranscriptItem
    var onCopy: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.formattedDate)
                    .font(AppTheme.caption)
                    .foregroundStyle(AppTheme.secondaryText)

                Spacer()

                if let mode = item.rewriteMode {
                    Label(mode.rawValue, systemImage: mode.icon)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }

            Text(item.text)
                .font(AppTheme.body)
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(4)

            if let onCopy {
                HStack {
                    Spacer()
                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(AppTheme.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .cardStyle()
    }
}
