import AppKit
import Foundation
import SwiftUI
import os

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
    private var planningTurnAssistantEntryIDs: [UUID: Set<UUID>] = [:]
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
            sessions = Dictionary(
                uniqueKeysWithValues: saved.sessions.map { profileID, restoredSession in
                    var session = restoredSession
                    session.entries = session.entries
                        .map(Self.migrateLegacyPermissionEntry)
                        .map(Self.migrateLegacyPlanApprovalEntry)
                    session.entries.removeAll(where: Self.isPrototypeStarterEntry)
                    if legacyPermissionBoundaryProfileIDs.contains(profileID)
                        && session.status == .completed {
                        session.status = .needsAnswer
                    }
                    if codexProfileIDs.contains(profileID),
                       session.codexTurnModeVersion != CodexThreadConfiguration.turnModeVersion {
                        session.sessionID = nil
                        let canRecoverPlanApproval =
                            recoverablePlanningManagerIDs.contains(profileID)
                        if !canRecoverPlanApproval {
                            session.status = .stopped
                        }
                    }
                    return (profileID, session)
                }
            )
            managerWorkflows = saved.managerWorkflows
            selectedBotID = saved.selectedBotID ?? saved.profiles.first?.id
            let recoveredPlanApproval = reconcileRestoredWorkflowPlanApprovals()
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
                uniqueKeysWithValues: sessions.map { profileID, restoredSession in
                    var session = restoredSession
                    if session.status == .launching
                        || session.status == .working
                        || session.status == .needsApproval
                        || session.status == .needsAnswer {
                        let preservesLegacyAttention =
                            session.status == .needsAnswer
                            && legacyPermissionBoundaryProfileIDs.contains(
                                profileID
                            )
                        session.status =
                            preservesLegacyAttention
                                || (session.status == .needsApproval
                                    && pendingPlanApprovalManagerIDs.contains(
                                        profileID
                                    ))
                                ? session.status
                                : .stopped
                    }
                    return (profileID, session)
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
                restored.pauseReason =
                    workflow.planApprovalEntryID == nil
                        ? "Ready to resume after the app restart."
                        : "Waiting for your approval of the implementation plan."
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
                uniqueKeysWithValues: BotProfile.defaults.map { ($0.id, AgentSessionState()) }
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
        launchedProfileIDs.remove(profileID)
        inFlightUserEntryIDs.removeValue(forKey: profileID)
        planningTurnAssistantEntryIDs.removeValue(forKey: profileID)
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
        launchedProfileIDs.remove(profileID)
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
        launchedProfileIDs.remove(profileID)
        planningTurnAssistantEntryIDs.removeValue(forKey: profileID)
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
                    detail: "Planning → Your approval → Building → Review → Conditional fixes & re-check → Documentation & draft PR"
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
        let turnStartedAt = ContinuousClock.now
        if shouldLaunch {
            launchedProfileIDs.remove(profileID)
        }

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
                let launchStartedAt = ContinuousClock.now
                let isColdStart = launchedProfileIDs.insert(profileID).inserted
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
            if managerWorkflows[profileID]?.stage == .planning,
               managerWorkflows[profileID]?.planApprovalEntryID == nil {
                planningTurnAssistantEntryIDs[profileID] = []
            }
            let responseStream = await runtime.respond(
                to: runtimeMessage,
                attachments: attachments,
                profile: preparedProfile
            )
            turnEntryStartIndices[profileID] =
                sessions[profileID]?.entries.count ?? 0
            var recordedFirstOutput = false
            for await event in responseStream {
                guard runGenerations[profileID] == generation else { return }
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
                apply(event, to: profileID)
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

        if approved, let builderID = workflow.team.builderProfileID {
            state.status = .completed
            workflow.stage = .building
            workflow.isPaused = false
            workflow.pauseReason = nil
            sessions[managerID] = state
            managerWorkflows[managerID] = workflow
            save(immediately: true)

            let plan = workflow.implementationPlan
                ?? latestAssistantText(for: managerID)
            Task { [weak self] in
                await self?.dispatchInitialBuild(
                    workflow: workflow,
                    managerSummary: plan,
                    to: builderID
                )
            }
        } else {
            state.status = .needsAnswer
            workflow.isPaused = true
            workflow.pauseReason =
                "Plan declined. Send feedback to the Manager to request a revised plan."
            sessions[managerID] = state
            managerWorkflows[managerID] = workflow
            save(immediately: true)
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
                let startedAt = ContinuousClock.now
                let package = try await worktrees.makeHandoff(
                    from: source,
                    session: sourceSession
                )
                PerformanceMetrics.record(
                    name: .handoffPreparation,
                    duration: startedAt.duration(to: .now),
                    profile: source
                )
                await runtime.stop(profile: runtimeProfile(for: target))
                connectedProfileIDs.remove(targetProfileID)
                launchedProfileIDs.remove(targetProfileID)
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
                        detail: package.timelineDetail
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
            let startedAt = ContinuousClock.now
            let ownership = try await worktrees.prepareWorktree(
                for: profile,
                startingPoint: handoff?.branch,
                handoffID: handoff?.id
                    ?? sessions[profile.id]?.worktreeSeedID
            )
            PerformanceMetrics.record(
                name: .worktreePreparation,
                duration: startedAt.duration(to: .now),
                profile: profile
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
        workflowStageStartedAt[manager.id] = .now
        save(immediately: true)
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
        case .reviewing:
            workflow.team.reviewerProfileID
        case .verifying:
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
            case .needsApproval, .needsAnswer:
                pauseWorkflow(
                    managerID,
                    reason: "\(profileName(profileID)) needs attention: \(status.label)."
                )
            case .failed:
                planningTurnAssistantEntryIDs.removeValue(forKey: profileID)
                pauseWorkflow(
                    managerID,
                    reason: "\(profileName(profileID)) needs attention: \(status.label)."
                )
            case .stopped:
                planningTurnAssistantEntryIDs.removeValue(forKey: profileID)
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
        workflow.updatedAt = .now
        managerWorkflows[managerID] = workflow
        save(immediately: true)
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
            guard let reviewerID = workflow.team.reviewerProfileID,
                  profiles.contains(where: {
                      $0.id == reviewerID && $0.role == .reviewer
                  }) else {
                pauseWorkflow(
                    managerID,
                    reason: "The assigned Reviewer is no longer available."
                )
                return
            }
            guard let next = transitionWorkflow(
                managerID,
                to: .reviewing
            ) else { return }
            Task { [weak self] in
                await self?.dispatchBuilderHandoff(
                    workflow: next,
                    builderID: profileID,
                    to: reviewerID,
                    instruction: Self.initialReviewInstruction
                )
            }

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
            guard let next = transitionWorkflow(managerID, to: .verifying),
                  let reviewerID = next.team.reviewerProfileID else { return }
            Task { [weak self] in
                await self?.dispatchBuilderHandoff(
                    workflow: next,
                    builderID: profileID,
                    to: reviewerID,
                    instruction: Self.verificationInstruction,
                    pass: .revision,
                    resetRecipient: false
                )
            }

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
        guard transitionWorkflow(managerID, to: .revising) != nil else {
            return
        }
        dispatchWorkflowMessage(
            from: reviewerID,
            to: builderID,
            title: "Review findings",
            visibleText: reviewSummary,
            runtimeMessage: """
            The reviewer requested changes, or did not return a valid structured disposition. Treat this conservatively as changes requested.

            \(reviewSummary)

            Address every actionable finding in your existing worktree. If the disposition was missing or malformed, inspect the review carefully and verify the implementation again. Run the relevant tests, commit any fixes locally, and finish with a concise summary. Do not push or open a pull request.
            """
        )
    }

    private func beginPublishing(
        _ managerID: UUID,
        reviewSummary: String,
        reviewerID: UUID
    ) {
        guard let workflow = managerWorkflows[managerID],
              let publisherID = workflow.team.publisherProfileID,
              profiles.contains(where: {
                  $0.id == publisherID && $0.role == .publisher
              }) else {
            pauseWorkflow(
                managerID,
                reason: "The assigned Documenter / PR Writer is no longer available."
            )
            return
        }
        guard var next = transitionWorkflow(
            managerID,
            to: .publishing,
            persist: false
        ) else { return }
        next.verificationSummary = reviewSummary
        next.updatedAt = .now
        managerWorkflows[managerID] = next
        save(immediately: true)
        Task { [weak self] in
            await self?.dispatchPublishing(
                workflow: next,
                reviewSummary: reviewSummary,
                reviewerID: reviewerID,
                to: publisherID
            )
        }
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
           let manager = profiles.first(where: { $0.id == managerID }),
           !isAppWindowActive() {
            notifications?.post(notice, for: manager)
        }
    }

    private func dispatchInitialBuild(
        workflow: ManagerWorkflow,
        managerSummary: String,
        to builderID: UUID
    ) async {
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
        dispatchWorkflowMessage(
            from: workflow.managerProfileID,
            to: builderID,
            title: "Implementation brief",
            visibleText: workflow.request,
            runtimeMessage: """
            You are the Builder in a managed bl00p workflow.

            Original request:
            \(workflow.request)

            Manager brief:
            \(managerSummary)

            Implement the requested change in your isolated worktree. Keep the change focused, run the relevant tests, and create a local commit before finishing so the Reviewer can inspect an immutable HEAD. Do not push or open a pull request.
            """
        )
    }

    private func dispatchBuilderHandoff(
        workflow: ManagerWorkflow,
        builderID: UUID,
        to reviewerID: UUID,
        instruction: String,
        pass: BuilderHandoffPass = .initial,
        resetRecipient: Bool = true
    ) async {
        guard let package = await prepareBuilderHandoff(
            workflow: workflow,
            builderID: builderID,
            pass: pass
        ) else { return }

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
            var reviewerSession =
                sessions[reviewerID] ?? AgentSessionState()
            reviewerSession.pendingHandoff = package
            reviewerSession.entries.append(
                .init(
                    kind: .handoff,
                    title: "Updated implementation",
                    text: package.taskContext,
                    detail: package.timelineDetail
                )
            )
            sessions[reviewerID] = reviewerSession
            save(immediately: true)
        }
        performSend(
            instruction,
            to: reviewerID
        )
    }

    private func prepareBuilderHandoff(
        workflow: ManagerWorkflow,
        builderID: UUID,
        pass: BuilderHandoffPass
    ) async -> GitHandoffPackage? {
        guard let builder = profiles.first(where: { $0.id == builderID }) else {
            pauseWorkflow(
                workflow.managerProfileID,
                reason: "The assigned Builder is no longer available."
            )
            return nil
        }
        do {
            let startedAt = ContinuousClock.now
            var package = try await worktrees.makeHandoff(
                from: builder,
                session: sessions[builderID] ?? AgentSessionState()
            )
            PerformanceMetrics.record(
                name: .handoffPreparation,
                duration: startedAt.duration(to: .now),
                profile: builder,
                stage: workflow.stage
            )
            package.taskContext = workflow.request
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
                    workflow.managerProfileID,
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
                pauseWorkflow(workflow.managerProfileID, reason: reason)
                append(
                    .init(
                        kind: .question,
                        title: "Builder handoff is not ready",
                        text: "\(reason) Ask this bot to finish the work, run the required tests, and commit any changes."
                    ),
                    to: builderID
                )
                return nil
            }
            record(package, for: workflow.managerProfileID)
            return package
        } catch {
            pauseWorkflow(
                workflow.managerProfileID,
                reason: "Could not prepare the Builder handoff: \(error.localizedDescription)"
            )
            return nil
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
        launchedProfileIDs.remove(profileID)
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
                    detail: handoff.timelineDetail
                )
            )
        }
        sessions[profileID] = state
        save(immediately: true)
        return true
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
        latestAssistantEntry(for: profileID)?.text
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
                    selectedBotID != profileID || !NSApplication.shared.isActive
            }
        case .entry(let entry):
            state.entries.append(entry)
            if entry.kind == .assistant,
               planningTurnAssistantEntryIDs[profileID] != nil {
                planningTurnAssistantEntryIDs[profileID]?.insert(entry.id)
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
            if profiles.first(where: { $0.id == profileID })?.provider == .codex {
                state.codexTurnModeVersion = CodexThreadConfiguration.turnModeVersion
            }
            connectedProfileIDs.insert(profileID)
        }

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
        var state = sessions[profileID] ?? AgentSessionState()
        state.entries.append(entry)
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
            managerWorkflows: managerWorkflows
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
    private let logger = Logger(subsystem: "dev.bl00p.app", category: "persistence")

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
