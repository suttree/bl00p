import Foundation

#if os(macOS)
import AppKit
import UserNotifications
#endif

enum AppWindowActivity {
    #if os(macOS)
    @MainActor
    static var isActive: Bool {
        NSApplication.shared.isActive && NSApplication.shared.keyWindow != nil
    }
    #else
    /// The GTK4 backend does not surface window focus, so bl00p cannot tell
    /// whether its window is frontmost. Reporting `false` means attention
    /// notices are always delivered to the desktop: a redundant notification
    /// is a smaller failure than a silently dropped one.
    static var isActive: Bool { false }
    #endif
}

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

    #if !os(macOS)
    /// Maps to freedesktop notification urgency levels.
    var urgency: String {
        switch self {
        case .needsAnswer, .needsApproval, .failed: "critical"
        case .completed: "normal"
        }
    }
    #endif
}

#if os(macOS)
@MainActor
#endif
protocol AgentNotificationDelivering {
    func requestAuthorization()
    func post(_ notice: AgentAttentionNotice, for profile: BotProfile)
    func setBadgeCount(_ count: Int)
}

#if os(macOS)

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
        // A notification queued while bl00p was in the background can arrive
        // just after its window becomes active.
        completionHandler([])
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

#else

/// Delivers attention notices through the freedesktop notification daemon.
///
/// `notify-send` is used rather than a direct D-Bus binding so bl00p keeps its
/// dependency surface to the GTK4 stack it already links. It ships in
/// `libnotify-bin`, which is present on a default Kali install.
final class AppNotificationController: AgentNotificationDelivering, @unchecked Sendable {
    static let shared = AppNotificationController()

    /// Replacing a bot's previous notice keeps one queued item per bot instead
    /// of stacking every status change in the notification tray.
    private var replacementIDs: [UUID: String] = [:]
    private let queue = DispatchQueue(label: "bl00p.notifications")

    private init() {}

    func requestAuthorization() {
        // The freedesktop notification spec has no authorization step.
    }

    func post(_ notice: AgentAttentionNotice, for profile: BotProfile) {
        let content = notice.content(for: profile)
        let replacementID = replacementIDs[profile.id] ?? profile.id.uuidString
        replacementIDs[profile.id] = replacementID

        var arguments = [
            "notify-send",
            "--app-name=bl00p",
            "--urgency=\(notice.urgency)",
            "--icon=bl00p",
            "--hint=string:desktop-entry:bl00p",
            content.title,
            content.body
        ]

        // `--replace-id` needs a numeric handle; derive a stable one per bot.
        arguments.insert(
            "--replace-id=\(abs(replacementID.hashValue % 100_000) + 1)",
            at: 3
        )
        let processArguments = arguments

        queue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = processArguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // A missing notification daemon must never take down a session.
            }
        }
    }

    func setBadgeCount(_ count: Int) {
        // No portable launcher badge exists across the Kali desktops. The
        // sidebar attention badges remain the in-app signal.
    }
}

#endif
