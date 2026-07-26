import AppKit
import Foundation
import UserNotifications

enum AgentAttentionNotice: Equatable, Sendable {
    case needsAnswer
    case needsApproval
    case failed
    case completed

    static func transition(
        from previousStatus: AgentStatus,
        to status: AgentStatus
    ) -> AgentAttentionNotice? {
        guard previousStatus != status else { return nil }

        switch status {
        case .needsAnswer:
            return .needsAnswer
        case .needsApproval:
            return .needsApproval
        case .failed:
            return .failed
        case .completed:
            return .completed
        case .stopped, .launching, .working:
            return nil
        }
    }

    func content(for profile: BotProfile) -> (title: String, body: String) {
        switch self {
        case .needsAnswer:
            return (
                "\(profile.name) has a question",
                "Open bl00p to respond."
            )
        case .needsApproval:
            return (
                "\(profile.name) needs approval",
                "Review the requested action in bl00p."
            )
        case .failed:
            return (
                "\(profile.name) needs attention",
                "The session stopped with an error."
            )
        case .completed:
            return (
                "\(profile.name) finished",
                "The task is ready for your review."
            )
        }
    }
}

@MainActor
protocol AgentNotificationDelivering {
    func requestAuthorization()
    func post(_ notice: AgentAttentionNotice, for profile: BotProfile)
    func setBadgeCount(_ count: Int)
}

final class AppNotificationController:
    NSObject,
    AgentNotificationDelivering,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    static let shared = AppNotificationController()

    private let center: UNUserNotificationCenter

    private override init() {
        center = .current()
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func post(_ notice: AgentAttentionNotice, for profile: BotProfile) {
        let copy = UNMutableNotificationContent()
        let content = notice.content(for: profile)
        copy.title = content.title
        copy.body = content.body
        copy.sound = .default
        copy.userInfo = ["profileID": profile.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "\(profile.id.uuidString)-\(UUID().uuidString)",
            content: copy,
            trigger: nil
        )
        center.add(request)
    }

    func setBadgeCount(_ count: Int) {
        DispatchQueue.main.async {
            NSApplication.shared.dockTile.badgeLabel =
                count > 0 ? String(count) : nil
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        completionHandler()
    }
}
