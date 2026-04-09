import SwiftUI

enum AppTheme {

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Surface Hierarchy
    // "No-Line Rule" — boundaries through color shifts, not borders
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let surface = Color(hex: "#FBF8FF")                    // Base canvas
    static let surfaceContainerLow = Color(hex: "#F5F2FC")        // Secondary groupings
    static let surfaceContainer = Color(hex: "#EFECF6")           // Mid-level containers
    static let surfaceContainerHigh = Color(hex: "#E9E7F1")       // Primary interactive cards
    static let surfaceContainerHighest = Color(hex: "#E4E1EB")    // Top-layer elements
    static let surfaceDim = Color(hex: "#DBD9E2")                 // Muted surfaces

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Brand Colors
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let accentOrange = Color(hex: "#FDA54A")               // Primary accent — vibrant orange
    static let secondaryBrown = Color(hex: "#8C5000")             // Active label color
    static let primaryGray = Color(hex: "#5F5E60")                // Gradient start
    static let tertiaryPurple = Color(hex: "#645978")             // Gradient end

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - CTA Colors
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let ctaDark = Color(hex: "#1B1B1D")                    // Primary dark CTA (obsidian)
    static let ctaSoft = Color(hex: "#EADDFF")                    // Soft lavender CTA
    static let ctaSoftText = Color(hex: "#1B1B1D")                // Text on soft CTA

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Text Colors
    // Never use pure #000000
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let onSurface = Color(hex: "#1B1B22")                  // Primary text
    static let onSurfaceVariant = Color(hex: "#8E8E93")           // Secondary text
    static let outlineVariant = Color(hex: "#D9C3B1")             // Ghost borders (15% opacity)

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Utility Colors
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let successGreen = Color(hex: "#34C759")
    static let error = Color(hex: "#BA1A1A")
    static let chipSelected = Color(hex: "#FDA54A")
    static let chipSelectedText = Color(hex: "#6E3D00")

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Legacy App Colors (main app screens)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let accent = Color("AccentColor")
    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.secondarySystemBackground)
    static let cardBackground = Color(.secondarySystemBackground)
    static let destructive = Color.red

    static let flowGradient = LinearGradient(
        colors: [Color.blue, Color.purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Brand gradient (from design system)
    static let brandGradient = LinearGradient(
        colors: [primaryGray, tertiaryPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Onboarding Aliases
    // Maps old names to new design system for compatibility
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let onboardingBackground = surface
    static let onboardingPrimaryText = onSurface
    static let onboardingSecondaryText = onSurfaceVariant
    static let onboardingCardBg = Color.white
    static let settingsRowBg = Color(hex: "#F2F2F7")
    static let settingsBorder = outlineVariant
    static let progressActive = ctaDark
    static let progressInactive = surfaceDim

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Typography
    // Serif-to-Rounded tension: editorial serif + approachable sans
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    // App-wide
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 17, weight: .regular)
    static let caption = Font.system(size: 13, weight: .regular)
    static let buttonFont = Font.system(size: 18, weight: .semibold, design: .rounded)

    // Onboarding — editorial serif headings
    static let onboardingHeroHeading = Font.system(size: 40, weight: .bold, design: .serif)
    static let onboardingHeading = Font.system(size: 32, weight: .bold, design: .serif)
    static let onboardingBody = Font.system(size: 16, weight: .regular)
    static let onboardingSubhead = Font.system(size: 15, weight: .regular)
    static let onboardingCTAFont = Font.system(size: 14, weight: .semibold)
    static let onboardingSkipFont = Font.system(size: 15, weight: .regular)
    static let onboardingPrivacyFont = Font.system(size: 13, weight: .regular)

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Spacing
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let paddingSmall: CGFloat = 8
    static let paddingMedium: CGFloat = 16
    static let paddingLarge: CGFloat = 24
    static let paddingXL: CGFloat = 32
    static let paddingXXL: CGFloat = 48

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Corner Radius
    // Minimum 24px on interactive elements (design system rule)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let cornerRadius: CGFloat = 24
    static let cornerRadiusSmall: CGFloat = 16
    static let ctaCornerRadius: CGFloat = 9999 // full / pill

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Shadows
    // Tinted from on-surface, never pure black
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    static let cardShadow = ShadowStyle.drop(color: Color(hex: "#1B1B22").opacity(0.06), radius: 16, x: 0, y: 6)
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

// MARK: - Glassmorphism Modifier

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: Color(hex: "#1B1B22").opacity(0.06), radius: 16, x: 0, y: 6)
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppTheme.paddingMedium)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: Color(hex: "#1B1B22").opacity(0.06), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }

    func glassStyle() -> some View {
        modifier(GlassCard())
    }
}
