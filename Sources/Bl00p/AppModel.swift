import AppKit
import Foundation
import SwiftUI

private struct BuilderImplementationHandoff: Sendable {
    let approvalEntryID: UUID
    let originalRequest: String
    let approvedPlan: String

    func visibleEntry(sourceName: String) -> TimelineEntry {
        TimelineEntry(
            kind: .handoff,
            title: "Implementation brief",
            text: approvedPlan,
            detail: """
            Original request:
            \(originalRequest)

            From \(sourceName)
            """
        )
    }

    var runtimeMessage: String {
        """
        You are the Builder in a managed bl00p workflow.

        Original request:
        <original_request>
        \(originalRequest)
        </original_request>

        Approved implementation plan:
        <approved_implementation_plan>
        \(approvedPlan)
        </approved_implementation_plan>

        Implement the approved plan in your isolated worktree. Keep the change focused, run the relevant tests, and create a local commit before finishing so the Reviewer can inspect an immutable HEAD. Do not push or open a pull request.
        """
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [BotProfile]
    @Published var sessions: [UUID: AgentSessionState]
    @Published var managerWorkflows: [UUID: ManagerWorkflow]
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
    private var inFlightUserEntryIDs: [UUID: UUID] = [:]
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
            let pendingPlanApprovalManagerIDs = Set(
                saved.managerWorkflows.compactMap { managerID, workflow in
                    workflow.stage == .planning
                        && workflow.planApprovalEntryID != nil
                        ? managerID
                        : nil
                }
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
                        session.status =
                            session.status == .needsApproval
                                && pendingPlanApprovalManagerIDs.contains(profileID)
                                ? .needsApproval
                                : .stopped
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
            managerWorkflows = saved.managerWorkflows.mapValues { workflow in
                guard workflow.stage != .completed else { return workflow }
                var restored = workflow
                restored.isPaused = true
                restored.pauseReason =
                    workflow.planApprovalEntryID == nil
                        ? "Ready to resume after the app restart."
                        : "Waiting for your approval of the implementation plan."
                return restored
            }
            selectedBotID = saved.selectedBotID ?? saved.profiles.first?.id
        } else {
            profiles = BotProfile.defaults
            sessions = Dictionary(
                uniqueKeysWithValues: BotProfile.defaults.map { ($0.id, AgentSessionState()) }
            )
            managerWorkflows = [:]
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

    func workflow(for managerProfileID: UUID) -> ManagerWorkflow? {
        managerWorkflows[managerProfileID]
    }

    func isManagerTeamReady(_ managerProfileID: UUID) -> Bool {
        guard let manager = profiles.first(
            where: { $0.id == managerProfileID && $0.role == .manager }
        ) else { return false }
        return validatedTeam(for: manager) != nil
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
        copy.managerTeam = nil
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
        inFlightUserEntryIDs.removeValue(forKey: profileID)
        runGenerations[profileID] = UUID()
        for index in profiles.indices where profiles[index].id != profileID {
            guard var team = profiles[index].managerTeam else { continue }
            if team.builderProfileID == profileID {
                team.builderProfileID = nil
            }
            if team.reviewerProfileID == profileID {
                team.reviewerProfileID = nil
            }
            if team.publisherProfileID == profileID {
                team.publisherProfileID = nil
            }
            profiles[index].managerTeam = team
        }
        profiles.removeAll { $0.id == profileID }
        sessions[profileID] = nil
        managerWorkflows[profileID] = nil
        for managerID in Array(managerWorkflows.keys) {
            guard var workflow = managerWorkflows[managerID],
                  workflow.stage != .completed,
                  [
                    workflow.team.builderProfileID,
                    workflow.team.reviewerProfileID,
                    workflow.team.publisherProfileID
                  ].contains(profileID) else { continue }
            workflow.isPaused = true
            workflow.pauseReason = "A bot assigned to this workflow was deleted."
            workflow.updatedAt = .now
            managerWorkflows[managerID] = workflow
        }
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
        inFlightUserEntryIDs.removeValue(forKey: profileID)
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
              let profile = profiles.first(where: { $0.id == profileID }) else {
            return
        }
        let state = sessions[profileID] ?? AgentSessionState()
        guard state.status != .launching, state.status != .working else {
            return
        }
        guard managerWorkflows[profileID]?.planApprovalEntryID == nil else {
            return
        }

        let startedWorkflow = startWorkflowIfNeeded(
            request: trimmed,
            manager: profile
        )
        performSend(
            trimmed,
            attachments: attachments,
            to: profileID,
            visibleEntry: .init(
                kind: .user,
                text: trimmed,
                attachments: attachments.isEmpty ? nil : attachments
            )
        )
        if startedWorkflow {
            append(
                .init(
                    kind: .system,
                    text: "Managed workflow started",
                    detail: "Planning → Your approval → Building → Review → Fixes → Re-check → Documentation & draft PR"
                ),
                to: profileID
            )
        }
    }

    func retry(_ entryID: UUID, for profileID: UUID) {
        let state = sessions[profileID] ?? AgentSessionState()
        guard state.status.allowsFailedMessageRetry,
              let entry = state.entries.first(where: { $0.id == entryID }),
              entry.kind == .user,
              entry.deliveryFailed == true else {
            return
        }

        performSend(
            entry.text,
            attachments: entry.attachments ?? [],
            to: profileID,
            retryingEntryID: entryID
        )
    }

    private func performSend(
        _ text: String,
        attachments: [ImageAttachment] = [],
        to profileID: UUID,
        visibleEntry: TimelineEntry? = nil,
        retryingEntryID: UUID? = nil
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
        if let visibleEntry {
            updatedSession.entries.append(visibleEntry)
        }
        let inFlightEntryID = visibleEntry?.id ?? retryingEntryID
        if let inFlightEntryID {
            if let index = updatedSession.entries.firstIndex(
                where: { $0.id == inFlightEntryID }
            ) {
                updatedSession.entries[index].deliveryFailed = nil
            }
            inFlightUserEntryIDs[profileID] = inFlightEntryID
        }
        sessions[profileID] = updatedSession
        save()

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
                userMessage: workflowRuntimeMessage(
                    for: profile,
                    userMessage: trimmed
                ),
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
        if managerWorkflows[profileID]?.stage == .planning,
           managerWorkflows[profileID]?.planApprovalEntryID == entryID {
            resolveWorkflowPlanApproval(
                entryID,
                approved: approved,
                for: profileID
            )
            return
        }

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

    private func resolveWorkflowPlanApproval(
        _ entryID: UUID,
        approved: Bool,
        for managerID: UUID
    ) {
        guard var workflow = managerWorkflows[managerID],
              workflow.stage == .planning,
              workflow.planApprovalEntryID == entryID,
              var state = sessions[managerID],
              let entryIndex = state.entries.firstIndex(where: {
                  $0.id == entryID
                      && $0.kind == .approval
                      && $0.approvalState == .pending
              }) else {
            return
        }

        state.entries[entryIndex].approvalState =
            approved ? .approved : .declined
        workflow.planApprovalEntryID = nil
        workflow.updatedAt = .now

        if approved {
            let approvedEntry = state.entries[entryIndex]
            guard let proposedPlan = workflow.implementationPlan,
                  !approvedEntry.text.trimmingCharacters(
                      in: .whitespacesAndNewlines
                  ).isEmpty,
                  proposedPlan == approvedEntry.text else {
                state.status = .needsAnswer
                workflow.approvedPlanEntryID = nil
                sessions[managerID] = state
                managerWorkflows[managerID] = workflow
                save()
                pauseWorkflow(
                    managerID,
                    reason: "The approved implementation plan is missing or inconsistent. Send feedback to the Manager to request a new plan."
                )
                return
            }

            guard let builderID = workflow.team.builderProfileID else {
                state.status = .needsAnswer
                sessions[managerID] = state
                managerWorkflows[managerID] = workflow
                save()
                pauseWorkflow(
                    managerID,
                    reason: "The assigned Builder is no longer available."
                )
                return
            }

            let handoff = BuilderImplementationHandoff(
                approvalEntryID: entryID,
                originalRequest: workflow.request,
                approvedPlan: approvedEntry.text
            )
            state.status = .completed
            workflow.implementationPlan = approvedEntry.text
            workflow.approvedPlanEntryID = entryID
            workflow.stage = .building
            workflow.isPaused = false
            workflow.pauseReason = nil
            sessions[managerID] = state
            managerWorkflows[managerID] = workflow
            save()

            Task { [weak self] in
                await self?.dispatchInitialBuild(
                    workflow: workflow,
                    handoff: handoff,
                    to: builderID
                )
            }
        } else {
            state.status = .needsAnswer
            workflow.approvedPlanEntryID = nil
            workflow.isPaused = true
            workflow.pauseReason =
                "Plan declined. Send feedback to the Manager to request a revised plan."
            sessions[managerID] = state
            managerWorkflows[managerID] = workflow
            save()
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
                    profiles[targetIndex].workingDirectory =
                        profiles[targetIndex].role == .builder
                            ? package.repositoryPath
                            : package.worktreePath
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
                    ?? sessions[profile.id]?.worktreeSeedID
            )
            var updated = profile
            updated.workingDirectory = ownership.repositoryPath
            updated.worktree = ownership
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = updated
            }
            if var session = sessions[profile.id] {
                session.worktreeSeedID = nil
                sessions[profile.id] = session
            }
            save()
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

    private func workflowRuntimeMessage(
        for profile: BotProfile,
        userMessage: String
    ) -> String {
        guard profile.role == .manager,
              let workflow = managerWorkflows[profile.id],
              workflow.stage == .planning,
              workflow.planApprovalEntryID == nil else {
            return userMessage
        }

        return """
        You are in the planning phase of a managed bl00p workflow.

        Original request:
        \(workflow.request)

        Current user instruction or revision feedback:
        \(userMessage)

        Produce only a focused implementation plan with acceptance criteria and verification expectations. You may inspect the repository read-only for context. Do not edit files, run mutating commands, implement the plan, review code, commit, push, publish, or spawn or delegate to other agents. Finish after presenting the plan. bl00p will ask the user to approve it and will dispatch the approved plan to the configured visible Builder and Reviewer.
        """
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

    private func validatedTeam(
        for manager: BotProfile
    ) -> ManagerTeamConfiguration? {
        guard manager.role == .manager,
              let team = manager.managerTeam,
              team.isComplete,
              let builderID = team.builderProfileID,
              let reviewerID = team.reviewerProfileID,
              let publisherID = team.publisherProfileID,
              Set([builderID, reviewerID, publisherID]).count == 3,
              profiles.contains(where: {
                  $0.id == builderID && $0.role == .builder
              }),
              profiles.contains(where: {
                  $0.id == reviewerID && $0.role == .reviewer
              }),
              profiles.contains(where: {
                  $0.id == publisherID && $0.role == .publisher
              }) else {
            return nil
        }
        return team
    }

    private func startWorkflowIfNeeded(
        request: String,
        manager: BotProfile
    ) -> Bool {
        guard let team = validatedTeam(for: manager),
              managerWorkflows[manager.id]?.stage == .completed
                || managerWorkflows[manager.id] == nil else {
            return false
        }

        managerWorkflows[manager.id] = ManagerWorkflow(
            managerProfileID: manager.id,
            team: team,
            request: request.isEmpty
                ? "Work from the attached context."
                : request
        )
        save()
        return true
    }

    private func expectedProfileID(
        for workflow: ManagerWorkflow
    ) -> UUID? {
        switch workflow.stage {
        case .planning, .reporting:
            workflow.managerProfileID
        case .building, .revising:
            workflow.team.builderProfileID
        case .reviewing, .verifying:
            workflow.team.reviewerProfileID
        case .publishing:
            workflow.team.publisherProfileID
        case .completed:
            nil
        }
    }

    private func handleWorkflowStatus(
        for profileID: UUID,
        from previousStatus: AgentStatus,
        to status: AgentStatus
    ) {
        guard previousStatus != status else { return }
        let matchingManagerIDs = managerWorkflows.compactMap { managerID, workflow in
            workflow.stage != .completed
                && expectedProfileID(for: workflow) == profileID
                ? managerID
                : nil
        }

        for managerID in matchingManagerIDs {
            switch status {
            case .needsApproval, .needsAnswer, .failed:
                pauseWorkflow(
                    managerID,
                    reason: "\(profileName(profileID)) needs attention: \(status.label)."
                )
            case .stopped:
                if previousStatus == .working || previousStatus == .launching {
                    pauseWorkflow(
                        managerID,
                        reason: "\(profileName(profileID)) was stopped."
                    )
                }
            case .launching, .working:
                resumeWorkflowIndicator(managerID)
            case .completed:
                resumeWorkflowIndicator(managerID)
                advanceWorkflow(managerID, completedBy: profileID)
            }
        }
    }

    private func pauseWorkflow(_ managerID: UUID, reason: String) {
        guard var workflow = managerWorkflows[managerID],
              workflow.stage != .completed else { return }
        let shouldAnnounce = !workflow.isPaused || workflow.pauseReason != reason
        workflow.isPaused = true
        workflow.pauseReason = reason
        workflow.updatedAt = .now
        managerWorkflows[managerID] = workflow
        save()
        if shouldAnnounce {
            append(
                .init(
                    kind: .system,
                    text: "Workflow paused",
                    detail: reason
                ),
                to: managerID
            )
        }
    }

    private func resumeWorkflowIndicator(_ managerID: UUID) {
        guard var workflow = managerWorkflows[managerID],
              workflow.isPaused else { return }
        workflow.isPaused = false
        workflow.pauseReason = nil
        workflow.updatedAt = .now
        managerWorkflows[managerID] = workflow
        save()
    }

    private func transitionWorkflow(
        _ managerID: UUID,
        to stage: ManagerWorkflowStage
    ) -> ManagerWorkflow? {
        guard var workflow = managerWorkflows[managerID] else { return nil }
        workflow.stage = stage
        workflow.isPaused = false
        workflow.pauseReason = nil
        workflow.updatedAt = .now
        managerWorkflows[managerID] = workflow
        save()
        return workflow
    }

    private func advanceWorkflow(
        _ managerID: UUID,
        completedBy profileID: UUID
    ) {
        guard let workflow = managerWorkflows[managerID],
              expectedProfileID(for: workflow) == profileID else { return }
        let summary = latestAssistantText(for: profileID)

        switch workflow.stage {
        case .planning:
            requestWorkflowPlanApproval(
                managerID,
                implementationPlan: summary
            )

        case .building:
            guard let next = transitionWorkflow(managerID, to: .reviewing),
                  let reviewerID = next.team.reviewerProfileID else { return }
            Task { [weak self] in
                await self?.dispatchBuilderHandoff(
                    workflow: next,
                    builderID: profileID,
                    to: reviewerID,
                    instruction: Self.initialReviewInstruction,
                    resetRecipient: true,
                    fallbackStage: .building
                )
            }

        case .reviewing:
            guard let next = transitionWorkflow(managerID, to: .revising),
                  let builderID = next.team.builderProfileID else { return }
            dispatchWorkflowMessage(
                from: profileID,
                to: builderID,
                title: "Review findings",
                visibleText: summary,
                runtimeMessage: """
                The reviewer completed the first pass.

                \(summary)

                Address every actionable finding in your existing worktree. If the review is clean, verify that explicitly. Run the relevant tests, commit any fixes locally, and finish with a concise summary. Do not push or open a pull request.
                """
            )

        case .revising:
            guard let next = transitionWorkflow(managerID, to: .verifying),
                  let reviewerID = next.team.reviewerProfileID else { return }
            Task { [weak self] in
                await self?.dispatchBuilderHandoff(
                    workflow: next,
                    builderID: profileID,
                    to: reviewerID,
                    instruction: Self.verificationInstruction,
                    resetRecipient: false,
                    fallbackStage: .revising
                )
            }

        case .verifying:
            guard let next = transitionWorkflow(managerID, to: .publishing),
                  let publisherID = next.team.publisherProfileID else { return }
            Task { [weak self] in
                await self?.dispatchPublishing(
                    workflow: next,
                    reviewSummary: summary,
                    reviewerID: profileID,
                    to: publisherID
                )
            }

        case .publishing:
            guard let draftURL = latestPullRequestURL(for: profileID) else {
                pauseWorkflow(
                    managerID,
                    reason: "\(profileName(profileID)) finished without a draft PR URL."
                )
                append(
                    .init(
                        kind: .question,
                        title: "Draft PR URL required",
                        text: "Ask this bot to finish publishing and return the full draft pull-request URL."
                    ),
                    to: profileID
                )
                return
            }
            guard var next = transitionWorkflow(managerID, to: .reporting) else {
                return
            }
            next.pullRequestURL = draftURL
            next.updatedAt = .now
            managerWorkflows[managerID] = next
            save()
            dispatchWorkflowMessage(
                from: profileID,
                to: managerID,
                title: "Delivery prepared",
                visibleText: summary,
                runtimeMessage: """
                The documenter and PR writer completed the delivery pass.

                \(summary)

                Notify the user that the workflow is complete. Include the clickable draft pull-request URL, the branch, verification performed, and any remaining caveats. Do not modify the repository.
                """
            )

        case .reporting:
            guard var completed = transitionWorkflow(
                managerID,
                to: .completed
            ) else { return }
            completed.pullRequestURL =
                pullRequestURL(in: summary) ?? completed.pullRequestURL
            completed.updatedAt = .now
            managerWorkflows[managerID] = completed
            save()
            append(
                .init(
                    kind: .system,
                    text: "Managed workflow complete",
                    detail: [
                        completed.branch.map { "Branch: \($0)" },
                        completed.pullRequestURL.map { "Draft PR: \($0)" }
                    ]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                ),
                to: managerID
            )

        case .completed:
            break
        }
    }

    private func requestWorkflowPlanApproval(
        _ managerID: UUID,
        implementationPlan: String
    ) {
        guard var workflow = managerWorkflows[managerID],
              workflow.stage == .planning else {
            return
        }

        let approvalID = UUID()
        workflow.implementationPlan = implementationPlan
        workflow.planApprovalEntryID = approvalID
        workflow.approvedPlanEntryID = nil
        workflow.isPaused = true
        workflow.pauseReason =
            "Waiting for your approval of the implementation plan."
        workflow.updatedAt = .now

        var state = sessions[managerID] ?? AgentSessionState()
        let previousStatus = state.status
        state.status = .needsApproval
        state.hasUnreadCompletion = false
        state.entries.append(
            .init(
                id: approvalID,
                kind: .approval,
                title: "Approve implementation plan",
                text: implementationPlan,
                detail: "Approve to hand this plan to the Builder and continue the managed workflow. Decline to pause and send revision feedback.",
                approvalState: .pending
            )
        )

        sessions[managerID] = state
        managerWorkflows[managerID] = workflow
        save()

        if notificationsArePrepared,
           let notice = AgentAttentionNotice.transition(
               from: previousStatus,
               to: .needsApproval
           ),
           let manager = profiles.first(where: { $0.id == managerID }),
           !isAppWindowActive() {
            notifications?.post(notice, for: manager)
        }
    }

    private func dispatchInitialBuild(
        workflow: ManagerWorkflow,
        handoff: BuilderImplementationHandoff,
        to builderID: UUID
    ) async {
        guard let currentWorkflow = managerWorkflows[
            workflow.managerProfileID
        ],
              currentWorkflow.stage == .building,
              currentWorkflow.approvedPlanEntryID
                == handoff.approvalEntryID,
              currentWorkflow.implementationPlan == handoff.approvedPlan,
              sessions[workflow.managerProfileID]?.entries.contains(where: {
                  $0.id == handoff.approvalEntryID
                      && $0.kind == .approval
                      && $0.approvalState == .approved
                      && $0.text == handoff.approvedPlan
              }) == true else {
            pauseWorkflow(
                workflow.managerProfileID,
                reason: "The approved implementation plan is missing or inconsistent. The Builder was not dispatched."
            )
            return
        }

        guard await resetWorkflowRecipient(
            builderID,
            worktreeSeedID: workflow.id
        ) else {
            pauseWorkflow(
                workflow.managerProfileID,
                reason: "The assigned Builder is no longer available."
            )
            return
        }
        append(
            handoff.visibleEntry(
                sourceName: profileName(workflow.managerProfileID)
            ),
            to: builderID
        )
        performSend(handoff.runtimeMessage, to: builderID)
    }

    private func dispatchBuilderHandoff(
        workflow: ManagerWorkflow,
        builderID: UUID,
        to reviewerID: UUID,
        instruction: String,
        resetRecipient: Bool,
        fallbackStage: ManagerWorkflowStage
    ) async {
        guard let builder = profiles.first(where: { $0.id == builderID }) else {
            pauseWorkflow(
                workflow.managerProfileID,
                reason: "The assigned Builder is no longer available."
            )
            return
        }
        do {
            var package = try await worktrees.makeHandoff(
                from: builder,
                session: sessions[builderID] ?? AgentSessionState()
            )
            package.taskContext = workflow.request
            let lacksInitialCommit =
                workflow.latestHandoff == nil
                    && package.headRevision == package.baseRevision
            let hasUncommittedChanges =
                package.workingTreeSummary != "Clean"
            let hasFailedTests = package.testStatus == .failed
            guard !lacksInitialCommit,
                  !hasUncommittedChanges,
                  !hasFailedTests else {
                _ = transitionWorkflow(
                    workflow.managerProfileID,
                    to: fallbackStage
                )
                let reason: String
                if lacksInitialCommit {
                    reason = "The Builder handoff has no local commit."
                } else if hasUncommittedChanges {
                    reason = "The Builder handoff still has uncommitted changes."
                } else {
                    reason = "The Builder reported failing tests."
                }
                pauseWorkflow(workflow.managerProfileID, reason: reason)
                append(
                    .init(
                        kind: .question,
                        title: "Builder handoff is not ready",
                        text: "\(reason) Ask this bot to finish the work, verify it, and create a local commit."
                    ),
                    to: builderID
                )
                return
            }
            record(package, for: workflow.managerProfileID)
            if resetRecipient {
                guard await resetWorkflowRecipient(
                    reviewerID,
                    handoff: package
                ) else {
                    pauseWorkflow(
                        workflow.managerProfileID,
                        reason: "The assigned Reviewer is no longer available."
                    )
                    return
                }
            } else {
                attach(
                    package,
                    from: builderID,
                    to: reviewerID,
                    title: "Updated implementation"
                )
            }
            performSend(
                instruction,
                to: reviewerID
            )
        } catch {
            pauseWorkflow(
                workflow.managerProfileID,
                reason: "Could not prepare the Builder handoff: \(error.localizedDescription)"
            )
        }
    }

    private func dispatchPublishing(
        workflow: ManagerWorkflow,
        reviewSummary: String,
        reviewerID: UUID,
        to publisherID: UUID
    ) async {
        guard let package = managerWorkflows[
            workflow.managerProfileID
        ]?.latestHandoff else {
            pauseWorkflow(
                workflow.managerProfileID,
                reason: "The verified Builder handoff is missing."
            )
            return
        }
        guard await resetWorkflowRecipient(
            publisherID,
            handoff: package,
            sourceProfileID: reviewerID
        ) else {
            pauseWorkflow(
                workflow.managerProfileID,
                reason: "The assigned Documenter / PR Writer is no longer available."
            )
            return
        }
        performSend(
            """
            You are the Documenter / PR Writer in a managed bl00p workflow.

            Final reviewer result:
            \(reviewSummary)

            Update the relevant user-facing and developer documentation for the completed change. Run final verification, commit all completed work on the current branch, push that branch, and create a draft pull request. Respect every approval request surfaced by bl00p. Finish with a concise summary containing the branch, tests, and the full draft PR URL.
            """,
            to: publisherID
        )
    }

    private func resetWorkflowRecipient(
        _ profileID: UUID,
        handoff: GitHandoffPackage? = nil,
        sourceProfileID: UUID? = nil,
        worktreeSeedID: UUID? = nil
    ) async -> Bool {
        guard let profile = profiles.first(
            where: { $0.id == profileID }
        ) else { return false }

        connectedProfileIDs.remove(profileID)
        runGenerations[profileID] = UUID()
        await runtime.stop(profile: runtimeProfile(for: profile))

        if let index = profiles.firstIndex(where: { $0.id == profileID }) {
            if profiles[index].role == .builder {
                if worktreeSeedID != nil {
                    profiles[index].worktree = nil
                }
                if let handoff {
                    profiles[index].workingDirectory = handoff.repositoryPath
                    profiles[index].worktree = nil
                }
            } else if let handoff {
                profiles[index].workingDirectory = handoff.worktreePath
                profiles[index].worktree = nil
            }
        }

        var state = sessions[profileID] ?? AgentSessionState()
        state.status = .stopped
        state.sessionID = nil
        state.codexTurnModeVersion = nil
        state.pendingHandoff = handoff
        state.worktreeSeedID = worktreeSeedID
        if let handoff {
            let sourceName = profileName(
                sourceProfileID ?? handoff.sourceProfileID
            )
            state.entries.append(
                .init(
                    kind: .handoff,
                    title: "Workflow handoff from \(sourceName)",
                    text: handoff.taskContext,
                    detail: handoffDetail(handoff)
                )
            )
        }
        sessions[profileID] = state
        save()
        return true
    }

    private func attach(
        _ package: GitHandoffPackage,
        from sourceProfileID: UUID,
        to targetProfileID: UUID,
        title: String
    ) {
        var state = sessions[targetProfileID] ?? AgentSessionState()
        state.pendingHandoff = package
        state.entries.append(
            .init(
                kind: .handoff,
                title: title,
                text: "From \(profileName(sourceProfileID))",
                detail: handoffDetail(package)
            )
        )
        sessions[targetProfileID] = state
        save()
    }

    private func record(
        _ package: GitHandoffPackage,
        for managerID: UUID
    ) {
        guard var workflow = managerWorkflows[managerID] else { return }
        workflow.latestHandoff = package
        workflow.branch = package.branch
        workflow.updatedAt = .now
        managerWorkflows[managerID] = workflow
        save()
    }

    private func dispatchWorkflowMessage(
        from sourceProfileID: UUID,
        to targetProfileID: UUID,
        title: String,
        visibleText: String,
        runtimeMessage: String
    ) {
        append(
            .init(
                kind: .handoff,
                title: title,
                text: visibleText,
                detail: "From \(profileName(sourceProfileID))"
            ),
            to: targetProfileID
        )
        performSend(runtimeMessage, to: targetProfileID)
    }

    private func latestAssistantText(for profileID: UUID) -> String {
        sessions[profileID]?.entries
            .last(where: { $0.kind == .assistant && !$0.text.isEmpty })?
            .text
            ?? "No assistant summary was captured."
    }

    private func profileName(_ profileID: UUID) -> String {
        profiles.first(where: { $0.id == profileID })?.name ?? "Assigned bot"
    }

    private func pullRequestURL(in text: String) -> String? {
        let pattern = #"https://github\.com/[^\s\]\)]+/pull/[0-9]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range])
    }

    private func latestPullRequestURL(for profileID: UUID) -> String? {
        guard let entries = sessions[profileID]?.entries else { return nil }
        for entry in entries.reversed() {
            if let url = pullRequestURL(in: entry.text) {
                return url
            }
            if let detail = entry.detail,
               let url = pullRequestURL(in: detail) {
                return url
            }
        }
        return nil
    }

    private static let initialReviewInstruction = """
    You are the Reviewer in a managed bl00p workflow. Review the committed implementation at the attached branch and HEAD. Inspect correctness, regressions, test coverage, security, and unnecessary complexity. Do not edit code. Return a concise list of actionable findings ranked by severity, or state clearly that the review is clean.
    """

    private static let verificationInstruction = """
    Re-check the updated committed implementation at the attached branch and HEAD. Confirm that every earlier finding is resolved and that the reported tests support the change. Do not edit code. Return any remaining actionable findings, or state clearly that the change is ready for documentation and publishing.
    """

    private func apply(_ event: AgentEvent, to profileID: UUID) {
        var state = sessions[profileID] ?? AgentSessionState()
        var notice: AgentAttentionNotice?
        var statusTransition: (from: AgentStatus, to: AgentStatus)?

        switch event {
        case .status(let status):
            let previousStatus = state.status
            notice = AgentAttentionNotice.transition(
                from: previousStatus,
                to: status
            )
            state.status = status
            statusTransition = (previousStatus, status)
            if status == .failed || status == .stopped {
                connectedProfileIDs.remove(profileID)
            }
            if status == .failed,
               let entryID = inFlightUserEntryIDs.removeValue(
                   forKey: profileID
               ),
               let index = state.entries.firstIndex(
                   where: { $0.id == entryID }
               ) {
                state.entries[index].deliveryFailed = true
            } else if status == .completed
                        || status == .needsApproval
                        || status == .needsAnswer
                        || status == .stopped {
                inFlightUserEntryIDs.removeValue(forKey: profileID)
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
        if let statusTransition {
            handleWorkflowStatus(
                for: profileID,
                from: statusTransition.from,
                to: statusTransition.to
            )
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
                selectedBotID: selectedBotID,
                managerWorkflows: managerWorkflows
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
