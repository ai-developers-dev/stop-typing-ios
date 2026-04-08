import SwiftUI

// MARK: - Progress Bar

/// Segmented progress bar matching Wispr Flow style.
/// Each segment fills dark when active, light gray when inactive.
struct OnboardingProgressBar: View {
    let currentSegment: Int
    let totalSegments: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSegments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index <= currentSegment
                          ? AppTheme.progressActive
                          : AppTheme.progressInactive)
                    .frame(height: 4)
            }
        }
    }
}

// MARK: - Navigation Bar

/// Top bar with back arrow, progress bar, and optional skip link.
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
                        .foregroundStyle(AppTheme.onboardingPrimaryText)
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
                    .foregroundStyle(AppTheme.onboardingSecondaryText)
                    .frame(width: 40)
            } else {
                Spacer().frame(width: 40)
            }
        }
        .padding(.horizontal, AppTheme.paddingLarge)
        .padding(.top, 8)
    }
}

// MARK: - Dark CTA Button

/// Primary onboarding button — dark charcoal, white text, full width.
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

// MARK: - Soft CTA Button

/// Secondary onboarding button — soft lavender, dark text, full width.
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

/// Serif heading with an optional highlighted word in accent orange.
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
                    .foregroundStyle(AppTheme.onboardingPrimaryText)
                +
                Text(highlight)
                    .font(size)
                    .italic()
                    .foregroundStyle(highlightColor)
                +
                Text(parts.dropFirst().joined(separator: highlight))
                    .font(size)
                    .foregroundStyle(AppTheme.onboardingPrimaryText)
            )
            .multilineTextAlignment(.center)
        } else {
            Text(text)
                .font(size)
                .foregroundStyle(AppTheme.onboardingPrimaryText)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Benefit Row

/// Icon + text row for value proposition lists.
struct BenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(AppTheme.accentOrange)
                .frame(width: 36)

            Text(text)
                .font(AppTheme.onboardingBody)
                .foregroundStyle(AppTheme.onboardingPrimaryText)

            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, AppTheme.paddingMedium)
        .background(AppTheme.onboardingCardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall))
    }
}

// MARK: - Settings Mock Row

/// Fake iOS Settings row for the keyboard setup screen.
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
                .foregroundStyle(.gray)
                .frame(width: 28, height: 28)
                .background(AppTheme.settingsRowBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(AppTheme.onboardingPrimaryText)

            Spacer()

            if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.settingsBorder)
            }

            if hasToggle {
                RoundedRectangle(cornerRadius: 16)
                    .fill(toggleOn ? AppTheme.successGreen : AppTheme.settingsRowBg)
                    .frame(width: 51, height: 31)
                    .overlay(
                        Circle()
                            .fill(.white)
                            .frame(width: 27, height: 27)
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                            .offset(x: toggleOn ? 10 : -10),
                        alignment: .center
                    )
            }
        }
        .padding(.horizontal, AppTheme.paddingMedium)
        .frame(height: 50)
    }
}

/// Container that groups multiple SettingsMockRows with dividers.
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
        .background(AppTheme.onboardingCardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Skip Link

/// "Skip for now" or "Maybe later" style text button.
struct SkipLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.onboardingSkipFont)
                .foregroundStyle(AppTheme.onboardingSecondaryText)
        }
    }
}

// MARK: - Previews

#Preview("Progress Bar") {
    VStack(spacing: 20) {
        OnboardingProgressBar(currentSegment: 0, totalSegments: 4)
        OnboardingProgressBar(currentSegment: 1, totalSegments: 4)
        OnboardingProgressBar(currentSegment: 2, totalSegments: 4)
        OnboardingProgressBar(currentSegment: 3, totalSegments: 4)
    }
    .padding()
}

#Preview("Buttons") {
    VStack(spacing: 16) {
        DarkCTAButton(title: "Get Started") {}
        SoftCTAButton(title: "Set up") {}
        SkipLink(title: "Skip for now") {}
    }
    .padding()
    .background(AppTheme.onboardingBackground)
}

#Preview("Settings Mock") {
    SettingsMockCard(rows: [
        SettingsMockRow(icon: "keyboard", title: "Keyboards", hasChevron: true),
        SettingsMockRow(icon: "keyboard", title: "Stop Typing", hasToggle: true, toggleOn: false),
        SettingsMockRow(icon: "keyboard", title: "Allow Full Access", hasToggle: true, toggleOn: false),
    ])
    .padding()
    .background(AppTheme.onboardingBackground)
}
