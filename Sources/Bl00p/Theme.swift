import AppKit
import SwiftUI

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

extension Color {
    static let bl00pPink = Color(nsColor: Bl00pTheme.accent)
    static let bl00pPinkText = Color(nsColor: Bl00pTheme.accentText)
    static let bl00pUserBubble = Color(nsColor: Bl00pTheme.userBubble)
    static let bl00pUserBubbleText = Color(nsColor: Bl00pTheme.userBubbleText)
    static let bl00pMint = Color(nsColor: Bl00pTheme.mint)
    static let bl00pAvatarInk = Color(nsColor: Bl00pTheme.avatarInk)
    static let bl00pPinkSoft = Color(nsColor: Bl00pTheme.approvalBackground)
    static let bl00pInk = Color(nsColor: .labelColor)
    static let bl00pMuted = Color(nsColor: .secondaryLabelColor)
}

extension Font {
    static func bl00p(
        _ textStyle: NSFont.TextStyle,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        sizeOffset: CGFloat = 0
    ) -> Font {
        let pointSize = NSFont.preferredFont(forTextStyle: textStyle).pointSize + 2 + sizeOffset
        return .system(size: pointSize, weight: weight, design: design)
    }
}

struct BotAvatar: View {
    let name: String
    let provider: AgentProvider
    let role: AgentRole
    var size: CGFloat = 34

    private var initial: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.first.map { String($0).uppercased() }
            ?? provider.shortMark
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color(nsColor: Bl00pTheme.avatarBackground(for: role)))

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
        .background(.quaternary.opacity(0.45), in: Capsule())
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
