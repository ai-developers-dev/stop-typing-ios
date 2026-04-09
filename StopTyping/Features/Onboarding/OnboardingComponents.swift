import SwiftUI

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let currentSegment: Int
    let totalSegments: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSegments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index <= currentSegment
                          ? AppTheme.ctaDark
                          : AppTheme.surfaceDim)
                    .frame(height: 4)
            }
        }
    }
}

// MARK: - Navigation Bar

struct OnboardingNavBar: View {
    let showBack: Bool
    let onBack: () -> Void
    var showSkip: Bool = false
    var onSkip: (() -> Void)? = nil
    let currentSegment: Int
    let totalSegments: Int

    var body: some View {
        HStack(spacing: 12) {
            if showBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(AppTheme.onSurface)
                }
                .frame(width: 32)
            } else {
                Spacer().frame(width: 32)
            }

            OnboardingProgressBar(
                currentSegment: currentSegment,
                totalSegments: totalSegments
            )

            if showSkip, let onSkip {
                Button("Skip", action: onSkip)
                    .font(AppTheme.onboardingSkipFont)
                    .foregroundStyle(AppTheme.onSurfaceVariant)
                    .frame(width: 40)
            } else {
                Spacer().frame(width: 40)
            }
        }
        .padding(.horizontal, AppTheme.paddingLarge)
        .padding(.top, 8)
    }
}

// MARK: - Dark CTA Button (Obsidian)

struct DarkCTAButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.onboardingCTAFont)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(AppTheme.ctaDark)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.ctaCornerRadius))
        }
    }
}

// MARK: - Soft CTA Button (Lavender)

struct SoftCTAButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.onboardingCTAFont)
                .foregroundStyle(AppTheme.ctaSoftText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(AppTheme.ctaSoft)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.ctaCornerRadius))
        }
    }
}

// MARK: - Onboarding Heading

struct OnboardingHeading: View {
    let text: String
    var highlight: String? = nil
    var highlightColor: Color = AppTheme.accentOrange
    var size: Font = AppTheme.onboardingHeading

    var body: some View {
        if let highlight, text.contains(highlight) {
            let parts = text.components(separatedBy: highlight)
            (
                Text(parts.first ?? "")
                    .font(size)
                    .foregroundStyle(AppTheme.onSurface)
                +
                Text(highlight)
                    .font(size)
                    .italic()
                    .foregroundStyle(highlightColor)
                +
                Text(parts.dropFirst().joined(separator: highlight))
                    .font(size)
                    .foregroundStyle(AppTheme.onSurface)
            )
            .multilineTextAlignment(.center)
        } else {
            Text(text)
                .font(size)
                .foregroundStyle(AppTheme.onSurface)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Benefit Row

struct BenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(AppTheme.accentOrange)
                .frame(width: 40, height: 40)
                .background(AppTheme.surfaceContainerHigh)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(text)
                .font(AppTheme.onboardingBody)
                .foregroundStyle(AppTheme.onSurface)

            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, AppTheme.paddingMedium)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
        .shadow(color: Color(hex: "#1B1B22").opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Settings Mock Row

struct SettingsMockRow: View {
    let icon: String
    let title: String
    var hasChevron: Bool = false
    var hasToggle: Bool = false
    var toggleOn: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(AppTheme.onSurfaceVariant)
                .frame(width: 28, height: 28)

            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.onSurface)

            Spacer()

            if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.surfaceDim)
            }

            if hasToggle {
                RoundedRectangle(cornerRadius: 16)
                    .fill(toggleOn ? AppTheme.successGreen : AppTheme.surfaceContainerHigh)
                    .frame(width: 51, height: 31)
                    .overlay(
                        Circle()
                            .fill(.white)
                            .frame(width: 27, height: 27)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            .offset(x: toggleOn ? 10 : -10),
                        alignment: .center
                    )
            }
        }
        .padding(.horizontal, AppTheme.paddingMedium)
        .frame(height: 50)
    }
}

struct SettingsMockCard: View {
    let rows: [SettingsMockRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                row
                if index < rows.count - 1 {
                    Divider()
                        .padding(.leading, 56)
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
        .shadow(color: Color(hex: "#1B1B22").opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Skip Link

struct SkipLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.onboardingSkipFont)
                .foregroundStyle(AppTheme.onSurfaceVariant)
        }
    }
}

// MARK: - Previews

#Preview("Buttons") {
    VStack(spacing: 16) {
        DarkCTAButton(title: "Get Started") {}
        SoftCTAButton(title: "Set up") {}
        SkipLink(title: "Skip for now") {}
    }
    .padding()
    .background(AppTheme.surface)
}

#Preview("Benefit Rows") {
    VStack(spacing: 12) {
        BenefitRow(icon: "message.fill", text: "Dictate messages instantly")
        BenefitRow(icon: "envelope.fill", text: "Write emails in seconds")
        BenefitRow(icon: "note.text", text: "Capture ideas on the go")
    }
    .padding()
    .background(AppTheme.surface)
}
