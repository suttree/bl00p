import Foundation

#if os(macOS)
import AppKit
import SwiftUI
#else
import SwiftOpenUI
#endif

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

struct SessionCloseAssessment: Equatable, Sendable {
    var isActive: Bool
    var hasDirtyWorktree: Bool
    var participatesInWorkflow: Bool
    var leavesWorktreeOnDisk: Bool = false
    var worktreeWarning: String? = nil

    var requiresDestructiveConfirmation: Bool {
        isActive || hasDirtyWorktree || participatesInWorkflow
            || leavesWorktreeOnDisk
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [BotProfile]
    @Published var sessions: [UUID: AgentSessionState]
    @Published var sessionOrder: [UUID: [UUID]]
    @Published var selectedSessionIDs: [UUID: UUID]
    @Published var managerWorkflows: [UUID: ManagerWorkflow]
    @Published var selectedBotID: UUID?
    @Published var isInspectorVisible = false
    @Published var isAddingBot = false
    @Published var profileDeletionError: String?

    private let runtime: any AgentRuntime
    private let worktrees: any GitWorktreeManaging
    private let store: AppStateStore
    private let isAppWindowActive: () -> Bool
    private var notifications: (any AgentNotificationDelivering)?
    private var runGenerations: [UUID: UUID] = [:]
    private var connectedProfileIDs: Set<UUID> = []
    private var inFlightUserEntryIDs: [UUID: UUID] = [:]
    private var planningTurnAssistantEntryIDs: [UUID: Set<UUID>] = [:]
    private var draftSaveTasks: [UUID: Task<Void, Never>] = [:]
    private var workflowDispatchesInFlight: Set<UUID> = []
    private var notificationsArePrepared = false
    private var persistenceRevision: UInt64 = 0
    private var launchedProfileIDs: Set<UUID> = []
    private var turnEntryStartIndices: [UUID: Int] = [:]
    private var workflowStageStartedAt: [UUID: ContinuousClock.Instant] = [:]

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
            let recoverablePlanningManagerIDs = Set<UUID>(
                saved.managerWorkflows.compactMap { managerID, workflow in
                    guard workflow.stage == .planning,
                          let session = saved.sessions[managerID],
                          session.status == .completed
                            || (session.status == .needsApproval
                                && Self.hasSavedPlanApprovalEvidence(
                                    workflow: workflow,
                                    session: session
                                )) else {
                        return nil
                    }
                    return managerID
                }
            )
            let legacyPermissionBoundaryProfileIDs = Set(
                saved.sessions.compactMap { profileID, session in
                    session.entries.last?.text
                        == "Claude stopped at a permission boundary"
                        ? profileID
                        : nil
                }
            )
            var restoredSessions = Dictionary(
                uniqueKeysWithValues: saved.sessions.map { sessionKey, restoredSession in
                    var session = restoredSession
                    let ownerID = session.ownerProfileID ?? sessionKey
                    session.id = sessionKey
                    session.ownerProfileID = ownerID
                    if session.title == "New chat",
                       let firstMessage = session.entries.first(where: { $0.kind == .user })?.text {
                        session.title = Self.sessionTitle(from: firstMessage)
                    }
                    if session.worktree == nil,
                       let profile = restoredProfiles.first(where: { $0.id == ownerID }),
                       let legacyWorktree = profile.worktree {
                        var migratedWorktree = legacyWorktree
                        migratedWorktree.ownerSessionID = sessionKey
                        session.worktree = migratedWorktree
                    }
                    let endedAtLegacyPermissionBoundary =
                        session.entries.last?.text == "Claude stopped at a permission boundary"
                    session.entries = session.entries
                        .map(Self.migrateLegacyPermissionEntry)
                        .map(Self.migrateLegacyPlanApprovalEntry)
                    session.entries.removeAll(where: Self.isPrototypeStarterEntry)
                    if endedAtLegacyPermissionBoundary && session.status == .completed {
                        session.status = .needsAnswer
                    }
                    if codexProfileIDs.contains(ownerID),
                       session.codexTurnModeVersion != CodexThreadConfiguration.turnModeVersion {
                        session.sessionID = nil
                        let canRecoverPlanApproval =
                            recoverablePlanningManagerIDs.contains(sessionKey)
                        if !canRecoverPlanApproval {
                            session.status = .stopped
                        }
                    }
                    return (sessionKey, session)
                }
            )
            var restoredOrder = saved.sessionOrder
            var restoredSelections = saved.selectedSessionIDs
            for profile in restoredProfiles {
                var owned: [UUID] = restoredSessions.values
                    .filter { $0.ownerProfileID == profile.id }
                    .map { $0.id }
                if owned.isEmpty {
                    restoredSessions[profile.id] = AgentSessionState(
                        id: profile.id,
                        ownerProfileID: profile.id
                    )
                    owned = [profile.id]
                }
                let ordered = (restoredOrder[profile.id] ?? [])
                    .filter { owned.contains($0) }
                let missing = owned.filter { !ordered.contains($0) }
                let fallbackID = restoredSessions[profile.id] != nil
                    ? profile.id
                    : owned.first
                restoredOrder[profile.id] = ordered + missing
                if restoredOrder[profile.id]?.isEmpty != false, let fallbackID {
                    restoredOrder[profile.id] = [fallbackID]
                }
                if let selected = restoredSelections[profile.id],
                   restoredOrder[profile.id]?.contains(selected) == true {
                    continue
                }
                restoredSelections[profile.id] = fallbackID
            }
            sessions = restoredSessions
            sessionOrder = restoredOrder
            selectedSessionIDs = restoredSelections
            managerWorkflows = Dictionary(
                uniqueKeysWithValues: saved.managerWorkflows.map {
                    managerID, workflow in
                    var restored = workflow
                    if restored.participantSessionIDs.isEmpty {
                        restored.participantSessionIDs[.manager] = managerID
                        if let profileID =
                            restored.team.builderProfileID {
                            restored.participantSessionIDs[.builder] =
                                restoredSelections[profileID] ?? profileID
                        }
                        if let profileID =
                            restored.team.reviewerProfileID {
                            restored.participantSessionIDs[.reviewer] =
                                restoredSelections[profileID] ?? profileID
                        }
                        if let profileID =
                            restored.team.publisherProfileID {
                            restored.participantSessionIDs[.publisher] =
                                restoredSelections[profileID] ?? profileID
                        }
                    }
                    return (managerID, restored)
                }
            )
            selectedBotID = saved.selectedBotID ?? saved.profiles.first?.id
            let recoveredPlanApproval =
                reconcileRestoredWorkflowPlanApprovals()
            let pendingPlanApprovalManagerIDs = Set(
                managerWorkflows.compactMap { managerID, workflow in
                    workflow.stage == .planning
                        && sessions[managerID]?.entries.contains(where: {
                            $0.id == workflow.planApprovalEntryID
                                && $0.kind == .approval
                                && $0.approvalState == .pending
                        }) == true
                        ? managerID
                        : nil
                }
            )
            sessions = Dictionary(
                uniqueKeysWithValues: sessions.map {
                    sessionID, restoredSession in
                    var session = restoredSession
                    if session.status == .launching
                        || session.status == .working
                        || session.status == .needsApproval
                        || session.status == .needsAnswer {
                        let preservesLegacyAttention =
                            session.status == .needsAnswer
                            && legacyPermissionBoundaryProfileIDs.contains(
                                sessionID
                            )
                        session.status =
                            preservesLegacyAttention
                                || (session.status == .needsApproval
                                    && pendingPlanApprovalManagerIDs.contains(
                                        sessionID
                                    ))
                                ? session.status
                                : .stopped
                    }
                    return (sessionID, session)
                }
            )
            managerWorkflows = managerWorkflows.mapValues { workflow in
                guard workflow.stage != .completed else { return workflow }
                var restored = workflow
                if restored.stage == .revising,
                   restored.revisionStartedAt == nil {
                    // Workflows persisted before the revision gate was added
                    // need a lower bound for their post-review test evidence.
                    restored.revisionStartedAt = workflow.updatedAt
                }
                restored.isPaused = true

                if workflow.planApprovalEntryID != nil {
                    restored.pauseReason =
                        "Waiting for your approval of the implementation plan."
                    restored.resumeAvailableAfterRestart = false
                    return restored
                }

                if workflow.stage == .building,
                   workflow.implementationPlan != nil,
                   workflow.pendingDispatch == nil,
                   workflow.deliveredDispatchID == nil,
                   let builderID = workflow.team.builderProfileID {
                    let builderSessionID =
                        workflow.participantSessionIDs[.builder] ?? builderID
                    if let deliveredEntry = sessions[
                        builderSessionID
                    ]?.entries.first(
                        where: {
                            $0.kind == .handoff
                                && $0.title == "Implementation brief"
                        }
                    ) {
                        restored.deliveredDispatchID = deliveredEntry.id
                    } else {
                        restored.pendingDispatch = ManagerWorkflowDispatch(
                            kind: .initialBuild,
                            sourceProfileID: workflow.managerProfileID,
                            targetProfileID: builderID,
                            summary: workflow.implementationPlan ?? ""
                        )
                    }
                }

                if restored.pendingDispatch != nil {
                    restored.pauseReason =
                        "Preparing the persisted workflow handoff."
                    restored.resumeAvailableAfterRestart = false
                } else {
                    restored.pauseReason = "Ready to resume after the app restart."
                    restored.resumeAvailableAfterRestart = true
                }
                return restored
            }
            var recoveredPublishingWorkflow = false
            for workflow in managerWorkflows.values
                where workflow.stage == .publishing {
                guard let publisherID = workflow.team.publisherProfileID,
                      let package = workflow.latestHandoff else { continue }
                let publisherAlreadyUsesHandoffWorktree = profiles.contains {
                    $0.id == publisherID
                        && $0.workingDirectory == package.worktreePath
                }
                guard !publisherAlreadyUsesHandoffWorktree else { continue }
                recoveredPublishingWorkflow = true
                if let index = profiles.firstIndex(where: {
                    $0.id == publisherID
                }) {
                    profiles[index].workingDirectory = package.worktreePath
                    profiles[index].worktree = nil
                }
                var publisherSession =
                    sessions[publisherID] ?? AgentSessionState()
                publisherSession.status = .stopped
                publisherSession.sessionID = nil
                publisherSession.codexTurnModeVersion = nil
                publisherSession.pendingHandoff = package
                publisherSession.worktreeSeedID = nil
                if !publisherSession.entries.contains(where: {
                    $0.kind == .handoff
                        && $0.detail == package.timelineDetail
                }) {
                    publisherSession.entries.append(
                        .init(
                            kind: .handoff,
                            title: "Recovered workflow handoff from \(package.sourceName)",
                            text: package.taskContext,
                            detail: package.timelineDetail
                        )
                    )
                }
                sessions[publisherID] = publisherSession
            }
            selectedBotID = saved.selectedBotID ?? saved.profiles.first?.id
            if recoveredPlanApproval || recoveredPublishingWorkflow {
                store.save(
                    PersistedAppState(
                        profiles: profiles,
                        sessions: sessions,
                        selectedBotID: selectedBotID,
                        managerWorkflows: managerWorkflows
                    )
                )
            }
        } else {
            profiles = BotProfile.defaults
            sessions = Dictionary(
                uniqueKeysWithValues: BotProfile.defaults.map {
                    ($0.id, AgentSessionState(id: $0.id, ownerProfileID: $0.id))
                }
            )
            sessionOrder = Dictionary(
                uniqueKeysWithValues: BotProfile.defaults.map { ($0.id, [$0.id]) }
            )
            selectedSessionIDs = Dictionary(
                uniqueKeysWithValues: BotProfile.defaults.map { ($0.id, $0.id) }
            )
            managerWorkflows = [:]
            selectedBotID = BotProfile.defaults.first?.id
        }
        let restoredAt = ContinuousClock.now
        var legacyReportingManagerIDs: [UUID] = []
        for (managerID, workflow) in managerWorkflows
            where workflow.stage != .completed {
            let elapsedMilliseconds = Int64(
                max(0, Date.now.timeIntervalSince(workflow.updatedAt) * 1_000)
            )
            workflowStageStartedAt[managerID] = restoredAt.advanced(
                by: .milliseconds(-elapsedMilliseconds)
            )
            if workflow.stage == .reporting,
               workflow.pullRequestURL != nil {
                legacyReportingManagerIDs.append(managerID)
            }
        }
        for managerID in legacyReportingManagerIDs {
            guard let workflow = managerWorkflows[managerID],
                  let draftURL = workflow.pullRequestURL else { continue }
            completeWorkflow(
                managerID,
                publisherSummary: workflow.publisherSummary
                    ?? "Delivery prepared by the Documenter / PR Writer.",
                draftURL: draftURL
            )
        }

        save()
        Task { [weak self] in
            await Task.yield()
            self?.recoverPendingWorkflowDispatches()
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

    func flushPersistence() async {
        persistenceRevision &+= 1
        await store.flush(
            persistedState(),
            revision: persistenceRevision
        )
    }

    func session(for profileID: UUID) -> AgentSessionState {
        guard let sessionID = selectedSessionID(for: profileID) else {
            return AgentSessionState(ownerProfileID: profileID)
        }
        return sessions[sessionID] ?? AgentSessionState(
            id: sessionID,
            ownerProfileID: profileID
        )
    }

    func sessions(for profileID: UUID) -> [AgentSessionState] {
        (sessionOrder[profileID] ?? []).compactMap { sessions[$0] }
    }

    func selectedSessionID(for profileID: UUID) -> UUID? {
        if let selected = selectedSessionIDs[profileID],
           sessions[selected]?.ownerProfileID == profileID {
            return selected
        }
        return sessionOrder[profileID]?.first
    }

    func selectSession(_ sessionID: UUID, for profileID: UUID) {
        guard sessions[sessionID]?.ownerProfileID == profileID else { return }
        selectedSessionIDs[profileID] = sessionID
        markSessionViewed(sessionID)
        save()
    }

    @discardableResult
    func newChat(for profileID: UUID) -> UUID {
        let id = UUID()
        sessions[id] = AgentSessionState(id: id, ownerProfileID: profileID)
        sessionOrder[profileID, default: []].append(id)
        selectedSessionIDs[profileID] = id
        save()
        if let profile = profiles.first(where: { $0.id == profileID }),
           profile.role == .builder,
           !profile.workingDirectory.isEmpty {
            Task { [weak self] in
                _ = await self?.prepareRuntimeProfile(
                    profile,
                    sessionID: id
                )
            }
        }
        return id
    }

    func updateDraft(_ draft: String, for sessionID: UUID) {
        guard var session = sessions[sessionID] else { return }
        session.draft = draft
        session.updatedAt = .now
        sessions[sessionID] = session
        draftSaveTasks[sessionID]?.cancel()
        draftSaveTasks[sessionID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            draftSaveTasks[sessionID] = nil
            save(immediately: true)
        }
    }

    func persistDraft(for sessionID: UUID) {
        draftSaveTasks[sessionID]?.cancel()
        draftSaveTasks[sessionID] = nil
        save(immediately: true)
    }

    func closeAssessment(for sessionID: UUID) async -> SessionCloseAssessment {
        guard let session = sessions[sessionID] else {
            return SessionCloseAssessment(
                isActive: false,
                hasDirtyWorktree: false,
                participatesInWorkflow: false
            )
        }
        let isActive = session.status == .working || session.status == .launching
        var dirty = false
        var leavesWorktreeOnDisk = false
        var worktreeWarning: String?
        if let worktree = session.worktree {
            do {
                dirty = try await worktrees.worktreeIsDirty(worktree)
            } catch {
                leavesWorktreeOnDisk = true
                worktreeWarning = error.localizedDescription
            }
        }
        let participates = managerWorkflows.contains { managerSessionID, workflow in
            workflow.stage != .completed
                && (managerSessionID == sessionID
                    || workflow.participantSessionIDs.values.contains(sessionID))
        }
        return SessionCloseAssessment(
            isActive: isActive,
            hasDirtyWorktree: dirty,
            participatesInWorkflow: participates,
            leavesWorktreeOnDisk: leavesWorktreeOnDisk,
            worktreeWarning: worktreeWarning
        )
    }

    /// Returns an actionable error and retains the tab when cleanup fails.
    func closeSession(
        _ sessionID: UUID,
        confirmedDestructiveCleanup: Bool = false,
        ensureReplacement: Bool = true
    ) async -> String? {
        guard let session = sessions[sessionID],
              let profileID = session.ownerProfileID,
              let profile = profiles.first(where: { $0.id == profileID }) else {
            return "This chat session no longer exists."
        }

        do {
            let assessment = await closeAssessment(for: sessionID)
            guard !assessment.requiresDestructiveConfirmation
                    || confirmedDestructiveCleanup else {
                return "This chat needs confirmation before it can be closed."
            }

            runGenerations[sessionID] = UUID()
            connectedProfileIDs.remove(sessionID)
            inFlightUserEntryIDs.removeValue(forKey: sessionID)
            draftSaveTasks[sessionID]?.cancel()
            draftSaveTasks[sessionID] = nil
            await runtime.stop(
                profile: runtimeProfile(for: profile, sessionID: sessionID)
            )

            if let worktree = session.worktree,
               !assessment.leavesWorktreeOnDisk {
                try await worktrees.removeWorktree(
                    worktree,
                    force: assessment.hasDirtyWorktree
                )
            }

            for managerID in Array(managerWorkflows.keys) {
                guard var workflow = managerWorkflows[managerID],
                      managerID == sessionID
                        || (workflow.stage != .completed
                            && workflow.participantSessionIDs.values.contains(sessionID)) else {
                    continue
                }
                if managerID == sessionID {
                    managerWorkflows[managerID] = nil
                } else {
                    workflow.participantSessionIDs = workflow
                        .participantSessionIDs
                        .filter { $0.value != sessionID }
                    workflow.isPaused = true
                    workflow.pauseReason = "A participating chat session was closed."
                    workflow.updatedAt = .now
                    managerWorkflows[managerID] = workflow
                }
            }

            sessions[sessionID] = nil
            sessionOrder[profileID]?.removeAll { $0 == sessionID }
            if ensureReplacement && sessionOrder[profileID]?.isEmpty != false {
                _ = newChat(for: profileID)
            } else if selectedSessionIDs[profileID] == sessionID {
                selectedSessionIDs[profileID] = sessionOrder[profileID]?.first
            }
            save()
            return nil
        } catch {
            append(
                .init(
                    kind: .system,
                    text: "Could not close chat",
                    detail: error.localizedDescription
                ),
                to: sessionID
            )
            return error.localizedDescription
        }
    }

    func workflow(for managerProfileID: UUID) -> ManagerWorkflow? {
        let sessionID = selectedSessionID(for: managerProfileID) ?? managerProfileID
        if let workflow = managerWorkflows[sessionID] {
            return workflow
        }
        return sessionID == managerProfileID
            ? managerWorkflows[managerProfileID]
            : nil
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
        sessions[profile.id] = AgentSessionState(
            id: profile.id,
            ownerProfileID: profile.id
        )
        sessionOrder[profile.id] = [profile.id]
        selectedSessionIDs[profile.id] = profile.id
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
        profileDeletionError = nil
        let ownedSessionIDs = sessionOrder[profileID] ?? []
        let requiresCleanup = ownedSessionIDs.contains { sessionID in
            guard let session = sessions[sessionID] else { return false }
            return session.worktree != nil
                || session.status == .working
                || session.status == .launching
        }
        if requiresCleanup {
            Task { [weak self] in
                guard let self else { return }
                for sessionID in ownedSessionIDs {
                    let assessment = await closeAssessment(for: sessionID)
                    if assessment.leavesWorktreeOnDisk {
                        profileDeletionError =
                            "This bot has a worktree that cannot be removed safely. Close that chat first and choose to leave its worktree on disk."
                        return
                    }
                    if let error = await closeSession(
                        sessionID,
                        confirmedDestructiveCleanup: true,
                        ensureReplacement: false
                    ) {
                        profileDeletionError = error
                        return
                    }
                }
                deleteProfileRecord(profileID)
            }
        } else {
            deleteProfileRecord(profileID)
        }
    }

    private func deleteProfileRecord(_ profileID: UUID) {
        let ownedSessionIDs = sessionOrder[profileID] ?? []
        if let profile = profiles.first(where: { $0.id == profileID }) {
            for sessionID in ownedSessionIDs {
                Task {
                    await runtime.stop(
                        profile: runtimeProfile(
                            for: profile,
                            sessionID: sessionID
                        )
                    )
                }
            }
        }
        launchedProfileIDs.remove(profileID)
        for sessionID in ownedSessionIDs {
            connectedProfileIDs.remove(sessionID)
            inFlightUserEntryIDs.removeValue(forKey: sessionID)
            planningTurnAssistantEntryIDs.removeValue(forKey: sessionID)
            runGenerations[sessionID] = UUID()
            draftSaveTasks[sessionID]?.cancel()
            draftSaveTasks[sessionID] = nil
            sessions[sessionID] = nil
            managerWorkflows[sessionID] = nil
        }
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
        sessionOrder[profileID] = nil
        selectedSessionIDs[profileID] = nil
        for managerID in Array(managerWorkflows.keys)
            where managerWorkflows[managerID]?.managerProfileID == profileID {
            managerWorkflows[managerID] = nil
        }
        for managerID in Array(managerWorkflows.keys) {
            guard var workflow = managerWorkflows[managerID],
                  workflow.stage != .completed,
                  [
                    workflow.team.builderProfileID,
                    workflow.team.reviewerProfileID,
                    workflow.team.publisherProfileID
                  ].contains(profileID) else { continue }
            if let activeProfileID = expectedProfileID(for: workflow) {
                planningTurnAssistantEntryIDs.removeValue(
                    forKey: activeProfileID
                )
            }
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
        if let path = DirectoryChooser.chooseDirectory(
            title: "Choose a working directory",
            message: "bl00p will launch this bot in the selected folder."
           ),
           let index = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[index].workingDirectory = path
            profiles[index].worktree = nil
            save()
        }
    }

    func launch(_ profileID: UUID) {
        guard let profile = profiles.first(where: { $0.id == profileID }),
              let chatID = selectedSessionID(for: profileID) else { return }
        let previousThreadID = sessions[chatID]?.sessionID
        let generation = UUID()
        runGenerations[chatID] = generation
        connectedProfileIDs.remove(chatID)
        launchedProfileIDs.remove(profileID)
        inFlightUserEntryIDs.removeValue(forKey: chatID)
        planningTurnAssistantEntryIDs.removeValue(forKey: chatID)
        if var resumedSession = sessions[chatID], previousThreadID != nil {
            resumedSession.status = .stopped
            resumedSession.hasUnreadCompletion = false
            sessions[chatID] = resumedSession
        } else {
            sessions[chatID] = AgentSessionState(
                id: chatID,
                ownerProfileID: profileID,
                worktree: sessions[chatID]?.worktree,
                draft: sessions[chatID]?.draft ?? ""
            )
        }

        Task {
            await runtime.stop(
                profile: runtimeProfile(for: profile, sessionID: chatID)
            )
            guard let preparedProfile = await prepareRuntimeProfile(
                profile,
                sessionID: chatID
            ) else {
                return
            }
            let launchStartedAt = ContinuousClock.now
            let isColdStart = launchedProfileIDs.insert(profileID).inserted
            let stream = await runtime.start(
                profile: preparedProfile,
                resumeThreadID: previousThreadID
            )
            PerformanceMetrics.record(
                name: .runtimeLaunch,
                duration: launchStartedAt.duration(to: .now),
                profile: preparedProfile,
                coldStart: isColdStart
            )
            consume(stream, for: chatID, generation: generation)
        }
    }

    func launchAll() {
        for profile in profiles {
            launch(profile.id)
        }
    }

    func stop(_ profileID: UUID) {
        guard let profile = profiles.first(where: { $0.id == profileID }),
              let chatID = selectedSessionID(for: profileID) else { return }
        connectedProfileIDs.remove(chatID)
        launchedProfileIDs.remove(profileID)
        planningTurnAssistantEntryIDs.removeValue(forKey: chatID)
        runGenerations[chatID] = UUID()
        Task {
            await runtime.stop(
                profile: runtimeProfile(for: profile, sessionID: chatID)
            )
        }
        apply(.status(.stopped), to: chatID)
        append(
            .init(kind: .system, text: "Session stopped by you."),
            to: chatID
        )
    }

    func send(
        _ text: String,
        attachments: [ImageAttachment] = [],
        to profileID: UUID
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty,
              let profile = profiles.first(where: { $0.id == profileID }),
              let chatID = selectedSessionID(for: profileID) else {
            return
        }
        guard let state = sessions[chatID] else { return }
        guard state.status != .launching, state.status != .working else {
            return
        }
        guard managerWorkflows[chatID]?.planApprovalEntryID == nil else {
            return
        }

        let startedWorkflow = startWorkflowIfNeeded(
            request: trimmed,
            manager: profile,
            sessionID: chatID
        )
        performSend(
            trimmed,
            attachments: attachments,
            to: profileID,
            sessionID: chatID,
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
                    detail: "Planning → Your approval → Building → Review → Conditional fixes & re-check → Documentation & draft PR"
                ),
                to: chatID
            )
        }
    }

    func retry(_ entryID: UUID, for profileID: UUID) {
        guard let chatID = selectedSessionID(for: profileID) else { return }
        guard let state = sessions[chatID] else { return }
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
            sessionID: chatID,
            retryingEntryID: entryID
        )
    }

    private func performSend(
        _ text: String,
        attachments: [ImageAttachment] = [],
        to profileID: UUID,
        sessionID explicitSessionID: UUID? = nil,
        visibleEntry: TimelineEntry? = nil,
        retryingEntryID: UUID? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty,
              let profile = profiles.first(where: { $0.id == profileID }) else { return }
        guard let chatID = explicitSessionID ?? selectedSessionID(for: profileID) else {
            return
        }

        guard let currentState = sessions[chatID],
              currentState.ownerProfileID == profileID else { return }
        guard currentState.status != .launching, currentState.status != .working else { return }

        let shouldLaunch = !connectedProfileIDs.contains(chatID)
            || currentState.status == .stopped
            || currentState.status == .failed
        let previousThreadID = currentState.sessionID
        let pendingHandoff = currentState.pendingHandoff
        let generation = runGenerations[chatID] ?? UUID()
        runGenerations[chatID] = generation

        var updatedSession = currentState
        updatedSession.status = shouldLaunch ? .launching : .working
        if shouldLaunch {
            updatedSession.hasUnreadCompletion = false
        }
        if let visibleEntry {
            updatedSession.entries.append(visibleEntry)
            if updatedSession.title == "New chat", visibleEntry.kind == .user {
                updatedSession.title = Self.sessionTitle(from: visibleEntry.text)
            }
        }
        updatedSession.updatedAt = .now
        let inFlightEntryID = visibleEntry?.id ?? retryingEntryID
        if let inFlightEntryID {
            if let index = updatedSession.entries.firstIndex(
                where: { $0.id == inFlightEntryID }
            ) {
                updatedSession.entries[index].deliveryFailed = nil
            }
            inFlightUserEntryIDs[chatID] = inFlightEntryID
        }
        sessions[chatID] = updatedSession
        save()
        let turnStartedAt = ContinuousClock.now
        if shouldLaunch {
            launchedProfileIDs.remove(profileID)
        }
        resumeWorkflowsForExplicitSend(to: chatID)

        Task { [weak self] in
            guard let self else { return }
            guard let preparedProfile = await prepareRuntimeProfile(
                profile,
                sessionID: chatID,
                handoff: pendingHandoff
            ) else {
                return
            }

            if shouldLaunch {
                await runtime.stop(
                    profile: runtimeProfile(for: profile, sessionID: chatID)
                )
                let launchStartedAt = ContinuousClock.now
                let isColdStart =
                    launchedProfileIDs.insert(profileID).inserted
                let launchStream = await runtime.start(
                    profile: preparedProfile,
                    resumeThreadID: previousThreadID
                )
                PerformanceMetrics.record(
                    name: .runtimeLaunch,
                    duration: launchStartedAt.duration(to: .now),
                    profile: preparedProfile,
                    coldStart: isColdStart
                )
                var reachedReady = false
                for await event in launchStream {
                    guard runGenerations[chatID] == generation else { return }
                    if case .entry(let entry) = event, entry.kind == .question {
                        continue
                    }
                    if case .status(.needsAnswer) = event {
                        reachedReady = true
                        break
                    }
                    apply(event, to: chatID)
                    if case .status(.failed) = event {
                        break
                    }
                }
                guard reachedReady else { return }
                // The launch stream stays open as this session's lifecycle
                // channel; keep consuming it so a later idle disconnect is
                // still reported to the UI.
                consume(launchStream, for: chatID, generation: generation)
            }

            if pendingHandoff != nil {
                guard var handoffConsumed = sessions[chatID] else { return }
                handoffConsumed.pendingHandoff = nil
                sessions[chatID] = handoffConsumed
                save()
            }
            let runtimeMessage = runtimeMessage(
                userMessage: workflowRuntimeMessage(
                    for: profile,
                    sessionID: chatID,
                    userMessage: trimmed
                ),
                handoff: pendingHandoff
            )
            if managerWorkflows[chatID]?.stage == .planning,
               managerWorkflows[chatID]?.planApprovalEntryID == nil {
                planningTurnAssistantEntryIDs[chatID] = []
            }
            let responseStream = await runtime.respond(
                to: runtimeMessage,
                attachments: attachments,
                profile: preparedProfile
            )
            turnEntryStartIndices[chatID] =
                sessions[chatID]?.entries.count ?? 0
            var recordedFirstOutput = false
            for await event in responseStream {
                guard runGenerations[chatID] == generation else { return }
                if !recordedFirstOutput {
                    switch event {
                    case .entry, .upsertEntry:
                        recordedFirstOutput = true
                        PerformanceMetrics.record(
                            name: .timeToFirstOutput,
                            duration: turnStartedAt.duration(to: .now),
                            profile: preparedProfile
                        )
                    default:
                        break
                    }
                }
                apply(event, to: chatID)
                if case .status(.completed) = event {
                    PerformanceMetrics.record(
                        name: .turnCompletion,
                        duration: turnStartedAt.duration(to: .now),
                        profile: preparedProfile
                    )
                }
            }
        }
    }

    func resolveApproval(_ entryID: UUID, approved: Bool, for profileID: UUID) {
        guard let chatID = selectedSessionID(for: profileID) else { return }
        if managerWorkflows[chatID]?.stage == .planning,
           managerWorkflows[chatID]?.planApprovalEntryID == entryID {
            resolveWorkflowPlanApproval(
                entryID,
                approved: approved,
                for: chatID
            )
            return
        }

        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }

        let generation = runGenerations[chatID] ?? UUID()
        runGenerations[chatID] = generation
        Task {
            let stream = await runtime.resolveApproval(
                entryID: entryID,
                approved: approved,
                profile: runtimeProfile(for: profile, sessionID: chatID)
            )
            consume(stream, for: chatID, generation: generation)
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
            workflow.resumeAvailableAfterRestart = false
            workflow.pendingDispatch =
                workflow.pendingDispatch
                    ?? ManagerWorkflowDispatch(
                        kind: .initialBuild,
                        sourceProfileID: workflow.managerProfileID,
                        targetProfileID: builderID,
                        summary: handoff.approvedPlan
                    )
            sessions[managerID] = state
            managerWorkflows[managerID] = workflow
            save(immediately: true)
            beginPendingWorkflowDispatch(for: managerID)
        } else {
            state.status = .needsAnswer
            workflow.approvedPlanEntryID = nil
            workflow.isPaused = true
            workflow.pauseReason =
                "Plan declined. Send feedback to the Manager to request a revised plan."
            sessions[managerID] = state
            managerWorkflows[managerID] = workflow
            save(immediately: true)
        }
    }

    func recoverPendingWorkflowDispatches() {
        let managerIDs = managerWorkflows.compactMap { managerID, workflow in
            workflow.pendingDispatch != nil
                ? managerID
                : nil
        }
        for managerID in managerIDs {
            beginPendingWorkflowDispatch(for: managerID)
        }
    }

    func resumeWorkflow(_ managerProfileOrSessionID: UUID) {
        let managerID =
            managerWorkflows[managerProfileOrSessionID] != nil
                ? managerProfileOrSessionID
                : selectedSessionID(for: managerProfileOrSessionID)
                    ?? managerProfileOrSessionID
        guard var workflow = managerWorkflows[managerID],
              workflow.stage != .completed,
              workflow.planApprovalEntryID == nil,
              workflow.resumeAvailableAfterRestart == true,
              let activeSessionID = expectedProfileID(for: workflow) else {
            return
        }
        let activeProfileID =
            sessions[activeSessionID]?.ownerProfileID ?? activeSessionID
        guard profiles.contains(where: {
            $0.id == activeProfileID
        }) else {
            return
        }

        if workflow.stage == .reviewing
            || workflow.stage == .verifying
            || workflow.stage == .publishing {
            let activeRole: AgentRole =
                workflow.stage == .publishing ? .publisher : .reviewer
            guard let handoff = workflow.latestHandoff,
                  let handoffSessionID = participantSessionID(
                      activeRole,
                      in: workflow
                  ),
                  prepareWorkflowHandoff(
                      handoff,
                      for: sessions[handoffSessionID]?.ownerProfileID
                          ?? activeProfileID,
                      sessionID: handoffSessionID
                  ) else {
                pauseWorkflow(
                    managerID,
                    reason: "The persisted workflow handoff could not be restored."
                )
                return
            }
        }

        workflow.isPaused = false
        workflow.pauseReason = nil
        workflow.resumeAvailableAfterRestart = false
        workflow.updatedAt = .now
        managerWorkflows[managerID] = workflow
        save()
        append(
            .init(
                kind: .system,
                text: "Managed workflow resumed",
                detail: "\(profileNameForSession(activeSessionID)) is continuing \(workflow.stage.label.lowercased())."
            ),
            to: managerID
        )
        let instruction: String
        if let dispatch = workflow.deliveredDispatch,
           dispatch.id == workflow.deliveredDispatchID {
            instruction = dispatch.kind == .initialBuild
                ? resumeInstruction(for: workflow)
                : runtimeInstruction(for: dispatch, workflow: workflow)
        } else {
            instruction = resumeInstruction(for: workflow)
        }
        performSend(
            instruction,
            to: activeProfileID,
            sessionID: activeSessionID
        )
    }

    func markViewed(_ profileID: UUID) {
        guard let chatID = selectedSessionID(for: profileID) else { return }
        markSessionViewed(chatID)
    }

    private func markSessionViewed(_ chatID: UUID) {
        guard var state = sessions[chatID] else { return }
        if state.status == .completed {
            state.hasUnreadCompletion = false
            sessions[chatID] = state
            save()
        }
    }

    func handoff(from sourceProfileID: UUID, to targetProfileID: UUID) {
        guard sourceProfileID != targetProfileID,
              let source = profiles.first(where: { $0.id == sourceProfileID }),
              let target = profiles.first(where: { $0.id == targetProfileID }),
              let sourceSessionID = selectedSessionID(for: sourceProfileID),
              let targetSessionID = selectedSessionID(for: targetProfileID),
              source.role == .builder,
              sessions[sourceSessionID]?.worktree != nil,
              sessions[sourceSessionID]?.status != .working,
              sessions[sourceSessionID]?.status != .launching else { return }

        guard let sourceSession = sessions[sourceSessionID] else { return }
        var sourceForHandoff = source
        sourceForHandoff.worktree = sourceSession.worktree
        Task { [weak self] in
            guard let self else { return }
            do {
                let startedAt = ContinuousClock.now
                let package = try await worktrees.makeHandoff(
                    from: sourceForHandoff,
                    session: sourceSession
                )
                PerformanceMetrics.record(
                    name: .handoffPreparation,
                    duration: startedAt.duration(to: .now),
                    profile: source
                )
                await runtime.stop(
                    profile: runtimeProfile(for: target, sessionID: targetSessionID)
                )
                connectedProfileIDs.remove(targetSessionID)
                launchedProfileIDs.remove(targetProfileID)
                runGenerations[targetSessionID] = UUID()

                guard var targetSession = sessions[targetSessionID],
                      var updatedSourceSession = sessions[sourceSessionID] else {
                    return
                }
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

                targetSession.status = .stopped
                targetSession.sessionID = nil
                targetSession.pendingHandoff = package
                targetSession.entries.append(
                    .init(
                        kind: .handoff,
                        title: "Handoff from \(source.name)",
                        text: package.taskContext,
                        detail: package.timelineDetail
                    )
                )
                sessions[targetSessionID] = targetSession

                updatedSourceSession.entries.append(
                    .init(
                        kind: .system,
                        text: "Handoff prepared for \(target.name)",
                        detail: "\(package.branch) · Tests \(package.testStatus.label.lowercased())"
                    )
                )
                sessions[sourceSessionID] = updatedSourceSession
                selectedBotID = targetProfileID
                selectedSessionIDs[targetProfileID] = targetSessionID
                save()
            } catch {
                append(
                    .init(
                        kind: .system,
                        text: "Could not create handoff",
                        detail: error.localizedDescription
                    ),
                    to: sourceSessionID
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
        sessionID: UUID? = nil,
        handoff: GitHandoffPackage? = nil
    ) async -> BotProfile? {
        guard let chatID = sessionID ?? selectedSessionID(for: profile.id) else {
            return nil
        }
        guard profile.role == .builder, !profile.workingDirectory.isEmpty else {
            return runtimeProfile(for: profile, sessionID: chatID)
        }

        do {
            let startedAt = ContinuousClock.now
            var worktreeProfile = profile
            worktreeProfile.worktree = sessions[chatID]?.worktree
            if let existingWorktree = worktreeProfile.worktree {
                worktreeProfile.workingDirectory = existingWorktree.repositoryPath
            }
            let ownership = try await worktrees.prepareWorktree(
                for: worktreeProfile,
                sessionID: chatID,
                startingPoint: handoff?.branch,
                handoffID: handoff?.id
                    ?? sessions[chatID]?.worktreeSeedID
            )
            PerformanceMetrics.record(
                name: .worktreePreparation,
                duration: startedAt.duration(to: .now),
                profile: profile
            )
            guard var session = sessions[chatID] else {
                try? await worktrees.removeWorktree(ownership, force: false)
                return nil
            }
            session.worktreeSeedID = nil
            session.worktree = ownership
            session.updatedAt = .now
            sessions[chatID] = session
            // Keep the original tab's mirrored value for decoding compatibility
            // with pre-tab state. New tabs never write ownership onto the bot.
            if chatID == profile.id,
               let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                var legacyMirror = ownership
                legacyMirror.ownerSessionID = nil
                profiles[index].worktree = legacyMirror
            }
            save()
            return runtimeProfile(for: profile, sessionID: chatID)
        } catch {
            apply(.status(.failed), to: chatID)
            append(
                .init(
                    kind: .system,
                    text: "Could not prepare isolated worktree",
                    detail: error.localizedDescription
                ),
                to: chatID
            )
            return nil
        }
    }

    private func runtimeProfile(
        for profile: BotProfile,
        sessionID: UUID? = nil
    ) -> BotProfile {
        let chatID = sessionID ?? selectedSessionID(for: profile.id) ?? profile.id
        var runtimeProfile = profile
        runtimeProfile.id = chatID
        runtimeProfile.worktree = sessions[chatID]?.worktree
        runtimeProfile.workingDirectory =
            sessions[chatID]?.worktree?.worktreePath ?? profile.workingDirectory
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
        sessionID: UUID,
        userMessage: String
    ) -> String {
        guard profile.role == .manager,
              let workflow = managerWorkflows[sessionID],
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
        manager: BotProfile,
        sessionID: UUID
    ) -> Bool {
        guard let team = validatedTeam(for: manager),
              managerWorkflows[sessionID]?.stage == .completed
                || managerWorkflows[sessionID] == nil else {
            return false
        }

        var participants: [AgentRole: UUID] = [.manager: sessionID]
        if let profileID = team.builderProfileID,
           let participantID = selectedSessionID(for: profileID) {
            participants[.builder] = participantID
        }
        if let profileID = team.reviewerProfileID,
           let participantID = selectedSessionID(for: profileID) {
            participants[.reviewer] = participantID
        }
        if let profileID = team.publisherProfileID,
           let participantID = selectedSessionID(for: profileID) {
            participants[.publisher] = participantID
        }
        guard participants.count == AgentRole.allCases.count else {
            append(
                .init(
                    kind: .system,
                    text: "Could not start managed workflow",
                    detail: "Every assigned bot needs an available chat session."
                ),
                to: sessionID
            )
            return false
        }
        let claimedSessionIDs = Set(
            managerWorkflows
                .filter { workflowID, workflow in
                    workflowID != sessionID && workflow.stage != .completed
                }
                .flatMap { $0.value.participantSessionIDs.values }
        )
        let conflicts = Set(participants.values).intersection(claimedSessionIDs)
        guard conflicts.isEmpty else {
            append(
                .init(
                    kind: .system,
                    text: "Could not start managed workflow",
                    detail: "One or more selected participant chats are already assigned to an active workflow."
                ),
                to: sessionID
            )
            return false
        }
        managerWorkflows[sessionID] = ManagerWorkflow(
            managerProfileID: manager.id,
            team: team,
            request: request.isEmpty
                ? "Work from the attached context."
                : request,
            participantSessionIDs: participants
        )
        workflowStageStartedAt[manager.id] = .now
        save(immediately: true)
        return true
    }

    private func expectedProfileID(
        for workflow: ManagerWorkflow
    ) -> UUID? {
        switch workflow.stage {
        case .planning, .reporting:
            workflow.participantSessionIDs[.manager] ?? workflow.managerProfileID
        case .building, .revising:
            workflow.participantSessionIDs[.builder]
                ?? workflow.team.builderProfileID
        case .reviewing, .verifying:
            workflow.participantSessionIDs[.reviewer]
                ?? workflow.team.reviewerProfileID
        case .publishing:
            workflow.participantSessionIDs[.publisher]
                ?? workflow.team.publisherProfileID
        case .completed:
            nil
        }
    }

    private func participantSessionID(
        _ role: AgentRole,
        in workflow: ManagerWorkflow
    ) -> UUID? {
        if let sessionID = workflow.participantSessionIDs[role] {
            return sessionID
        }
        switch role {
        case .manager:
            return workflow.managerProfileID
        case .builder:
            return workflow.team.builderProfileID
        case .reviewer:
            return workflow.team.reviewerProfileID
        case .publisher:
            return workflow.team.publisherProfileID
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
                && (!workflow.isPaused
                    || status == .launching
                    || status == .working)
                && (workflow.participantSessionIDs.isEmpty
                    || workflow.participantSessionIDs.values.contains(profileID))
                && expectedProfileID(for: workflow) == profileID
                ? managerID
                : nil
        }

        for managerID in matchingManagerIDs {
            switch status {
            case .needsAnswer:
                if let workflow = managerWorkflows[managerID],
                   workflow.stage == .reviewing
                    || workflow.stage == .verifying,
                   latestReviewOutput(for: profileID).disposition != nil {
                    resumeWorkflowIndicator(managerID)
                    advanceWorkflow(managerID, completedBy: profileID)
                } else {
                    pauseWorkflow(
                        managerID,
                        reason: "\(profileNameForSession(profileID)) needs attention: \(status.label)."
                    )
                }
            case .needsApproval:
                pauseWorkflow(
                    managerID,
                    reason: "\(profileNameForSession(profileID)) needs attention: \(status.label)."
                )
            case .failed:
                planningTurnAssistantEntryIDs.removeValue(forKey: profileID)
                pauseWorkflow(
                    managerID,
                    reason: "\(profileNameForSession(profileID)) needs attention: \(status.label)."
                )
            case .stopped:
                planningTurnAssistantEntryIDs.removeValue(forKey: profileID)
                if previousStatus == .working || previousStatus == .launching {
                    pauseWorkflow(
                        managerID,
                        reason: "\(profileNameForSession(profileID)) was stopped."
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
        save(immediately: true)
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
        workflow.resumeAvailableAfterRestart = false
        workflow.updatedAt = .now
        managerWorkflows[managerID] = workflow
        save(immediately: true)
    }

    private func resumeWorkflowsForExplicitSend(to sessionID: UUID) {
        let managerIDs: [UUID] = managerWorkflows.compactMap { managerID, workflow in
            guard workflow.isPaused,
                  workflow.planApprovalEntryID == nil,
                  expectedProfileID(for: workflow) == sessionID,
                  workflow.participantSessionIDs.isEmpty
                    || workflow.participantSessionIDs.values.contains(sessionID) else {
                return nil
            }
            return managerID
        }
        for managerID in managerIDs {
            resumeWorkflowIndicator(managerID)
        }
    }

    private func transitionWorkflow(
        _ managerID: UUID,
        to stage: ManagerWorkflowStage,
        persist: Bool = true
    ) -> ManagerWorkflow? {
        guard var workflow = managerWorkflows[managerID] else { return nil }
        let now = ContinuousClock.now
        if let startedAt = workflowStageStartedAt[managerID] {
            let profile = expectedProfileID(for: workflow).flatMap { profileID in
                profiles.first(where: { $0.id == profileID })
            }
            PerformanceMetrics.record(
                name: .workflowStage,
                duration: startedAt.duration(to: now),
                profile: profile,
                stage: workflow.stage
            )
        }
        workflow.stage = stage
        workflow.isPaused = false
        workflow.pauseReason = nil
        workflow.resumeAvailableAfterRestart = false
        workflow.updatedAt = .now
        managerWorkflows[managerID] = workflow
        workflowStageStartedAt[managerID] = now
        if persist {
            save(immediately: true)
        }
        return workflow
    }

    private func advanceWorkflow(
        _ managerID: UUID,
        completedBy profileID: UUID
    ) {
        guard let workflow = managerWorkflows[managerID],
              expectedProfileID(for: workflow) == profileID else { return }
        let reviewOutput: ReviewOutput? =
            workflow.stage == .reviewing || workflow.stage == .verifying
                ? latestReviewOutput(for: profileID)
                : nil
        if workflow.stage == .planning {
            let capturedEntryIDs =
                planningTurnAssistantEntryIDs.removeValue(forKey: profileID)
                ?? []
            guard let planEntry = sessions[profileID]?.entries.last(where: {
                capturedEntryIDs.contains($0.id)
                    && $0.kind == .assistant
                    && !$0.text.isEmpty
            }) else {
                pauseWorkflow(
                    managerID,
                    reason: "\(profileName(profileID)) finished the planning turn without returning an implementation plan. Send feedback to try again."
                )
                return
            }
            requestWorkflowPlanApproval(
                managerID,
                implementationPlan: planEntry.text,
                replacingAssistantEntryID: planEntry.id
            )
            return
        }

        let summary = reviewOutput?.summary
            ?? latestAssistantText(for: profileID)
        switch workflow.stage {
        case .planning:
            break
        case .building:
            guard let builderProfileID =
                    sessions[profileID]?.ownerProfileID,
                  let reviewerID = workflow.team.reviewerProfileID,
                  participantSessionID(.reviewer, in: workflow) != nil else {
                return
            }
            queueWorkflowDispatch(
                .init(
                    kind: .initialReview,
                    sourceProfileID: builderProfileID,
                    targetProfileID: reviewerID,
                    summary: workflow.implementationPlan
                        ?? workflow.request
                ),
                for: managerID
            )

        case .reviewing:
            if reviewOutput?.disposition == .clean {
                beginPublishing(
                    managerID,
                    reviewSummary: summary,
                    reviewerID: profileID
                )
            } else {
                dispatchRevision(
                    managerID,
                    reviewSummary: summary,
                    reviewerID: profileID
                )
            }

        case .revising:
            guard let builderProfileID =
                    sessions[profileID]?.ownerProfileID,
                  let reviewerID = workflow.team.reviewerProfileID,
                  participantSessionID(.reviewer, in: workflow) != nil else {
                return
            }
            queueWorkflowDispatch(
                .init(
                    kind: .verification,
                    sourceProfileID: builderProfileID,
                    targetProfileID: reviewerID,
                    summary: workflow.implementationPlan
                        ?? workflow.request
                ),
                for: managerID
            )

        case .verifying:
            if reviewOutput?.disposition == .clean {
                beginPublishing(
                    managerID,
                    reviewSummary: summary,
                    reviewerID: profileID
                )
            } else {
                dispatchRevision(
                    managerID,
                    reviewSummary: summary,
                    reviewerID: profileID
                )
                return
            }

        case .publishing:
            guard let draftURL = latestPullRequestURL(for: profileID) else {
                pauseWorkflow(
                    managerID,
                    reason: "\(profileNameForSession(profileID)) finished without a draft PR URL."
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
            completeWorkflow(
                managerID,
                publisherSummary: summary,
                draftURL: draftURL
            )

        case .reporting:
            guard let draftURL =
                pullRequestURL(in: summary) ?? workflow.pullRequestURL else {
                pauseWorkflow(
                    managerID,
                    reason: "The restored workflow is missing its draft PR URL."
                )
                return
            }
            completeWorkflow(
                managerID,
                publisherSummary: workflow.publisherSummary ?? summary,
                draftURL: draftURL
            )

        case .completed:
            break
        }
    }

    private static let workflowPlanApprovalTitle =
        "Approve implementation plan"
    private static let workflowPlanApprovalDetail =
        "Approve to hand this plan to the Builder and continue the managed workflow. Decline to pause and send revision feedback."
    private static let workflowPlanApprovalPauseReason =
        "Waiting for your approval of the implementation plan."

    private static func nonEmptyPlan(_ text: String?) -> String? {
        guard let text,
              !text.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ).isEmpty else {
            return nil
        }
        return text
    }

    private static func isPendingWorkflowPlanApproval(
        _ entry: TimelineEntry
    ) -> Bool {
        entry.kind == .approval
            && entry.title == workflowPlanApprovalTitle
            && entry.approvalState == .pending
    }

    private static func pendingWorkflowPlanApprovals(
        in session: AgentSessionState
    ) -> [(index: Int, entry: TimelineEntry)] {
        session.entries.enumerated().compactMap { index, entry in
            isPendingWorkflowPlanApproval(entry)
                ? (index, entry)
                : nil
        }
    }

    private static func hasSavedPlanApprovalEvidence(
        workflow: ManagerWorkflow,
        session: AgentSessionState
    ) -> Bool {
        let hasPendingPlanCard =
            pendingWorkflowPlanApprovals(in: session).contains(where: {
                nonEmptyPlan($0.entry.text) != nil
            })
        guard let approvalID = workflow.planApprovalEntryID,
              nonEmptyPlan(workflow.implementationPlan) != nil else {
            return hasPendingPlanCard
        }
        let referencedEntry = session.entries.first(where: {
            $0.id == approvalID
        })
        return hasPendingPlanCard
            || referencedEntry == nil
            || referencedEntry.map(isPendingWorkflowPlanApproval) == true
    }

    private func reconcileRestoredWorkflowPlanApprovals() -> Bool {
        var changed = false
        for managerID in Array(managerWorkflows.keys) {
            if restoreWorkflowPlanApproval(managerID) {
                changed = true
            }
            guard var workflow = managerWorkflows[managerID],
                  workflow.stage == .planning,
                  var state = sessions[managerID] else {
                continue
            }
            let pendingPlanEntries =
                Self.pendingWorkflowPlanApprovals(in: state)
            let hasCoherentApproval =
                state.status == .needsApproval
                && Self.nonEmptyPlan(workflow.implementationPlan) != nil
                && pendingPlanEntries.count == 1
                && pendingPlanEntries.first?.entry.id
                    == workflow.planApprovalEntryID
                && pendingPlanEntries.first?.entry.text
                    == workflow.implementationPlan
            guard !hasCoherentApproval else {
                continue
            }

            let previousWorkflow = workflow
            let previousStatus = state.status
            let previousEntries = state.entries
            if workflow.planApprovalEntryID != nil {
                workflow.planApprovalEntryID = nil
            }
            if state.status == .completed {
                state.status = .stopped
            }
            state.entries.removeAll(
                where: Self.isPendingWorkflowPlanApproval
            )
            let discardedInvalidApproval =
                workflow != previousWorkflow
                || state.status != previousStatus
                || state.entries != previousEntries
            guard discardedInvalidApproval else { continue }

            workflow.updatedAt = .now
            managerWorkflows[managerID] = workflow
            sessions[managerID] = state
            changed = true
        }
        return changed
    }

    @discardableResult
    private func restoreWorkflowPlanApproval(
        _ managerID: UUID
    ) -> Bool {
        guard let workflow = managerWorkflows[managerID],
              workflow.stage == .planning,
              let state = sessions[managerID],
              state.status == .completed || state.status == .needsApproval else {
            return false
        }

        let pendingPlanEntries =
            Self.pendingWorkflowPlanApprovals(in: state)
        if let referencedID = workflow.planApprovalEntryID,
           let referencedEntry = state.entries.first(where: {
               $0.id == referencedID
           }),
           !Self.isPendingWorkflowPlanApproval(referencedEntry) {
            return false
        }
        let restoredPlan: String?
        if state.status == .completed {
            restoredPlan = latestAssistantResponse(for: managerID)
        } else {
            let referencedEntry = workflow.planApprovalEntryID.flatMap {
                approvalID in
                pendingPlanEntries.first(where: {
                    $0.entry.id == approvalID
                })?.entry
            }
            let savedPlan = Self.nonEmptyPlan(
                workflow.implementationPlan
            )
            // Prefer the saved plan's matching card so recovery preserves the
            // intended card when more than one pending plan is present.
            let matchingSavedPlan = savedPlan.flatMap { plan in
                pendingPlanEntries.last(where: {
                    $0.entry.text == plan
                })?.entry.text
            }
            restoredPlan =
                Self.nonEmptyPlan(
                    referencedEntry?.text
                        ?? matchingSavedPlan
                        ?? pendingPlanEntries.last?.entry.text
                )
                ?? (
                    workflow.planApprovalEntryID == nil
                        ? nil
                        : savedPlan
                )
        }

        guard let restoredPlan = Self.nonEmptyPlan(restoredPlan) else {
            return false
        }

        if state.status == .completed,
           !pendingPlanEntries.contains(where: {
               $0.entry.text == restoredPlan
           }),
           state.entries.contains(where: {
               $0.kind == .approval
                   && $0.title == Self.workflowPlanApprovalTitle
                   && $0.text == restoredPlan
                   && $0.approvalState != nil
                   && $0.approvalState != .pending
           }) {
            return false
        }

        return ensureWorkflowPlanApproval(
            managerID,
            plan: restoredPlan,
            preferredID: workflow.planApprovalEntryID
        )
    }

    @discardableResult
    private func ensureWorkflowPlanApproval(
        _ managerID: UUID,
        plan: String,
        preferredID: UUID? = nil
    ) -> Bool {
        guard let plan = Self.nonEmptyPlan(plan),
              var workflow = managerWorkflows[managerID],
              workflow.stage == .planning,
              var state = sessions[managerID] else {
            return false
        }

        let pendingPlanEntries =
            Self.pendingWorkflowPlanApprovals(in: state)
        let approvalID: UUID
        if let preferredID,
           pendingPlanEntries.contains(where: {
               $0.entry.id == preferredID
           }) {
            approvalID = preferredID
        } else if let matchingEntry = pendingPlanEntries.last(where: {
            $0.entry.text == plan
        }) {
            approvalID = matchingEntry.entry.id
        } else if let preferredID,
                  !state.entries.contains(where: { $0.id == preferredID }) {
            approvalID = preferredID
        } else {
            approvalID = UUID()
        }

        let previousWorkflow = workflow
        let previousStatus = state.status
        let previousUnreadCompletion = state.hasUnreadCompletion
        let previousEntries = state.entries

        let selectedIndex = pendingPlanEntries.last(where: {
            $0.entry.id == approvalID
        })?.index
        for pendingEntry in pendingPlanEntries.reversed()
            where pendingEntry.index != selectedIndex {
            state.entries.remove(at: pendingEntry.index)
        }
        if let approvalIndex = state.entries.firstIndex(where: {
            $0.id == approvalID
                && Self.isPendingWorkflowPlanApproval($0)
        }) {
            state.entries[approvalIndex].text = plan
            state.entries[approvalIndex].detail =
                Self.workflowPlanApprovalDetail
        } else {
            state.entries.append(
                .init(
                    id: approvalID,
                    kind: .approval,
                    title: Self.workflowPlanApprovalTitle,
                    text: plan,
                    detail: Self.workflowPlanApprovalDetail,
                    approvalState: .pending,
                    contentFormat: .markdown
                )
            )
        }
        state.status = .needsApproval
        state.hasUnreadCompletion = false

        workflow.implementationPlan = plan
        workflow.planApprovalEntryID = approvalID
        workflow.isPaused = true
        workflow.pauseReason = Self.workflowPlanApprovalPauseReason

        let changed = workflow != previousWorkflow
            || state.status != previousStatus
            || state.hasUnreadCompletion != previousUnreadCompletion
            || state.entries != previousEntries
        if changed {
            workflow.updatedAt = .now
        }
        sessions[managerID] = state
        managerWorkflows[managerID] = workflow
        return changed
    }

    private func dispatchRevision(
        _ managerID: UUID,
        reviewSummary: String,
        reviewerID: UUID
    ) {
        guard var workflow = managerWorkflows[managerID],
              let builderID = workflow.team.builderProfileID,
              participantSessionID(
                  .builder,
                  in: workflow
              ) != nil,
              profiles.contains(where: {
                  $0.id == builderID && $0.role == .builder
              }) else {
            pauseWorkflow(
                managerID,
                reason: "The assigned Builder is no longer available."
            )
            return
        }
        let revisionRounds = workflow.revisionRounds ?? 0
        guard revisionRounds < Self.maximumRevisionRounds else {
            pauseWorkflow(
                managerID,
                reason: "The review still has outstanding findings after \(revisionRounds) revision rounds."
            )
            append(
                .init(
                    kind: .question,
                    title: "Review loop needs attention",
                    text: "The automated revision limit was reached. Review the outstanding findings and tell the team how to proceed.",
                    detail: reviewSummary
                ),
                to: managerID,
                immediately: true
            )
            return
        }
        workflow.revisionRounds = revisionRounds + 1
        workflow.reviewSummary = reviewSummary
        workflow.revisionStartedAt = .now
        workflow.updatedAt = .now
        managerWorkflows[managerID] = workflow
        queueWorkflowDispatch(
            .init(
                kind: .revision,
                sourceProfileID:
                    sessions[reviewerID]?.ownerProfileID ?? reviewerID,
                targetProfileID: builderID,
                summary: reviewSummary
            ),
            for: managerID
        )
    }

    private func beginPublishing(
        _ managerID: UUID,
        reviewSummary: String,
        reviewerID: UUID
    ) {
        guard var workflow = managerWorkflows[managerID],
              let publisherID = workflow.team.publisherProfileID,
              participantSessionID(.publisher, in: workflow) != nil,
              profiles.contains(where: {
                  $0.id == publisherID && $0.role == .publisher
              }) else {
            pauseWorkflow(
                managerID,
                reason: "The assigned Documenter / PR Writer is no longer available."
            )
            return
        }
        guard let package = workflow.latestHandoff else {
            pauseWorkflow(
                managerID,
                reason: "The verified Builder handoff is missing."
            )
            return
        }
        workflow.verificationSummary = reviewSummary
        workflow.updatedAt = .now
        managerWorkflows[managerID] = workflow
        queueWorkflowDispatch(
            .init(
                kind: .publishing,
                sourceProfileID:
                    sessions[reviewerID]?.ownerProfileID ?? reviewerID,
                targetProfileID: publisherID,
                summary: reviewSummary,
                handoff: package
            ),
            for: managerID
        )
    }

    private func completeWorkflow(
        _ managerID: UUID,
        publisherSummary: String,
        draftURL: String
    ) {
        guard var completed = transitionWorkflow(
            managerID,
            to: .completed,
            persist: false
        ) else { return }
        completed.pullRequestURL = draftURL
        completed.publisherSummary = publisherSummary
        completed.updatedAt = .now
        managerWorkflows[managerID] = completed

        let testEvidence = completed.latestHandoff.map {
            "Verification: \($0.testStatus.label) — \($0.testSummary)"
        }
        let completionEntry = TimelineEntry(
            kind: .system,
            text: "Managed workflow complete",
            detail: [
                completed.branch.map { "Branch: \($0)" },
                testEvidence,
                completed.verificationSummary.map {
                    "Reviewer: \($0)"
                },
                "Publisher: \(publisherSummary)",
                "Draft PR: \(draftURL)"
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
        )
        var managerSession = sessions[managerID] ?? AgentSessionState()
        managerSession.status = .completed
        managerSession.entries.append(completionEntry)
        sessions[managerID] = managerSession
        save(immediately: true)
        workflowStageStartedAt[managerID] = nil
        let elapsedMilliseconds = Int64(
            Date.now.timeIntervalSince(completed.startedAt) * 1_000
        )
        PerformanceMetrics.record(
            name: .workflowTotal,
            duration: .milliseconds(max(0, elapsedMilliseconds)),
            profile: profiles.first(where: { $0.id == managerID }),
            stage: .completed
        )
    }

    private func requestWorkflowPlanApproval(
        _ managerID: UUID,
        implementationPlan: String,
        replacingAssistantEntryID assistantEntryID: UUID
    ) {
        guard var workflow = managerWorkflows[managerID],
              workflow.stage == .planning,
              var state = sessions[managerID],
              let entryIndex = state.entries.firstIndex(where: {
                  $0.id == assistantEntryID && $0.kind == .assistant
              }) else {
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

        let previousStatus = state.status
        state.status = .needsApproval
        state.hasUnreadCompletion = false
        let assistantTimestamp = state.entries[entryIndex].timestamp
        state.entries.remove(at: entryIndex)
        state.entries.insert(
            .init(
                id: approvalID,
                kind: .approval,
                title: "Approve implementation plan",
                text: implementationPlan,
                detail: "Approve to hand this plan to the Builder and continue the managed workflow. Decline to pause and send revision feedback.",
                timestamp: assistantTimestamp,
                approvalState: .pending,
                contentFormat: .markdown
            ),
            at: entryIndex
        )

        sessions[managerID] = state
        managerWorkflows[managerID] = workflow
        save(immediately: true)

        if notificationsArePrepared,
           let notice = AgentAttentionNotice.transition(
               from: previousStatus,
               to: .needsApproval
           ),
           let ownerID = sessions[managerID]?.ownerProfileID,
           let manager = profiles.first(where: { $0.id == ownerID }),
           !isAppWindowActive() {
            notifications?.post(notice, for: manager)
        }
    }

    private func dispatchInitialBuild(
        workflow: ManagerWorkflow,
        handoff: BuilderImplementationHandoff,
        to builderID: UUID
    ) async {
        let managerSessionID =
            workflow.participantSessionIDs[.manager]
                ?? workflow.managerProfileID
        guard let currentWorkflow = managerWorkflows[managerSessionID],
              currentWorkflow.stage == .building,
              currentWorkflow.approvedPlanEntryID
                == handoff.approvalEntryID,
              currentWorkflow.implementationPlan == handoff.approvedPlan,
              sessions[managerSessionID]?.entries.contains(where: {
                  $0.id == handoff.approvalEntryID
                      && $0.kind == .approval
                      && $0.approvalState == .approved
                      && $0.text == handoff.approvedPlan
              }) == true else {
            pauseWorkflow(
                managerSessionID,
                reason: "The approved implementation plan is missing or inconsistent. The Builder was not dispatched."
            )
            return
        }

        guard let builderSessionID = participantSessionID(.builder, in: workflow) else {
            pauseWorkflow(
                managerSessionID,
                reason: "The assigned Builder session is no longer available."
            )
            return
        }
        guard await resetWorkflowRecipient(
            builderID,
            sessionID: builderSessionID,
            worktreeSeedID: workflow.id
        ) else {
            pauseWorkflow(
                workflow.participantSessionIDs[.manager] ?? workflow.managerProfileID,
                reason: "The assigned Builder is no longer available."
            )
            return
        }
        append(
            handoff.visibleEntry(
                sourceName: profileNameForSession(managerSessionID)
            ),
            to: builderSessionID
        )
        performSend(
            handoff.runtimeMessage,
            to: builderID,
            sessionID: builderSessionID
        )
    }

    private func dispatchBuilderHandoff(
        workflow: ManagerWorkflow,
        builderSessionID: UUID,
        reviewerProfileID: UUID,
        reviewerSessionID: UUID,
        instruction: String,
        pass: BuilderHandoffPass = .initial,
        resetRecipient: Bool = true
    ) async {
        let managerSessionID =
            workflow.participantSessionIDs[.manager] ?? workflow.managerProfileID
        guard let builderProfileID = sessions[builderSessionID]?.ownerProfileID,
              var builder = profiles.first(where: { $0.id == builderProfileID }),
              let builderSession = sessions[builderSessionID] else {
            pauseWorkflow(
                managerSessionID,
                reason: "The assigned Builder is no longer available."
            )
            return
        }
        builder.worktree = builderSession.worktree
        do {
            let startedAt = ContinuousClock.now
            var package = try await worktrees.makeHandoff(
                from: builder,
                session: builderSession
            )
            PerformanceMetrics.record(
                name: .handoffPreparation,
                duration: startedAt.duration(to: .now),
                profile: builder,
                stage: workflow.stage
            )
            package.taskContext =
                workflow.implementationPlan ?? workflow.request
            let previousRevision =
                workflow.latestHandoff?.headRevision ?? package.baseRevision
            let lacksRequiredCommit =
                package.headRevision == previousRevision
            let hasUncommittedChanges =
                package.workingTreeSummary != "Clean"
            let hasInvalidTests: Bool
            switch pass {
            case .initial:
                hasInvalidTests = package.testStatus == .failed
            case .revision:
                guard let testEvidenceAt = package.testEvidenceAt,
                      let revisionStartedAt = workflow.revisionStartedAt else {
                    hasInvalidTests = true
                    break
                }
                hasInvalidTests =
                    package.testStatus != .passed
                        || testEvidenceAt < revisionStartedAt
            }
            guard !lacksRequiredCommit,
                  !hasUncommittedChanges,
                  !hasInvalidTests else {
                _ = transitionWorkflow(
                    managerSessionID,
                    to: pass.fallbackStage
                )
                let reason: String
                if lacksRequiredCommit {
                    reason =
                        pass == .initial
                            ? "The Builder handoff has no local commit."
                            : "The Builder revision pass has no new local commit."
                } else if hasUncommittedChanges {
                    reason = "The Builder handoff still has uncommitted changes."
                } else if pass == .initial {
                    reason = "The Builder reported failing tests."
                } else {
                    reason =
                        "The Builder handoff does not report passing tests from the revision pass."
                }
                pauseWorkflow(managerSessionID, reason: reason)
                append(
                    .init(
                        kind: .question,
                        title: "Builder handoff is not ready",
                        text: "\(reason) Ask this bot to finish the work, run the required tests, and commit any changes."
                    ),
                    to: builderSessionID
                )
                return
            }
            record(package, for: managerSessionID)
            if resetRecipient {
                guard await resetWorkflowRecipient(
                    reviewerProfileID,
                    sessionID: reviewerSessionID,
                    handoff: package
                ) else {
                    pauseWorkflow(
                        managerSessionID,
                        reason: "The assigned Reviewer is no longer available."
                    )
                    return
                }
            } else {
                attach(
                    package,
                    from: builderSessionID,
                    to: reviewerSessionID,
                    title: "Updated implementation"
                )
            }
            performSend(
                instruction,
                to: reviewerProfileID,
                sessionID: reviewerSessionID
            )
        } catch {
            pauseWorkflow(
                managerSessionID,
                reason: "Could not prepare the Builder handoff: \(error.localizedDescription)"
            )
        }
    }

    private func queueWorkflowDispatch(
        _ dispatch: ManagerWorkflowDispatch,
        for managerID: UUID,
        pullRequestURL: String? = nil
    ) {
        guard var workflow = managerWorkflows[managerID],
              workflow.pendingDispatch == nil else {
            return
        }

        workflow.stage = dispatch.kind.stage
        workflow.pendingDispatch = dispatch
        workflow.isPaused = false
        workflow.pauseReason = nil
        workflow.resumeAvailableAfterRestart = false
        workflow.pullRequestURL = pullRequestURL ?? workflow.pullRequestURL
        workflow.updatedAt = .now
        managerWorkflows[managerID] = workflow
        save()
        beginPendingWorkflowDispatch(for: managerID)
    }

    private func beginPendingWorkflowDispatch(for managerID: UUID) {
        guard let workflow = managerWorkflows[managerID],
              let dispatch = workflow.pendingDispatch,
              workflow.stage == dispatch.kind.stage,
              workflow.deliveredDispatchID != dispatch.id,
              !workflowDispatchesInFlight.contains(dispatch.id) else {
            return
        }

        workflowDispatchesInFlight.insert(dispatch.id)
        Task { [weak self] in
            guard let self else { return }
            await flushPersistence()
            await processPendingWorkflowDispatch(
                managerID: managerID,
                dispatchID: dispatch.id
            )
            workflowDispatchesInFlight.remove(dispatch.id)
        }
    }

    private func processPendingWorkflowDispatch(
        managerID: UUID,
        dispatchID: UUID
    ) async {
        guard var workflow = managerWorkflows[managerID],
              var dispatch = workflow.pendingDispatch,
              dispatch.id == dispatchID,
              workflow.stage == dispatch.kind.stage,
              let targetSessionID = workflowDispatchTargetSessionID(
                  for: dispatch,
                  workflow: workflow
              ) else {
            return
        }

        do {
            switch dispatch.kind {
            case .initialBuild:
                guard let approvalEntryID = workflow.approvedPlanEntryID,
                      let approvedPlan = workflow.implementationPlan,
                      sessions[managerID]?.entries.contains(where: {
                          $0.id == approvalEntryID
                              && $0.kind == .approval
                              && $0.approvalState == .approved
                              && $0.text == approvedPlan
                      }) == true else {
                    pauseWorkflow(
                        managerID,
                        reason: "The approved implementation plan is missing or inconsistent. The Builder was not dispatched."
                    )
                    return
                }
                guard await resetWorkflowRecipient(
                    dispatch.targetProfileID,
                    sessionID: targetSessionID,
                    worktreeSeedID: workflow.id
                ) else {
                    pauseWorkflow(
                        managerID,
                        reason: "The assigned Builder is no longer available."
                    )
                    return
                }

            case .initialReview, .verification:
                if dispatch.handoff == nil {
                    guard let builderSessionID = participantSessionID(
                        .builder,
                        in: workflow
                    ),
                    let builderProfileID =
                        sessions[builderSessionID]?.ownerProfileID,
                    var builder = profiles.first(where: {
                        $0.id == builderProfileID
                    }),
                    let builderSession = sessions[builderSessionID] else {
                        pauseWorkflow(
                            managerID,
                            reason: "The assigned Builder is no longer available."
                        )
                        return
                    }
                    builder.worktree = builderSession.worktree
                    var package = try await worktrees.makeHandoff(
                        from: builder,
                        session: builderSession
                    )
                    package.taskContext =
                        workflow.implementationPlan ?? workflow.request
                    guard validate(
                        package,
                        for: dispatch,
                        workflow: workflow,
                        managerID: managerID
                    ) else {
                        return
                    }
                    guard persist(
                        package,
                        for: managerID,
                        dispatchID: dispatchID
                    ) else {
                        return
                    }
                    dispatch.handoff = package
                    workflow = managerWorkflows[managerID] ?? workflow
                }

                guard let package = dispatch.handoff else { return }
                if dispatch.kind == .initialReview {
                    guard await resetWorkflowRecipient(
                        dispatch.targetProfileID,
                        sessionID: targetSessionID,
                        handoff: package
                    ) else {
                        pauseWorkflow(
                            managerID,
                            reason: "The assigned Reviewer is no longer available."
                        )
                        return
                    }
                } else {
                    guard prepareWorkflowHandoff(
                        package,
                        for: dispatch.targetProfileID,
                        sessionID: targetSessionID
                    ) else {
                        pauseWorkflow(
                            managerID,
                            reason: "The assigned Reviewer is no longer available."
                        )
                        return
                    }
                }

            case .publishing:
                guard let package = dispatch.handoff,
                      await resetWorkflowRecipient(
                          dispatch.targetProfileID,
                          sessionID: targetSessionID,
                          handoff: package
                      ) else {
                    pauseWorkflow(
                        managerID,
                        reason: "The assigned Documenter / PR Writer is no longer available."
                    )
                    return
                }

            case .revision, .reporting:
                guard profiles.contains(where: {
                    $0.id == dispatch.targetProfileID
                }) else {
                    pauseWorkflow(
                        managerID,
                        reason: "The assigned workflow recipient is no longer available."
                    )
                    return
                }
            }
        } catch {
            pauseWorkflow(
                managerID,
                reason: "Could not prepare the workflow handoff: \(error.localizedDescription)"
            )
            return
        }

        guard var currentWorkflow = managerWorkflows[managerID],
              let currentDispatch = currentWorkflow.pendingDispatch,
              currentDispatch.id == dispatchID,
              currentWorkflow.stage == currentDispatch.kind.stage,
              currentWorkflow.deliveredDispatchID != dispatchID else {
            return
        }

        guard let currentTargetSessionID = workflowDispatchTargetSessionID(
            for: currentDispatch,
            workflow: currentWorkflow
        ) else {
            pauseWorkflow(
                managerID,
                reason: "The assigned workflow recipient session is no longer available."
            )
            return
        }
        var targetState =
            sessions[currentTargetSessionID]
                ?? AgentSessionState(
                    id: currentTargetSessionID,
                    ownerProfileID: currentDispatch.targetProfileID
                )
        if !targetState.entries.contains(where: { $0.id == dispatchID }) {
            targetState.entries.append(
                timelineEntry(
                    for: currentDispatch,
                    workflow: currentWorkflow
                )
            )
        }
        currentWorkflow.pendingDispatch = nil
        currentWorkflow.deliveredDispatchID = dispatchID
        currentWorkflow.deliveredDispatch = currentDispatch
        currentWorkflow.resumeAvailableAfterRestart = false
        currentWorkflow.isPaused = false
        currentWorkflow.pauseReason = nil
        currentWorkflow.updatedAt = .now
        sessions[currentTargetSessionID] = targetState
        managerWorkflows[managerID] = currentWorkflow
        await flushPersistence()

        performSend(
            runtimeInstruction(
                for: currentDispatch,
                workflow: currentWorkflow
            ),
            to: currentDispatch.targetProfileID,
            sessionID: currentTargetSessionID
        )
    }

    private func workflowDispatchTargetSessionID(
        for dispatch: ManagerWorkflowDispatch,
        workflow: ManagerWorkflow
    ) -> UUID? {
        let role: AgentRole
        switch dispatch.kind {
        case .initialBuild, .revision:
            role = .builder
        case .initialReview, .verification:
            role = .reviewer
        case .publishing:
            role = .publisher
        case .reporting:
            role = .manager
        }
        guard let sessionID = participantSessionID(role, in: workflow),
              sessions[sessionID]?.ownerProfileID
                == dispatch.targetProfileID
                || sessionID == dispatch.targetProfileID else {
            return nil
        }
        return sessionID
    }

    private func initialBuilderInstruction(
        for workflow: ManagerWorkflow
    ) -> String {
        """
        You are the Builder in a managed bl00p workflow.

        Original request:
        \(workflow.request)

        Manager brief:
        \(workflow.implementationPlan ?? "No implementation plan was captured.")

        Implement the requested change in your isolated worktree. Keep the change focused, run the relevant tests, and create a local commit before finishing so the Reviewer can inspect an immutable HEAD. Do not push or open a pull request.
        """
    }

    private func resumeInstruction(for workflow: ManagerWorkflow) -> String {
        switch workflow.stage {
        case .planning:
            return "Resume the read-only planning work for this request and present an updated implementation plan."
        case .building:
            return """
            Resume the managed Builder task after the app restart.

            \(initialBuilderInstruction(for: workflow))

            Inspect the existing worktree first and continue from any work already present. Do not start over or duplicate completed changes.
            """
        case .reviewing:
            return "Resume the read-only review of the committed implementation for “\(workflow.request)”. Do not edit code."
        case .revising:
            return "Resume addressing the review findings for “\(workflow.request)” in the existing worktree. Run tests and commit the finished fixes locally; do not push."
        case .verifying:
            return "Resume the read-only verification pass for “\(workflow.request)”. Confirm the earlier findings are resolved; do not edit code."
        case .publishing:
            return "Resume documentation, final verification, and draft pull-request preparation for “\(workflow.request)”. Respect every approval request surfaced by bl00p."
        case .reporting:
            return "Resume the final read-only delivery report for “\(workflow.request)”. Report the branch, verification, draft pull-request URL, and remaining caveats without modifying the repository."
        case .completed:
            return ""
        }
    }

    private func validate(
        _ package: GitHandoffPackage,
        for dispatch: ManagerWorkflowDispatch,
        workflow: ManagerWorkflow,
        managerID: UUID
    ) -> Bool {
        let previousRevision =
            workflow.latestHandoff?.headRevision ?? package.baseRevision
        let lacksRequiredCommit =
            package.headRevision == previousRevision
        let hasUncommittedChanges = package.workingTreeSummary != "Clean"
        let hasInvalidTests: Bool
        if dispatch.kind == .verification {
            if let testEvidenceAt = package.testEvidenceAt,
               let revisionStartedAt = workflow.revisionStartedAt {
                hasInvalidTests =
                    package.testStatus != .passed
                        || testEvidenceAt < revisionStartedAt
            } else {
                hasInvalidTests = true
            }
        } else {
            hasInvalidTests = package.testStatus == .failed
        }
        guard !lacksRequiredCommit,
              !hasUncommittedChanges,
              !hasInvalidTests else {
            let fallbackStage: ManagerWorkflowStage =
                dispatch.kind == .initialReview ? .building : .revising
            let reason: String
            if lacksRequiredCommit {
                reason =
                    dispatch.kind == .initialReview
                        ? "The Builder handoff has no local commit."
                        : "The Builder revision pass has no new local commit."
            } else if hasUncommittedChanges {
                reason = "The Builder handoff still has uncommitted changes."
            } else if dispatch.kind == .initialReview {
                reason = "The Builder reported failing tests."
            } else {
                reason =
                    "The Builder handoff does not report passing tests from the revision pass."
            }
            return rejectWorkflowHandoff(
                dispatch: dispatch,
                managerID: managerID,
                fallbackStage: fallbackStage,
                reason: reason
            )
        }
        return true
    }

    private func rejectWorkflowHandoff(
        dispatch: ManagerWorkflowDispatch,
        managerID: UUID,
        fallbackStage: ManagerWorkflowStage,
        reason: String
    ) -> Bool {
        guard var current = managerWorkflows[managerID],
              current.pendingDispatch?.id == dispatch.id else {
            return false
        }
        current.pendingDispatch = nil
        current.stage = fallbackStage
        current.updatedAt = .now
        managerWorkflows[managerID] = current
        save()
        pauseWorkflow(managerID, reason: reason)
        append(
            .init(
                kind: .question,
                title: "Builder handoff is not ready",
                text: "\(reason) Ask this bot to finish the work, run the required tests, and create a local commit."
            ),
            to: participantSessionID(.builder, in: current)
                ?? dispatch.sourceProfileID
        )
        return false
    }

    private func persist(
        _ package: GitHandoffPackage,
        for managerID: UUID,
        dispatchID: UUID
    ) -> Bool {
        guard var workflow = managerWorkflows[managerID],
              var dispatch = workflow.pendingDispatch,
              dispatch.id == dispatchID else {
            return false
        }
        dispatch.handoff = package
        workflow.pendingDispatch = dispatch
        workflow.latestHandoff = package
        workflow.branch = package.branch
        workflow.updatedAt = .now
        managerWorkflows[managerID] = workflow
        save()
        return true
    }

    private func prepareWorkflowHandoff(
        _ package: GitHandoffPackage,
        for profileID: UUID,
        sessionID: UUID
    ) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }),
              sessions[sessionID]?.ownerProfileID == profileID
                || sessionID == profileID else {
            return false
        }
        profiles[index].workingDirectory =
            profiles[index].role == .builder
                ? package.repositoryPath
                : package.worktreePath
        if profiles[index].role == .builder {
            profiles[index].worktree = nil
        }
        var state =
            sessions[sessionID]
                ?? AgentSessionState(
                    id: sessionID,
                    ownerProfileID: profileID
                )
        state.pendingHandoff = package
        sessions[sessionID] = state
        save()
        return true
    }

    private func timelineEntry(
        for dispatch: ManagerWorkflowDispatch,
        workflow: ManagerWorkflow
    ) -> TimelineEntry {
        switch dispatch.kind {
        case .initialBuild:
            return .init(
                id: dispatch.id,
                kind: .handoff,
                title: "Implementation brief",
                text: workflow.implementationPlan ?? dispatch.summary,
                detail: """
                Original request:
                \(workflow.request)

                From \(profileName(dispatch.sourceProfileID))
                """
            )
        case .initialReview:
            return .init(
                id: dispatch.id,
                kind: .handoff,
                title: "Workflow handoff from \(profileName(dispatch.sourceProfileID))",
                text: workflow.request,
                detail: dispatch.handoff?.timelineDetail
            )
        case .revision:
            return .init(
                id: dispatch.id,
                kind: .handoff,
                title: "Review findings",
                text: dispatch.summary,
                detail: "From \(profileName(dispatch.sourceProfileID))"
            )
        case .verification:
            return .init(
                id: dispatch.id,
                kind: .handoff,
                title: "Updated implementation",
                text: "From \(profileName(dispatch.sourceProfileID))",
                detail: dispatch.handoff?.timelineDetail
            )
        case .publishing:
            return .init(
                id: dispatch.id,
                kind: .handoff,
                title: "Workflow handoff from \(profileName(dispatch.sourceProfileID))",
                text: workflow.request,
                detail: dispatch.handoff?.timelineDetail
            )
        case .reporting:
            return .init(
                id: dispatch.id,
                kind: .handoff,
                title: "Delivery prepared",
                text: dispatch.summary,
                detail: "From \(profileName(dispatch.sourceProfileID))"
            )
        }
    }

    private func dispatchPublishing(
        workflow: ManagerWorkflow,
        reviewSummary: String,
        reviewerSessionID: UUID,
        publisherProfileID: UUID,
        publisherSessionID: UUID
    ) async {
        let managerSessionID =
            workflow.participantSessionIDs[.manager] ?? workflow.managerProfileID
        guard let package = managerWorkflows[
            managerSessionID
        ]?.latestHandoff else {
            pauseWorkflow(
                managerSessionID,
                reason: "The verified Builder handoff is missing."
            )
            return
        }
        guard await resetWorkflowRecipient(
            publisherProfileID,
            sessionID: publisherSessionID,
            handoff: package,
            sourceProfileID: sessions[reviewerSessionID]?.ownerProfileID
        ) else {
            pauseWorkflow(
                managerSessionID,
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
            to: publisherProfileID,
            sessionID: publisherSessionID
        )
    }

    private func runtimeInstruction(
        for dispatch: ManagerWorkflowDispatch,
        workflow: ManagerWorkflow
    ) -> String {
        switch dispatch.kind {
        case .initialBuild:
            if let approvalEntryID = workflow.approvedPlanEntryID,
               let approvedPlan = workflow.implementationPlan {
                BuilderImplementationHandoff(
                    approvalEntryID: approvalEntryID,
                    originalRequest: workflow.request,
                    approvedPlan: approvedPlan
                ).runtimeMessage
            } else {
                initialBuilderInstruction(for: workflow)
            }
        case .initialReview:
            Self.initialReviewInstruction
        case .revision:
            """
            The reviewer requested changes, or did not return a valid structured disposition. Treat this conservatively as changes requested.

            \(dispatch.summary)

            Address every actionable finding in your existing worktree. If the disposition was missing or malformed, inspect the review carefully and verify the implementation again. Run the relevant tests, commit any fixes locally, and finish with a concise summary. Do not push or open a pull request.
            """
        case .verification:
            Self.verificationInstruction
        case .publishing:
            """
            You are the Documenter / PR Writer in a managed bl00p workflow.

            Final reviewer result:
            \(dispatch.summary)

            Update the relevant user-facing and developer documentation for the completed change. Run final verification, commit all completed work on the current branch, push that branch, and create a draft pull request. Respect every approval request surfaced by bl00p. Finish with a concise summary containing the branch, tests, and the full draft PR URL.
            """
        case .reporting:
            """
            The documenter and PR writer completed the delivery pass.

            \(dispatch.summary)

            Notify the user that the workflow is complete. Include the clickable draft pull-request URL, the branch, verification performed, and any remaining caveats. Do not modify the repository.
            """
        }
    }

    private func resetWorkflowRecipient(
        _ profileID: UUID,
        sessionID: UUID,
        handoff: GitHandoffPackage? = nil,
        sourceProfileID: UUID? = nil,
        worktreeSeedID: UUID? = nil
    ) async -> Bool {
        guard let profile = profiles.first(
            where: { $0.id == profileID }
        ) else { return false }

        guard sessions[sessionID]?.ownerProfileID == profileID
                || sessionID == profileID else { return false }
        connectedProfileIDs.remove(sessionID)
        launchedProfileIDs.remove(profileID)
        planningTurnAssistantEntryIDs.removeValue(forKey: sessionID)
        runGenerations[sessionID] = UUID()
        await runtime.stop(
            profile: runtimeProfile(for: profile, sessionID: sessionID)
        )

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

        guard var state = sessions[sessionID] else { return false }
        state.status = .stopped
        state.sessionID = nil
        state.codexTurnModeVersion = nil
        state.pendingHandoff = handoff
        state.worktreeSeedID = worktreeSeedID
        if worktreeSeedID != nil || handoff != nil {
            state.worktree = nil
        }
        if let handoff {
            let sourceName = profileName(
                sourceProfileID ?? handoff.sourceProfileID
            )
            state.entries.append(
                .init(
                    kind: .handoff,
                    title: "Workflow handoff from \(sourceName)",
                    text: handoff.taskContext,
                    detail: handoff.timelineDetail
                )
            )
        }
        sessions[sessionID] = state
        save(immediately: true)
        return true
    }

    private func attach(
        _ package: GitHandoffPackage,
        from sourceProfileID: UUID,
        to targetProfileID: UUID,
        title: String
    ) {
        guard var state = sessions[targetProfileID] else { return }
        state.pendingHandoff = package
        state.entries.append(
            .init(
                kind: .handoff,
                title: title,
                text: package.taskContext,
                detail: package.timelineDetail
            )
        )
        sessions[targetProfileID] = state
        save(immediately: true)
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
        targetSessionID: UUID,
        title: String,
        visibleText: String,
        runtimeMessage: String
    ) {
        append(
            .init(
                kind: .handoff,
                title: title,
                text: visibleText,
                detail: "From \(profileNameForSession(sourceProfileID))"
            ),
            to: targetSessionID
        )
        performSend(
            runtimeMessage,
            to: targetProfileID,
            sessionID: targetSessionID
        )
    }

    private func latestAssistantResponse(
        for profileID: UUID
    ) -> String? {
        sessions[profileID]?.entries
            .last(where: {
                $0.kind == .assistant
                    && !$0.text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
            })?
            .text
    }

    private struct ReviewOutput {
        let disposition: ReviewDisposition?
        let summary: String
    }

    private func latestReviewOutput(for profileID: UUID) -> ReviewOutput {
        let entries = sessions[profileID]?.entries ?? []
        let startIndex = min(
            turnEntryStartIndices[profileID] ?? 0,
            entries.count
        )
        let response = entries[startIndex...]
            .filter { $0.kind == .assistant && !$0.text.isEmpty }
            .map(\.text)
            .joined(separator: "\n\n")
        let summary = ReviewDisposition.removingProtocolLines(from: response)
        return ReviewOutput(
            disposition: ReviewDisposition.parse(from: response),
            summary: summary.isEmpty
                ? "No reviewer summary was captured."
                : summary
        )
    }

    private func latestAssistantEntry(for profileID: UUID) -> TimelineEntry? {
        sessions[profileID]?.entries.last(where: {
            $0.kind == .assistant && !$0.text.isEmpty
        })
    }

    private func latestAssistantText(for profileID: UUID) -> String {
        guard let entries = sessions[profileID]?.entries else {
            return "No assistant summary was captured."
        }
        let boundary = entries.lastIndex(where: {
            $0.kind == .user || $0.kind == .handoff
        })
        let turnEntries = boundary.map {
            entries[entries.index(after: $0)...]
        } ?? entries[...]
        let messages = turnEntries.compactMap { entry -> String? in
            guard entry.kind == .assistant else { return nil }
            let text = entry.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return text.isEmpty ? nil : text
        }
        return messages.isEmpty
            ? "No assistant summary was captured."
            : messages.joined(separator: "\n\n")
    }

    private func profileName(_ profileID: UUID) -> String {
        profiles.first(where: { $0.id == profileID })?.name ?? "Assigned bot"
    }

    private func profileNameForSession(_ sessionID: UUID) -> String {
        guard let ownerID = sessions[sessionID]?.ownerProfileID else {
            return profileName(sessionID)
        }
        return profileName(ownerID)
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

    End the final response with exactly one machine-readable line:
    BL00P_REVIEW_DISPOSITION: clean
    or:
    BL00P_REVIEW_DISPOSITION: changesRequested
    """

    private static let maximumRevisionRounds = 2

    private static let verificationInstruction = """
    Re-check the updated committed implementation at the attached branch and HEAD. Confirm that every earlier finding is resolved and that the reported tests support the change. Do not edit code. Return any remaining actionable findings, or state clearly that the change is ready for documentation and publishing.

    End the final response with exactly one machine-readable line:
    BL00P_REVIEW_DISPOSITION: clean
    or:
    BL00P_REVIEW_DISPOSITION: changesRequested
    """

    private enum BuilderHandoffPass {
        case initial
        case revision

        var fallbackStage: ManagerWorkflowStage {
            switch self {
            case .initial: .building
            case .revision: .revising
            }
        }
    }

    private func apply(_ event: AgentEvent, to profileID: UUID) {
        guard var state = sessions[profileID] else { return }
        let ownerProfileID = state.ownerProfileID ?? profileID
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
                launchedProfileIDs.remove(profileID)
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
                    selectedBotID != ownerProfileID
                        || selectedSessionID(for: ownerProfileID) != profileID
                        || !AppWindowActivity.isActive
            }
        case .entry(let entry):
            state.entries.append(entry)
            if entry.kind == .assistant,
               planningTurnAssistantEntryIDs[profileID] != nil {
                planningTurnAssistantEntryIDs[profileID]?.insert(entry.id)
            }
            if state.title == "New chat", entry.kind == .user {
                state.title = Self.sessionTitle(from: entry.text)
            }
        case .upsertEntry(let entry):
            if let index = state.entries.firstIndex(where: { $0.id == entry.id }) {
                state.entries[index] = entry
            } else {
                state.entries.append(entry)
            }
            if entry.kind == .assistant,
               planningTurnAssistantEntryIDs[profileID] != nil {
                planningTurnAssistantEntryIDs[profileID]?.insert(entry.id)
            }
        case .approvalResolved(let entryID, let approvalState):
            if let index = state.entries.firstIndex(where: { $0.id == entryID }) {
                state.entries[index].approvalState = approvalState
            }
        case .sessionID(let sessionID):
            state.sessionID = sessionID
            if profiles.first(where: { $0.id == ownerProfileID })?.provider == .codex {
                state.codexTurnModeVersion = CodexThreadConfiguration.turnModeVersion
            }
            connectedProfileIDs.insert(profileID)
        }

        state.updatedAt = .now
        sessions[profileID] = state
        let requiresImmediatePersistence: Bool
        switch event {
        case .status(let status):
            requiresImmediatePersistence =
                status == .needsApproval
                    || status == .needsAnswer
                    || status == .completed
                    || status == .failed
                    || status == .stopped
        case .approvalResolved:
            requiresImmediatePersistence = true
        case .entry, .upsertEntry, .sessionID:
            requiresImmediatePersistence = false
        }
        save(immediately: requiresImmediatePersistence)
        if notificationsArePrepared,
           let notice,
           let profile = profiles.first(where: { $0.id == ownerProfileID }),
           !isAppWindowActive() {
            notifications?.post(notice, for: profile)
        }
        if let statusTransition {
            handleWorkflowStatus(
                for: profileID,
                from: statusTransition.from,
                to: statusTransition.to
            )
            if statusTransition.to == .completed
                || statusTransition.to == .failed
                || statusTransition.to == .stopped {
                turnEntryStartIndices.removeValue(forKey: profileID)
            }
        }
    }

    private func append(
        _ entry: TimelineEntry,
        to profileID: UUID,
        immediately: Bool = false
    ) {
        guard var state = sessions[profileID] else { return }
        state.entries.append(entry)
        state.updatedAt = .now
        sessions[profileID] = state
        save(immediately: immediately)
    }

    private func save(immediately: Bool = false) {
        persistenceRevision &+= 1
        store.enqueue(
            persistedState(),
            revision: persistenceRevision,
            immediately: immediately
        )
        syncDockBadge()
    }

    private func persistedState() -> PersistedAppState {
        PersistedAppState(
            profiles: profiles,
            sessions: sessions,
            selectedBotID: selectedBotID,
            managerWorkflows: managerWorkflows,
            sessionOrder: sessionOrder,
            selectedSessionIDs: selectedSessionIDs
        )
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

    static func sessionTitle(from message: String) -> String {
        let singleLine = message
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return "New chat" }
        let limit = 36
        guard singleLine.count > limit else { return singleLine }
        return String(singleLine.prefix(limit - 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            + "…"
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

    private static func migrateLegacyPlanApprovalEntry(
        _ entry: TimelineEntry
    ) -> TimelineEntry {
        guard entry.kind == .approval,
              entry.title == "Approve implementation plan",
              entry.contentFormat == nil else {
            return entry
        }
        var migrated = entry
        migrated.contentFormat = .markdown
        return migrated
    }
}

final class AppStateStore: Sendable {
    let fileURL: URL?
    private let persistence: AppStatePersistenceQueue
    private let logger = Bl00pLogger(subsystem: "dev.bl00p.app", category: "persistence")

    init(
        fileURL: URL? = nil,
        writer: (any PersistedStateWriting)? = nil,
        scheduler: any PersistenceScheduling = ContinuousPersistenceScheduler(),
        coalescingDelay: Duration = .milliseconds(150)
    ) {
        let resolvedURL: URL?
        if let fileURL {
            resolvedURL = fileURL
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            resolvedURL = base?
                .appendingPathComponent("bl00p", isDirectory: true)
                .appendingPathComponent("state.json", isDirectory: false)
        }
        self.fileURL = resolvedURL
        persistence = AppStatePersistenceQueue(
            writer: writer ?? FilePersistedStateWriter(fileURL: resolvedURL),
            scheduler: scheduler,
            coalescingDelay: coalescingDelay
        )
    }

    /// A previously-saved state that fails to decode (e.g. after a schema change) is
    /// moved aside instead of silently discarded. The last known-good backup is then
    /// loaded so a decode or interrupted-write failure cannot reset the app to defaults.
    func load() -> PersistedAppState? {
        guard let fileURL else { return nil }
        let backupURL = backupURL(for: fileURL)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                return try decodeState(at: fileURL)
            } catch {
                logger.error("Failed to decode saved state, quarantining it: \(error)")
                quarantineUnreadableState(at: fileURL)
            }
        }

        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            return nil
        }
        do {
            return try decodeState(at: backupURL)
        } catch {
            logger.error("Failed to decode backup state: \(error)")
            return nil
        }
    }

    func enqueue(
        _ state: PersistedAppState,
        revision: UInt64,
        immediately: Bool
    ) {
        let persistence = persistence
        Task {
            if immediately {
                await persistence.flush(state, revision: revision)
            } else {
                await persistence.enqueue(state, revision: revision)
            }
        }
    }

    /// Writes immediately for migrations, fixtures, and other synchronous
    /// boundaries while retaining the backup behavior used by queued writes.
    func save(_ state: PersistedAppState) {
        guard let fileURL,
              let data = try? JSONEncoder.compactState.encode(state) else {
            return
        }
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        let backupURL = backupURL(for: fileURL)
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: fileURL.path) {
                let previousData = try Data(contentsOf: fileURL)
                try previousData.write(to: backupURL, options: .atomic)
            }
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save state: \(error)")
        }
    }

    func flush(
        _ state: PersistedAppState,
        revision: UInt64
    ) async {
        await persistence.flush(state, revision: revision)
    }

    private func decodeState(at url: URL) throws -> PersistedAppState {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.iso8601.decode(PersistedAppState.self, from: data)
    }

    private func backupURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).bak")
    }

    private func quarantineUnreadableState(at fileURL: URL) {
        let timestamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let quarantineURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("state.corrupt-\(timestamp).json")
        do {
            try FileManager.default.removeItemIfPresent(at: quarantineURL)
            try FileManager.default.moveItem(at: fileURL, to: quarantineURL)
        } catch {
            logger.error("Failed to quarantine unreadable state: \(error)")
        }
    }
}

private extension FileManager {
    func removeItemIfPresent(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
