import SwiftUI

enum AppTheme {

    // MARK: - Colors (App-wide)

    static let accent = Color("AccentColor")
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let cardBackground = Color(.secondarySystemBackground)
    static let destructive = Color.red

    // Gradient for the main CTA (used in app, NOT onboarding)
    static let flowGradient = LinearGradient(
        colors: [Color.blue, Color.purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Onboarding Colors

    static let onboardingBackground = Color(hex: "#F8F5FF")
    static let accentOrange = Color(hex: "#E8943A")
    static let ctaDark = Color(hex: "#1C1C1E")
    static let ctaSoft = Color(hex: "#E8DAFE")
    static let ctaSoftText = Color(hex: "#1C1C1E")
    static let settingsRowBg = Color(hex: "#F2F2F7")
    static let settingsBorder = Color(hex: "#D1D1D6")
    static let progressActive = Color(hex: "#1C1C1E")
    static let progressInactive = Color(hex: "#D1D1D6")
    static let successGreen = Color(hex: "#34C759")
    static let onboardingCardBg = Color.white
    static let onboardingPrimaryText = Color(hex: "#1C1C1E")
    static let onboardingSecondaryText = Color(hex: "#8E8E93")

    // MARK: - Typography (App-wide)

    static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 17, weight: .regular)
    static let caption = Font.system(size: 13, weight: .regular)
    static let buttonFont = Font.system(size: 18, weight: .semibold, design: .rounded)

    // MARK: - Onboarding Typography

    static let onboardingHeroHeading = Font.system(size: 36, weight: .bold, design: .serif)
    static let onboardingHeading = Font.system(size: 32, weight: .bold, design: .serif)
    static let onboardingBody = Font.system(size: 17, weight: .regular)
    static let onboardingSubhead = Font.system(size: 15, weight: .regular)
    static let onboardingCTAFont = Font.system(size: 17, weight: .semibold)
    static let onboardingSkipFont = Font.system(size: 15, weight: .regular)
    static let onboardingPrivacyFont = Font.system(size: 13, weight: .regular)

    // MARK: - Spacing

    static let paddingSmall: CGFloat = 8
    static let paddingMedium: CGFloat = 16
    static let paddingLarge: CGFloat = 24
    static let paddingXL: CGFloat = 32

    // MARK: - Corner Radius

    static let cornerRadius: CGFloat = 16
    static let cornerRadiusSmall: CGFloat = 10
    static let ctaCornerRadius: CGFloat = 14

    // MARK: - Shadows

    static let cardShadow = ShadowStyle.drop(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Reusable View Modifiers

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.paddingMedium)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}
