import AppKit
import SwiftUI

extension Color {
    static let bl00pPink = Color(red: 1.0, green: 105.0 / 255.0, blue: 180.0 / 255.0)
    static let bl00pMint = Color(red: 105.0 / 255.0, green: 1.0, blue: 180.0 / 255.0)
    static let bl00pPinkSoft = Color(red: 1.0, green: 0.93, blue: 0.97)
    static let bl00pInk = Color(red: 0.10, green: 0.08, blue: 0.10)
    static let bl00pMuted = Color(red: 0.43, green: 0.39, blue: 0.42)
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
    var size: CGFloat = 34

    private var initial: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.first.map { String($0).uppercased() }
            ?? provider.shortMark
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.bl00pMint)

            Text(initial)
                .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.bl00pInk)
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
        case .needsApproval, .needsAnswer: .bl00pPink
        case .completed: .green
        case .failed: .bl00pPink
        }
    }
}
