#if os(macOS)
import SwiftUI
#else
import SwiftOpenUI
#endif

#if os(macOS)
typealias Bl00pFontWeight = Font.Weight
typealias Bl00pFontDesign = Font.Design
#else
typealias Bl00pFontWeight = FontWeight
typealias Bl00pFontDesign = FontDesign
#endif

/// The text styles bl00p paints with, sized from the macOS system defaults so
/// the Linux build keeps the upstream typographic rhythm. AppKit's
/// `NSFont.preferredFont(forTextStyle:)` is unavailable here, so the point
/// sizes are stated directly.
enum Bl00pTextStyle {
    case caption2
    case caption1
    case callout
    case body
    case headline
    case title3
    case title2

    var pointSize: Double {
        switch self {
        case .caption2: 10
        case .caption1: 10
        case .callout: 12
        case .body: 13
        case .headline: 13
        case .title3: 15
        case .title2: 17
        }
    }
}

enum Bl00pTheme {
    static let hotPink = Color(
        red: 1.00,
        green: 105.0 / 255.0,
        blue: 180.0 / 255.0
    )
    static let accent = hotPink
    static let userBubble = hotPink
    static let userBubbleText = Color.white
    static let accentText = adaptive(
        light: Color(red: 0.69, green: 0.00, blue: 0.35),
        dark: Color(red: 1.00, green: 0.48, blue: 0.74)
    )
    static let mint = adaptive(
        light: Color(red: 0.41, green: 1.00, blue: 0.71),
        dark: Color(red: 0.32, green: 0.88, blue: 0.63)
    )
    static let avatarInk = Color(red: 0.10, green: 0.08, blue: 0.10)
    static let approvalBackground = adaptive(
        light: Color(red: 1.00, green: 0.94, blue: 0.97),
        dark: Color(red: 0.20, green: 0.11, blue: 0.16)
    )
    static let sidebarLightTop = Color(red: 0.99, green: 0.98, blue: 0.99)
    static let sidebarLightBottom = Color(red: 1.00, green: 0.94, blue: 0.97)
    static let sidebarDarkTop = Color(red: 0.12, green: 0.11, blue: 0.12)
    static let sidebarDarkBottom = Color(red: 0.18, green: 0.12, blue: 0.16)

    /// Stands in for AppKit's `labelColor`, which has no Linux counterpart.
    static let ink = adaptive(
        light: Color(red: 0.15, green: 0.15, blue: 0.15),
        dark: Color(red: 0.92, green: 0.92, blue: 0.92)
    )
    /// Stands in for AppKit's `secondaryLabelColor`.
    static let muted = adaptive(
        light: Color(red: 0.45, green: 0.45, blue: 0.47),
        dark: Color(red: 0.63, green: 0.63, blue: 0.65)
    )
    /// Flat replacement for `.quaternary.opacity(0.45)`; SwiftOpenUI's
    /// hierarchical styles do not support opacity adjustment.
    static let chipBackground = adaptive(
        light: Color(red: 0.92, green: 0.92, blue: 0.94).opacity(0.45),
        dark: Color(red: 0.30, green: 0.30, blue: 0.32).opacity(0.45)
    )

    static func sidebarColors(for colorScheme: ColorScheme) -> [Color] {
        colorScheme == .dark
            ? [sidebarDarkTop, sidebarDarkBottom]
            : [sidebarLightTop, sidebarLightBottom]
    }

    static func sidebarTop(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? sidebarDarkTop : sidebarLightTop
    }

    static func avatarBackground(for role: AgentRole) -> Color {
        role == .manager ? hotPink : mint
    }

    private static func adaptive(light: Color, dark: Color) -> Color {
        Bl00pAppearance.current == .dark ? dark : light
    }
}

extension Color {
    static let bl00pPink = Bl00pTheme.accent
    static let bl00pPinkText = Bl00pTheme.accentText
    static let bl00pUserBubble = Bl00pTheme.userBubble
    static let bl00pUserBubbleText = Bl00pTheme.userBubbleText
    static let bl00pMint = Bl00pTheme.mint
    static let bl00pAvatarInk = Bl00pTheme.avatarInk
    static let bl00pPinkSoft = Bl00pTheme.approvalBackground
    static let bl00pInk = Bl00pTheme.ink
    static let bl00pMuted = Bl00pTheme.muted

    #if os(macOS)
    /// Preserves the exact AppKit dynamic system colors on macOS.
    static let bl00pControlBackground = Color(nsColor: .controlBackgroundColor)
    static let bl00pWindowBackground = Color(nsColor: .windowBackgroundColor)
    static let bl00pTextBackground = Color(nsColor: .textBackgroundColor)
    #else
    /// GTK4 has no direct equivalent to AppKit's semantic control colors, so
    /// these approximate them from the same light/dark palette bl00p already
    /// paints its own surfaces with.
    static let bl00pControlBackground = Bl00pAppearance.current == .dark
        ? Color(red: 0.16, green: 0.16, blue: 0.17)
        : Color(red: 0.95, green: 0.95, blue: 0.96)
    static let bl00pWindowBackground = Bl00pAppearance.current == .dark
        ? Color(red: 0.11, green: 0.11, blue: 0.12)
        : Color.white
    static let bl00pTextBackground = bl00pWindowBackground
    #endif
}

extension Font {
    static func bl00p(
        _ textStyle: Bl00pTextStyle,
        weight: Bl00pFontWeight = .regular,
        design: Bl00pFontDesign = .default,
        sizeOffset: Double = 0
    ) -> Font {
        .system(
            size: textStyle.pointSize + 2 + sizeOffset,
            weight: weight,
            design: design
        )
    }
}

struct BotAvatar: View {
    let name: String
    let provider: AgentProvider
    let role: AgentRole
    var size: Double = 34

    private var initial: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.first.map { String($0).uppercased() }
            ?? provider.shortMark
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(Bl00pTheme.avatarBackground(for: role))

            Text(initial)
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.bl00pAvatarInk)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(name)
    }
}

struct StatusPill: View {
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)

            Text(status.label)
                .font(.bl00p(.caption1, weight: .semibold))
        }
        .foregroundStyle(Color.bl00pMuted)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Bl00pTheme.chipBackground, in: Capsule())
    }
}

extension AgentStatus {
    var color: Color {
        switch self {
        case .stopped: .secondary
        case .launching: .orange
        case .working: .blue
        case .needsApproval, .needsAnswer: .bl00pPinkText
        case .completed: .green
        case .failed: .bl00pPinkText
        }
    }
}
