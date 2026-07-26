import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [BotProfile]
    @Published var sessions: [UUID: AgentSessionState]
    @Published var selectedBotID: UUID?
    @Published var isInspectorVisible = false
    @Published var isAddingBot = false

    private let runtime: any AgentRuntime
    private let worktrees: any GitWorktreeManaging
    private let store: AppStateStore
    private let isAppWindowActive: () -> Bool
    private var notifications: (any AgentNotificationDelivering)?
    private var runGenerations: [UUID: UUID] = [:]
    private var connectedProfileIDs: Set<UUID> = []
    private var notificationsArePrepared = false

    init(
        runtime: any AgentRuntime = AgentRuntimeRouter(),
        worktrees: any GitWorktreeManaging = GitWorktreeManager(),
        store: AppStateStore = AppStateStore(),
        notifications: (any AgentNotificationDelivering)? = nil,
        isAppWindowActive: @escaping () -> Bool = {
            AppWindowActivity.isActive
        }
    ) {
        self.runtime = runtime
        self.worktrees = worktrees
        self.store = store
        self.notifications = notifications
        self.isAppWindowActive = isAppWindowActive

        if let saved = store.load(), !saved.profiles.isEmpty {
            let restoredProfiles = saved.profiles.map(Self.migrateLegacyDefaultName)
            profiles = restoredProfiles
            let codexProfileIDs = Set(
                restoredProfiles
                    .filter { $0.provider == .codex }
                    .map(\.id)
            )
            sessions = Dictionary(
                uniqueKeysWithValues: saved.sessions.map { profileID, restoredSession in
                    var session = restoredSession
                    let endedAtLegacyPermissionBoundary =
                        session.entries.last?.text == "Claude stopped at a permission boundary"
                    session.entries = session.entries.map(Self.migrateLegacyPermissionEntry)
                    session.entries.removeAll(where: Self.isPrototypeStarterEntry)
                    if session.status == .launching
                        || session.status == .working
                        || session.status == .needsApproval
                        || session.status == .needsAnswer {
                        session.status = .stopped
                    }
                    if endedAtLegacyPermissionBoundary && session.status == .completed {
                        session.status = .needsAnswer
                    }
                    if codexProfileIDs.contains(profileID),
                       session.codexTurnModeVersion != CodexThreadConfiguration.turnModeVersion {
                        session.sessionID = nil
                        session.status = .stopped
                    }
                    return (profileID, session)
                }
            )
            selectedBotID = saved.selectedBotID ?? saved.profiles.first?.id
        } else {
            profiles = BotProfile.defaults
            sessions = Dictionary(
                uniqueKeysWithValues: BotProfile.defaults.map { ($0.id, AgentSessionState()) }
            )
            selectedBotID = BotProfile.defaults.first?.id
        }
    }

    var selectedProfile: BotProfile? {
        guard let selectedBotID else { return nil }
        return profiles.first { $0.id == selectedBotID }
    }

    func prepareNotifications() {
        guard !notificationsArePrepared else { return }
        notificationsArePrepared = true
        if notifications == nil {
            notifications = AppNotificationController.shared
        }
        notifications?.requestAuthorization()
        syncDockBadge()
    }

    func session(for profileID: UUID) -> AgentSessionState {
        sessions[profileID] ?? AgentSessionState()
    }

    func binding(for profileID: UUID) -> Binding<BotProfile> {
        Binding(
            get: { [weak self] in
                self?.profiles.first(where: { $0.id == profileID })
                    ?? BotProfile(
                        id: profileID,
                        name: "Bot",
                        provider: .codex,
                        role: .builder,
                        instructions: ""
                    )
            },
            set: { [weak self] updated in
                self?.update(updated)
            }
        )
    }

    func add(_ profile: BotProfile) {
        profiles.append(profile)
        sessions[profile.id] = AgentSessionState()
        selectedBotID = profile.id
        isAddingBot = false
        isInspectorVisible = true
        save()
    }

    func duplicate(_ profileID: UUID) {
        guard var copy = profiles.first(where: { $0.id == profileID }) else { return }
        copy.id = UUID()
        copy.name += " Copy"
        copy.worktree = nil
        add(copy)
    }

    func rename(_ profileID: UUID, to proposedName: String) {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].name = name
        save()
    }

    func delete(_ profileID: UUID) {
        guard profiles.count > 1 else { return }
        if let profile = profiles.first(where: { $0.id == profileID }) {
            Task {
                await runtime.stop(profile: runtimeProfile(for: profile))
            }
        }
        connectedProfileIDs.remove(profileID)
        runGenerations[profileID] = UUID()
        profiles.removeAll { $0.id == profileID }
        sessions[profileID] = nil
        if selectedBotID == profileID {
            selectedBotID = profiles.first?.id
        }
        save()
    }

    func update(_ profile: BotProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        if profiles[index].workingDirectory != profile.workingDirectory {
            updated.worktree = nil
        }
        profiles[index] = updated
        save()
    }

    func showSettings(for profileID: UUID) {
        selectedBotID = profileID
        isInspectorVisible = true
    }

    func chooseWorkingDirectory(for profileID: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Choose a working directory"
        panel.message = "bl00p will launch this bot in the selected folder."
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let path = panel.url?.path,
           let index = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[index].workingDirectory = path
            profiles[index].worktree = nil
            save()
        }
    }

    func launch(_ profileID: UUID) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
        let previousThreadID = sessions[profileID]?.sessionID
        let generation = UUID()
        runGenerations[profileID] = generation
        connectedProfileIDs.remove(profileID)
        if var resumedSession = sessions[profileID], previousThreadID != nil {
            resumedSession.status = .stopped
            resumedSession.hasUnreadCompletion = false
            sessions[profileID] = resumedSession
        } else {
            sessions[profileID] = AgentSessionState()
        }

        Task {
            await runtime.stop(profile: runtimeProfile(for: profile))
            guard let preparedProfile = await prepareRuntimeProfile(profile) else {
                return
            }
            let stream = await runtime.start(
                profile: preparedProfile,
                resumeThreadID: previousThreadID
            )
            consume(stream, for: profileID, generation: generation)
        }
    }

    func launchAll() {
        for profile in profiles {
            launch(profile.id)
        }
    }

    func stop(_ profileID: UUID) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
        connectedProfileIDs.remove(profileID)
        runGenerations[profileID] = UUID()
        Task {
            await runtime.stop(profile: runtimeProfile(for: profile))
        }
        apply(.status(.stopped), to: profileID)
        append(
            .init(kind: .system, text: "Session stopped by you."),
            to: profileID
        )
    }

    func send(
        _ text: String,
        attachments: [ImageAttachment] = [],
        to profileID: UUID
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty,
              let profile = profiles.first(where: { $0.id == profileID }) else { return }

        let currentState = sessions[profileID] ?? AgentSessionState()
        guard currentState.status != .launching, currentState.status != .working else { return }

        let shouldLaunch = !connectedProfileIDs.contains(profileID)
            || currentState.status == .stopped
            || currentState.status == .failed
        let previousThreadID = currentState.sessionID
        let pendingHandoff = currentState.pendingHandoff
        let generation = runGenerations[profileID] ?? UUID()
        runGenerations[profileID] = generation

        var updatedSession = currentState
        updatedSession.status = shouldLaunch ? .launching : .working
        if shouldLaunch {
            updatedSession.hasUnreadCompletion = false
        }
        sessions[profileID] = updatedSession
        append(
            .init(
                kind: .user,
                text: trimmed,
                attachments: attachments.isEmpty ? nil : attachments
            ),
            to: profileID
        )

        Task { [weak self] in
            guard let self else { return }
            guard let preparedProfile = await prepareRuntimeProfile(
                profile,
                handoff: pendingHandoff
            ) else {
                return
            }

            if shouldLaunch {
                await runtime.stop(profile: runtimeProfile(for: profile))
                let launchStream = await runtime.start(
                    profile: preparedProfile,
                    resumeThreadID: previousThreadID
                )
                var reachedReady = false
                for await event in launchStream {
                    guard runGenerations[profileID] == generation else { return }
                    if case .entry(let entry) = event, entry.kind == .question {
                        continue
                    }
                    if case .status(.needsAnswer) = event {
                        reachedReady = true
                        break
                    }
                    apply(event, to: profileID)
                    if case .status(.failed) = event {
                        break
                    }
                }
                guard reachedReady else { return }
                // The launch stream stays open as this session's lifecycle
                // channel; keep consuming it so a later idle disconnect is
                // still reported to the UI.
                consume(launchStream, for: profileID, generation: generation)
            }

            if pendingHandoff != nil {
                var handoffConsumed = sessions[profileID] ?? AgentSessionState()
                handoffConsumed.pendingHandoff = nil
                sessions[profileID] = handoffConsumed
                save()
            }
            let runtimeMessage = runtimeMessage(
                userMessage: trimmed,
                handoff: pendingHandoff
            )
            let responseStream = await runtime.respond(
                to: runtimeMessage,
                attachments: attachments,
                profile: preparedProfile
            )
            for await event in responseStream {
                guard runGenerations[profileID] == generation else { return }
                apply(event, to: profileID)
            }
        }
    }

    func resolveApproval(_ entryID: UUID, approved: Bool, for profileID: UUID) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }

        let generation = runGenerations[profileID] ?? UUID()
        runGenerations[profileID] = generation
        Task {
            let stream = await runtime.resolveApproval(
                entryID: entryID,
                approved: approved,
                profile: runtimeProfile(for: profile)
            )
            consume(stream, for: profileID, generation: generation)
        }
    }

    func markViewed(_ profileID: UUID) {
        guard var state = sessions[profileID] else { return }
        if state.status == .completed {
            state.hasUnreadCompletion = false
            sessions[profileID] = state
            save()
        }
    }

    func handoff(from sourceProfileID: UUID, to targetProfileID: UUID) {
        guard sourceProfileID != targetProfileID,
              let source = profiles.first(where: { $0.id == sourceProfileID }),
              let target = profiles.first(where: { $0.id == targetProfileID }),
              source.role == .builder,
              source.worktree != nil,
              sessions[sourceProfileID]?.status != .working,
              sessions[sourceProfileID]?.status != .launching else { return }

        let sourceSession = sessions[sourceProfileID] ?? AgentSessionState()
        Task { [weak self] in
            guard let self else { return }
            do {
                let package = try await worktrees.makeHandoff(
                    from: source,
                    session: sourceSession
                )
                await runtime.stop(profile: runtimeProfile(for: target))
                connectedProfileIDs.remove(targetProfileID)
                runGenerations[targetProfileID] = UUID()

                if let targetIndex = profiles.firstIndex(
                    where: { $0.id == targetProfileID }
                ) {
                    profiles[targetIndex].workingDirectory = package.repositoryPath
                    if profiles[targetIndex].role == .builder {
                        profiles[targetIndex].worktree = nil
                    }
                }

                var targetSession = sessions[targetProfileID] ?? AgentSessionState()
                targetSession.status = .stopped
                targetSession.sessionID = nil
                targetSession.pendingHandoff = package
                targetSession.entries.append(
                    .init(
                        kind: .handoff,
                        title: "Handoff from \(source.name)",
                        text: package.taskContext,
                        detail: handoffDetail(package)
                    )
                )
                sessions[targetProfileID] = targetSession

                var updatedSourceSession =
                    sessions[sourceProfileID] ?? AgentSessionState()
                updatedSourceSession.entries.append(
                    .init(
                        kind: .system,
                        text: "Handoff prepared for \(target.name)",
                        detail: "\(package.branch) · Tests \(package.testStatus.label.lowercased())"
                    )
                )
                sessions[sourceProfileID] = updatedSourceSession
                selectedBotID = targetProfileID
                save()
            } catch {
                append(
                    .init(
                        kind: .system,
                        text: "Could not create handoff",
                        detail: error.localizedDescription
                    ),
                    to: sourceProfileID
                )
            }
        }
    }

    private func consume(
        _ stream: AsyncStream<AgentEvent>,
        for profileID: UUID,
        generation: UUID
    ) {
        Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                guard self?.runGenerations[profileID] == generation else { break }
                self?.apply(event, to: profileID)
            }
        }
    }

    private func prepareRuntimeProfile(
        _ profile: BotProfile,
        handoff: GitHandoffPackage? = nil
    ) async -> BotProfile? {
        guard profile.role == .builder, !profile.workingDirectory.isEmpty else {
            return runtimeProfile(for: profile)
        }

        do {
            let ownership = try await worktrees.prepareWorktree(
                for: profile,
                startingPoint: handoff?.branch,
                handoffID: handoff?.id
            )
            var updated = profile
            updated.workingDirectory = ownership.repositoryPath
            updated.worktree = ownership
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = updated
                save()
            }
            return runtimeProfile(for: updated)
        } catch {
            apply(.status(.failed), to: profile.id)
            append(
                .init(
                    kind: .system,
                    text: "Could not prepare isolated worktree",
                    detail: error.localizedDescription
                ),
                to: profile.id
            )
            return nil
        }
    }

    private func runtimeProfile(for profile: BotProfile) -> BotProfile {
        var runtimeProfile = profile
        runtimeProfile.workingDirectory = profile.runtimeWorkingDirectory
        return runtimeProfile
    }

    private func runtimeMessage(
        userMessage: String,
        handoff: GitHandoffPackage?
    ) -> String {
        guard let handoff else { return userMessage }
        if userMessage.isEmpty {
            return handoff.agentContext
        }
        return "\(handoff.agentContext)\n\nNext instruction:\n\(userMessage)"
    }

    private func handoffDetail(_ package: GitHandoffPackage) -> String {
        """
        Branch: \(package.branch)
        HEAD: \(package.headRevision)
        Tests: \(package.testStatus.label)
        \(package.testSummary)
        Working tree:
        \(package.workingTreeSummary)
        """
    }

    private func apply(_ event: AgentEvent, to profileID: UUID) {
        var state = sessions[profileID] ?? AgentSessionState()
        var notice: AgentAttentionNotice?

        switch event {
        case .status(let status):
            notice = AgentAttentionNotice.transition(
                from: state.status,
                to: status
            )
            state.status = status
            if status == .failed || status == .stopped {
                connectedProfileIDs.remove(profileID)
            }
            if status == .completed {
                state.hasUnreadCompletion =
                    selectedBotID != profileID || !NSApplication.shared.isActive
            }
        case .entry(let entry):
            state.entries.append(entry)
        case .upsertEntry(let entry):
            if let index = state.entries.firstIndex(where: { $0.id == entry.id }) {
                state.entries[index] = entry
            } else {
                state.entries.append(entry)
            }
        case .approvalResolved(let entryID, let approvalState):
            if let index = state.entries.firstIndex(where: { $0.id == entryID }) {
                state.entries[index].approvalState = approvalState
            }
        case .sessionID(let sessionID):
            state.sessionID = sessionID
            if profiles.first(where: { $0.id == profileID })?.provider == .codex {
                state.codexTurnModeVersion = CodexThreadConfiguration.turnModeVersion
            }
            connectedProfileIDs.insert(profileID)
        }

        sessions[profileID] = state
        save()
        if notificationsArePrepared,
           let notice,
           let profile = profiles.first(where: { $0.id == profileID }),
           !isAppWindowActive() {
            notifications?.post(notice, for: profile)
        }
    }

    private func append(_ entry: TimelineEntry, to profileID: UUID) {
        var state = sessions[profileID] ?? AgentSessionState()
        state.entries.append(entry)
        sessions[profileID] = state
        save()
    }

    private func save() {
        store.save(
            PersistedAppState(
                profiles: profiles,
                sessions: sessions,
                selectedBotID: selectedBotID
            )
        )
        syncDockBadge()
    }

    private func syncDockBadge() {
        guard notificationsArePrepared else { return }
        let count = sessions.values.filter {
            $0.status.needsAttention || $0.hasUnreadCompletion
        }.count
        notifications?.setBadgeCount(count)
    }

    private static func migrateLegacyDefaultName(_ profile: BotProfile) -> BotProfile {
        let wasPrototypeDefault =
            (profile.provider == .claude
                && profile.role == .builder
                && profile.name == "Claude Builder")
            || (profile.provider == .codex
                && profile.role == .reviewer
                && profile.name == "Codex Reviewer")
            || (profile.provider == .claude
                && profile.role == .publisher
                && profile.name == "Claude PR Writer")

        guard wasPrototypeDefault else { return profile }
        var migrated = profile
        migrated.name = profile.provider.displayName
        return migrated
    }

    private static func isPrototypeStarterEntry(_ entry: TimelineEntry) -> Bool {
        if entry.kind == .question {
            return [
                "What should I build?",
                "What should I review?",
                "What should I prepare?"
            ].contains(entry.title)
        }

        guard entry.kind == .system else { return false }
        return [
            "Claude session launched",
            "Codex session launched",
            "Connected to Claude Code",
            "Ready to resume Claude Code",
            "Connected to Codex app-server",
            "Resumed Codex session",
            "Resumed Codex review session"
        ].contains(entry.text)
    }

    private static func migrateLegacyPermissionEntry(
        _ entry: TimelineEntry
    ) -> TimelineEntry {
        guard entry.text == "Claude stopped at a permission boundary" else {
            return entry
        }

        var migrated = entry
        migrated.kind = .question
        migrated.title = "Some actions were blocked"
        migrated.text = "Claude could not run every requested action. Review its response, then tell it how you want to proceed."
        migrated.detail = ClaudePermissionDenials.readableLegacyDetail(entry.detail)
        return migrated
    }
}

struct AppStateStore: Sendable {
    private let fileURL: URL?

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            return
        }

        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        self.fileURL = base?
            .appendingPathComponent("bl00p", isDirectory: true)
            .appendingPathComponent("state.json", isDirectory: false)
    }

    func load() -> PersistedAppState? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder.iso8601.decode(PersistedAppState.self, from: data)
    }

    func save(_ state: PersistedAppState) {
        guard let fileURL,
              let data = try? JSONEncoder.pretty.encode(state) else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence failure should not interrupt an active coding session.
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
