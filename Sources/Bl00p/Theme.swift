import Foundation

#if os(macOS)
import AppKit
import SwiftUI

typealias Bl00pTextStyle = NSFont.TextStyle
typealias Bl00pFontWeight = Font.Weight
typealias Bl00pFontDesign = Font.Design
typealias Bl00pDimension = CGFloat
#else
import SwiftOpenUI

typealias Bl00pFontWeight = FontWeight
typealias Bl00pFontDesign = FontDesign
typealias Bl00pDimension = Double

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
#endif

#if os(macOS)
enum Bl00pTheme {
    static let hotPink = NSColor(
        srgbRed: 1.00,
        green: 105.0 / 255.0,
        blue: 180.0 / 255.0,
        alpha: 1
    )
    static let accent = hotPink
    static let userBubble = hotPink
    static let userBubbleText = NSColor.white
    static let accentText = adaptive(
        light: NSColor(srgbRed: 0.69, green: 0.00, blue: 0.35, alpha: 1),
        dark: NSColor(srgbRed: 1.00, green: 0.48, blue: 0.74, alpha: 1)
    )
    static let mint = adaptive(
        light: NSColor(srgbRed: 0.41, green: 1.00, blue: 0.71, alpha: 1),
        dark: NSColor(srgbRed: 0.32, green: 0.88, blue: 0.63, alpha: 1)
    )
    static let avatarInk = NSColor(
        srgbRed: 0.10,
        green: 0.08,
        blue: 0.10,
        alpha: 1
    )
    static let approvalBackground = adaptive(
        light: NSColor(srgbRed: 1.00, green: 0.94, blue: 0.97, alpha: 1),
        dark: NSColor(srgbRed: 0.20, green: 0.11, blue: 0.16, alpha: 1)
    )
    static let sidebarLightTop = NSColor(
        srgbRed: 0.99,
        green: 0.98,
        blue: 0.99,
        alpha: 1
    )
    static let sidebarLightBottom = NSColor(
        srgbRed: 1.00,
        green: 0.94,
        blue: 0.97,
        alpha: 1
    )
    static let sidebarDarkTop = NSColor(
        srgbRed: 0.12,
        green: 0.11,
        blue: 0.12,
        alpha: 1
    )
    static let sidebarDarkBottom = NSColor(
        srgbRed: 0.18,
        green: 0.12,
        blue: 0.16,
        alpha: 1
    )

    static func sidebarColors(for colorScheme: ColorScheme) -> [NSColor] {
        colorScheme == .dark
            ? [sidebarDarkTop, sidebarDarkBottom]
            : [sidebarLightTop, sidebarLightBottom]
    }

    static func sidebarTop(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? sidebarDarkTop : sidebarLightTop
    }

    static func avatarBackground(for role: AgentRole) -> NSColor {
        role == .manager ? hotPink : mint
    }

    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark
                : light
        }
    }
}
#else
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
    static let ink = adaptive(
        light: Color(red: 0.15, green: 0.15, blue: 0.15),
        dark: Color(red: 0.92, green: 0.92, blue: 0.92)
    )
    static let muted = adaptive(
        light: Color(red: 0.45, green: 0.45, blue: 0.47),
        dark: Color(red: 0.63, green: 0.63, blue: 0.65)
    )
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
#endif

extension Color {
    #if os(macOS)
    static let bl00pPink = Color(nsColor: Bl00pTheme.accent)
    static let bl00pPinkText = Color(nsColor: Bl00pTheme.accentText)
    static let bl00pUserBubble = Color(nsColor: Bl00pTheme.userBubble)
    static let bl00pUserBubbleText = Color(nsColor: Bl00pTheme.userBubbleText)
    static let bl00pMint = Color(nsColor: Bl00pTheme.mint)
    static let bl00pAvatarInk = Color(nsColor: Bl00pTheme.avatarInk)
    static let bl00pPinkSoft = Color(nsColor: Bl00pTheme.approvalBackground)
    static let bl00pInk = Color(nsColor: .labelColor)
    static let bl00pMuted = Color(nsColor: .secondaryLabelColor)
    static let bl00pControlBackground = Color(nsColor: .controlBackgroundColor)
    static let bl00pWindowBackground = Color(nsColor: .windowBackgroundColor)
    static let bl00pTextBackground = Color(nsColor: .textBackgroundColor)
    #else
    static let bl00pPink = Bl00pTheme.accent
    static let bl00pPinkText = Bl00pTheme.accentText
    static let bl00pUserBubble = Bl00pTheme.userBubble
    static let bl00pUserBubbleText = Bl00pTheme.userBubbleText
    static let bl00pMint = Bl00pTheme.mint
    static let bl00pAvatarInk = Bl00pTheme.avatarInk
    static let bl00pPinkSoft = Bl00pTheme.approvalBackground
    static let bl00pInk = Bl00pTheme.ink
    static let bl00pMuted = Bl00pTheme.muted
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
        sizeOffset: Bl00pDimension = 0
    ) -> Font {
        #if os(macOS)
        let pointSize =
            NSFont.preferredFont(forTextStyle: textStyle).pointSize
                + 2
                + sizeOffset
        return .system(size: pointSize, weight: weight, design: design)
        #else
        return .system(
            size: textStyle.pointSize + 2 + sizeOffset,
            weight: weight,
            design: design
        )
        #endif
    }
}

struct BotAvatar: View {
    let name: String
    let provider: AgentProvider
    let role: AgentRole
    var size: Bl00pDimension = 34

    private var initial: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.first.map { String($0).uppercased() }
            ?? provider.shortMark
    }

    var body: some View {
        ZStack {
            #if os(macOS)
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color(nsColor: Bl00pTheme.avatarBackground(for: role)))
            #else
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(Bl00pTheme.avatarBackground(for: role))
            #endif

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
        #if os(macOS)
        .background(.quaternary.opacity(0.45), in: Capsule())
        #else
        .background(Bl00pTheme.chipBackground, in: Capsule())
        #endif
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
