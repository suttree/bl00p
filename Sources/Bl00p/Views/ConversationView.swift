import Foundation

#if os(macOS)
import AppKit
import SwiftUI
#else
import SwiftOpenUI
#endif

struct ConversationView: View {
    @ObservedObject var model: AppModel
    @State private var draft = ""
    @State private var attachments: [ImageAttachment] = []
    @State private var closeRequest: SessionCloseRequest?
    @State private var closeError: String?
    @State private var scrollPositions: [UUID: UUID] = [:]

    var body: some View {
        if let profile = model.selectedProfile,
           let sessionID = model.conversationSessionID(for: profile.id),
           let session = model.sessions[sessionID] {
            let isAwaitingPlanApproval =
                model.workflow(for: profile.id)?.planApprovalEntryID != nil
            let isAwaitingStructuredAnswer = session.entries.contains {
                $0.kind == .question
                    && $0.questionResolution?.state == .pending
            }

            VStack(spacing: 0) {
                ConversationHeader(
                    profile: profile,
                    session: session,
                    handoffTargets: model.profiles.filter { $0.id != profile.id },
                    stop: {
                        model.stop(profile.id, sessionID: sessionID)
                    },
                    handoff: { targetID in
                        model.handoff(
                            from: profile.id,
                            to: targetID,
                            sourceSessionID: sessionID
                        )
                    },
                    chooseRepository: {
                        model.chooseRepository(for: sessionID)
                    },
                    repositoryCanBeChanged:
                        model.repositoryCanBeChanged(for: sessionID),
                    showSettings: { model.isInspectorVisible.toggle() }
                )

                Divider()

                if profile.role == .manager,
                   let selectedTabSessionID =
                    model.selectedTabSessionID(for: profile.id) {
                    ConversationTabBar(
                        sessions: model.tabSessions(for: profile.id),
                        selectedSessionID: selectedTabSessionID,
                        select: {
                            model.selectTab($0, viewing: profile.id)
                        },
                        create: { model.newTab(viewing: profile.id) },
                        close: { requestClose($0) }
                    )

                    Divider()
                }

                if profile.role == .manager {
                    ManagerWorkflowBanner(
                        workflow: model.workflow(for: profile.id),
                        isTeamReady: model.isManagerTeamReady(profile.id),
                        profiles: model.profiles,
                        resume: { model.resumeWorkflow(profile.id) }
                    )
                    Divider()
                }

                if session.entries.isEmpty {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TranscriptView(
                        sessionID: sessionID,
                        scrollPosition: Binding(
                            get: { scrollPositions[sessionID] },
                            set: { scrollPositions[sessionID] = $0 }
                        ),
                        entries: session.entries,
                        profile: profile,
                        canRetryFailedMessage:
                            session.status.allowsFailedMessageRetry,
                        retry: { entryID in
                            model.retry(
                                entryID,
                                for: profile.id,
                                sessionID: sessionID
                            )
                        },
                        resolveApproval: { entryID, approved in
                            model.resolveApproval(
                                entryID,
                                approved: approved,
                                for: profile.id,
                                sessionID: sessionID
                            )
                        },
                        resolveQuestion: { entryID, selections in
                            model.resolveQuestion(
                                entryID,
                                selections: selections,
                                for: profile.id,
                                sessionID: sessionID
                            )
                        }
                    )
                }

                ComposerView(
                    profileID: sessionID,
                    draft: $draft,
                    attachments: $attachments,
                    isEnabled: session.status != .launching
                        && session.status != .working
                        && !isAwaitingPlanApproval
                        && !isAwaitingStructuredAnswer,
                    send: {
                        let outgoing = draft
                        let outgoingAttachments = attachments
                        draft = ""
                        attachments = []
                        model.send(
                            outgoing,
                            attachments: outgoingAttachments,
                            to: profile.id,
                            sessionID: sessionID
                        )
                    }
                )
            }
            .background(Color.bl00pTextBackground)
            .task(id: sessionID) {
                draft = model.sessions[sessionID]?.draft ?? ""
                attachments = []
                model.markViewed(profile.id, sessionID: sessionID)
            }
            .onChange(of: draft) { _, updated in
                model.updateDraft(updated, for: sessionID)
            }
            .onChange(of: sessionID) { previousSessionID, _ in
                model.persistDraft(for: previousSessionID)
            }
            .modifier(SessionCloseDialogs(
                request: $closeRequest,
                error: $closeError,
                close: close
            ))
        } else if let profile = model.selectedProfile,
                  model.tabOwnerProfileID(for: profile.id) != profile.id {
            Bl00pUnavailableView(
                title: "Not Part of This Chat",
                systemImage: "person.crop.circle.badge.questionmark",
                description:
                    "\(profile.name) does not have a conversation in the selected Manager session."
            )
        } else {
            Bl00pUnavailableView(
                title: "No Bot Selected",
                systemImage: "bubble.left.and.exclamationmark.bubble.right",
                description: "Choose or add a bot to begin."
            )
        }
    }
    private func requestClose(_ sessionID: UUID) {
        Task {
            let assessment = await model.closeAssessment(for: sessionID)
            closeRequest = SessionCloseRequest(
                sessionID: sessionID,
                assessment: assessment
            )
        }
    }

    private func close(_ request: SessionCloseRequest) {
        Task {
            let error = await model.closeSession(
                request.sessionID,
                confirmedDestructiveCleanup: true
            )
            if let error {
                closeError = error
            }
            closeRequest = nil
        }
    }
}

private struct SessionCloseRequest: Identifiable {
    let sessionID: UUID
    let assessment: SessionCloseAssessment

    var id: UUID { sessionID }

    var message: String {
        var warnings: [String] = [
            "The local chat history will be deleted. Its Git branch is retained for recovery."
        ]
        if assessment.isActive {
            warnings.append("The agent is active and will be stopped.")
        }
        if assessment.hasDirtyWorktree {
            warnings.append("The worktree has uncommitted changes and will be removed.")
        }
        if assessment.leavesWorktreeOnDisk {
            warnings.append(
                "The worktree cannot be safely removed automatically and will be left on disk."
            )
            if let detail = assessment.worktreeWarning {
                warnings.append(detail)
            }
        }
        if assessment.participatesInWorkflow {
            warnings.append("Its managed workflow will be paused.")
        }
        return warnings.joined(separator: "\n\n")
    }
}

private struct SessionCloseDialogs: ViewModifier {
    @Binding var request: SessionCloseRequest?
    @Binding var error: String?
    let close: (SessionCloseRequest) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .alert(
                request?.assessment.requiresDestructiveConfirmation == true
                    ? "Close this chat and clean up its worktree?"
                    : "Close this chat?",
                isPresented: Binding(
                    get: { request != nil },
                    set: { if !$0 { request = nil } }
                ),
                presenting: request
            ) { request in
                Button("Cancel", role: .cancel) {}
                Button("Close Chat", role: .destructive) {
                    close(request)
                }
            } message: { request in
                Text(request.message)
            }
            .alert(
                "Could not close chat",
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                )
            ) {
                Button("OK") {}
            } message: {
                Text(error ?? "")
            }
        #else
        content
            .sheet(
                isPresented: Binding(
                    get: { request != nil },
                    set: { if !$0 { request = nil } }
                )
            ) {
                if let request {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(
                            request.assessment.requiresDestructiveConfirmation
                                ? "Close this chat and clean up its worktree?"
                                : "Close this chat?"
                        )
                        .font(.bl00p(.headline, weight: .semibold))
                        Text(request.message)
                        HStack {
                            Spacer()
                            Button("Cancel") {
                                self.request = nil
                            }
                            Button("Close Chat") {
                                close(request)
                            }
                        }
                    }
                    .padding(20)
                    .frame(width: 420)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                )
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Could not close chat")
                        .font(.bl00p(.headline, weight: .semibold))
                    Text(error ?? "")
                    HStack {
                        Spacer()
                        Button("OK") {
                            error = nil
                        }
                    }
                }
                .padding(20)
                .frame(width: 420)
            }
        #endif
    }
}

private struct ConversationTabBar: View {
    let sessions: [AgentSessionState]
    let selectedSessionID: UUID
    let select: (UUID) -> Void
    let create: () -> Void
    let close: (UUID) -> Void

    var body: some View {
        #if os(macOS)
        ScrollView(.horizontal, showsIndicators: false) {
            tabs
        }
        #else
        ScrollView(.horizontal) {
            tabs
        }
        #endif
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) {
                offset, session in
                let position = offset + 1

                HStack(spacing: 7) {
                    if session.status == .working || session.status == .launching {
                        ProgressView()
                            .controlSize(.mini)
                    } else if session.status.needsAttention
                                || session.hasUnreadCompletion {
                        Circle()
                            .fill(Color.bl00pPink)
                            .frame(width: 7, height: 7)
                    }

                    Button(position <= 9 ? "⌘\(position)" : "\(position)") {
                        select(session.id)
                    }
                    .buttonStyle(.plain)
                    .lineLimit(1)
                    .help(session.title)
                    .accessibilityLabel("Chat \(position): \(session.title)")

                    Button {
                        close(session.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .help("Close chat")
                }
                .font(.bl00p(.caption1, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    session.id == selectedSessionID
                        ? Color.bl00pPinkSoft
                        : Color.bl00pControlBackground,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            session.id == selectedSessionID
                                ? Color.bl00pPink.opacity(0.55)
                                : Color.bl00pSeparator,
                            lineWidth: 1
                        )
                }
            }

            Button(action: create) {
                Label("New chat", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.bl00pControlBackground)
    }
}

private struct ManagerWorkflowBanner: View {
    let workflow: ManagerWorkflow?
    let isTeamReady: Bool
    let profiles: [BotProfile]
    let resume: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(
                systemName: workflow?.isPaused == true
                    ? "pause.circle.fill"
                    : "point.3.connected.trianglepath.dotted"
            )
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    workflow?.isPaused == true
                        ? Color.orange
                        : Color.bl00pPinkText
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title)
                        .font(.bl00p(.callout, weight: .semibold))
                    if let workflow {
                        Text(workflow.stage.label)
                            .font(.bl00p(.caption1, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let workflow {
                    WorkflowStageIndicator(workflow: workflow)

                    Text(detail(for: workflow))
                        .font(.bl00p(.caption1))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(
                        isTeamReady
                            ? "Your next message will start a managed workflow."
                            : "Assign a Builder, Reviewer, and Documenter in settings to enable optional orchestration."
                    )
                        .font(.bl00p(.caption1))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if workflow?.resumeAvailableAfterRestart == true {
                Button("Resume", action: resume)
                    .buttonStyle(.borderedProminent)
                    .tint(.bl00pPink)
                    #if os(macOS)
                    .accessibilityHint("Continues the restored managed workflow")
                    #endif
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.bl00pPinkSoft.opacity(0.45))
    }

    private var title: String {
        guard let workflow else {
            return isTeamReady ? "Managed workflow ready" : "Standalone Manager"
        }
        if workflow.stage == .completed {
            return "Managed workflow complete"
        }
        return workflow.isPaused ? "Managed workflow paused" : "Managed workflow active"
    }

    private func detail(for workflow: ManagerWorkflow) -> String {
        if let reason = workflow.pauseReason {
            return reason
        }
        if workflow.stage == .completed, let url = workflow.pullRequestURL {
            return url
        }
        guard let profileID = activeProfileID(for: workflow),
              let profile = profiles.first(where: { $0.id == profileID }) else {
            return workflow.request
        }
        return "\(profile.name) is handling \(workflow.stage.label.lowercased())."
    }

    private func activeProfileID(for workflow: ManagerWorkflow) -> UUID? {
        switch workflow.stage {
        case .planning, .reporting:
            workflow.managerProfileID
        case .building, .revising:
            workflow.team.builderProfileID
        case .reviewing:
            workflow.team.reviewerProfileID
        case .publishing:
            workflow.team.publisherProfileID
        case .verifying:
            nil
        case .completed:
            nil
        }
    }
}

private struct WorkflowStageIndicator: View {
    let workflow: ManagerWorkflow

    private let stages = ManagerWorkflowStage.allCases

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, _ in
                if index > 0 {
                    Capsule()
                        .fill(connectorColor(before: index))
                        .frame(width: 14, height: 2)
                }

                stageMarker(at: index)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        #if os(macOS)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Managed workflow progress")
        .accessibilityValue(accessibilityValue)
        #endif
    }

    @ViewBuilder
    private func stageMarker(at index: Int) -> some View {
        let currentIndex = workflow.stage.progressIndex

        if index < currentIndex || workflow.stage == .completed {
            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(Color.bl00pPink, in: Circle())
        } else if index == currentIndex, workflow.isPaused {
            Image(systemName: "pause.fill")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(Color.orange, in: Circle())
        } else if index == currentIndex {
            Circle()
                .fill(Color.bl00pPink)
                .frame(width: 14, height: 14)
                .overlay {
                    Circle()
                        .fill(.white)
                        .frame(width: 5, height: 5)
                }
        } else {
            Circle()
                .fill(Color.bl00pControlBackground)
                .frame(width: 14, height: 14)
                .overlay {
                    Circle()
                        .stroke(.tertiary, lineWidth: 1)
                }
        }
    }

    private func connectorColor(before index: Int) -> Color {
        index <= workflow.stage.progressIndex
            ? .bl00pPink.opacity(0.65)
            : Color.secondary.opacity(0.2)
    }

    private var accessibilityValue: String {
        let state: String
        if workflow.stage == .completed {
            state = "completed"
        } else if workflow.isPaused {
            state = "paused"
        } else {
            state = "active"
        }
        return "\(workflow.stage.label), \(state), stage \(workflow.stage.progressIndex + 1) of \(stages.count)"
    }
}

private struct ConversationHeader: View {
    let profile: BotProfile
    let session: AgentSessionState
    let handoffTargets: [BotProfile]
    let stop: () -> Void
    let handoff: (UUID) -> Void
    let chooseRepository: () -> Void
    let repositoryCanBeChanged: Bool
    let showSettings: () -> Void

    private var isRunning: Bool {
        session.status == .launching || session.status == .working
    }

    var body: some View {
        HStack(spacing: 12) {
            BotAvatar(
                name: profile.name,
                provider: profile.provider,
                role: profile.role,
                size: 38
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(.bl00p(.headline, weight: .semibold))
                    StatusPill(status: session.status)
                }

                Text(directoryLabel)
                    .font(.bl00p(.caption1))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if session.repositoryPath.isEmpty {
                Button("Choose Repository…", action: chooseRepository)
                    .buttonStyle(.borderedProminent)
                    .tint(.bl00pPink)
            } else {
                Button(action: chooseRepository) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .disabled(!repositoryCanBeChanged)
                .help(
                    repositoryCanBeChanged
                        ? "Choose a different repository for this chat"
                        : "Repository is locked after this chat starts. Create a new chat to use another repository."
                )
            }

            if profile.role == .builder,
               session.worktree != nil,
               !handoffTargets.isEmpty {
                Menu {
                    ForEach(handoffTargets) { target in
                        Button {
                            handoff(target.id)
                        } label: {
                            Label(
                                "\(target.name) · \(target.role.displayName)",
                                systemImage: "arrowshape.turn.up.right"
                            )
                        }
                    }
                } label: {
                    Label("Hand off", systemImage: "arrowshape.turn.up.right")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(isRunning)
                .help("Package this branch, task, and test state for another bot")
            }

            if isRunning {
                Button("Stop", systemImage: "stop.fill", action: stop)
                    .buttonStyle(.bordered)
            }

            Button(action: showSettings) {
                #if os(macOS)
                Image(systemName: "slider.horizontal.3")
                #else
                // "slider.horizontal.3" has no Material Symbols mapping;
                // "gearshape" (-> "settings") reads the same for a settings
                // affordance and is already mapped.
                Image(systemName: "gearshape")
                #endif
            }
            .buttonStyle(.bordered)
            .help("Bot settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.bl00pControlBackground)
    }

    private var directoryLabel: String {
        if let worktree = session.worktree {
            return "\(worktree.branch) · \(worktree.worktreePath)"
        }
        if session.repositoryPath.isEmpty {
            return "No repository selected for this chat"
        }
        return session.repositoryPath
    }
}

private struct TranscriptView: View {
    let sessionID: UUID
    @Binding var scrollPosition: UUID?
    let entries: [TimelineEntry]
    let profile: BotProfile
    let canRetryFailedMessage: Bool
    let retry: (UUID) -> Void
    let resolveApproval: (UUID, Bool) -> Void
    let resolveQuestion: (UUID, [QuestionSelection]) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                #if os(macOS)
                LazyVStack(alignment: .leading, spacing: 18) {
                    transcriptContent
                }
                .scrollTargetLayout()
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .frame(maxWidth: 884)
                .frame(maxWidth: .infinity)
                #else
                // SwiftOpenUI's LazyVStack only offers a data-driven
                // initializer, not a free-form ViewBuilder one, so the
                // scroll-to-bottom sentinel view below can't share it with
                // the entries. A plain VStack renders every entry eagerly
                // instead of only the visible ones.
                VStack(alignment: .leading, spacing: 18) {
                    transcriptContent
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .frame(maxWidth: 884)
                .frame(maxWidth: .infinity)
                #endif
            }
            #if os(macOS)
            .scrollPosition(id: $scrollPosition)
            #endif
            .task(id: sessionID) {
                try? await Task.sleep(for: .milliseconds(60))
                proxy.scrollTo(
                    scrollPosition ?? sessionID,
                    anchor: .bottom
                )
            }
            .onChange(of: entries.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(
                        sessionID,
                        anchor: .bottom
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptContent: some View {
        ForEach(entries) { entry in
            TimelineEntryView(
                entry: entry,
                profile: profile,
                canRetryFailedMessage: canRetryFailedMessage,
                retry: retry,
                resolveApproval: resolveApproval,
                resolveQuestion: resolveQuestion
            )
            .id(entry.id)
        }

        Color.clear
            .frame(height: 24)
            .id(sessionID)
    }
}

private struct TimelineEntryView: View {
    let entry: TimelineEntry
    let profile: BotProfile
    let canRetryFailedMessage: Bool
    let retry: (UUID) -> Void
    let resolveApproval: (UUID, Bool) -> Void
    let resolveQuestion: (UUID, [QuestionSelection]) -> Void

    var body: some View {
        switch entry.kind {
        case .user:
            userMessage
        case .assistant:
            assistantMessage
        case .system:
            systemMessage
        case .command:
            ToolCallCard(entry: entry, icon: "terminal", tint: .bl00pInk)
        case .diff:
            ToolCallCard(
                entry: entry,
                icon: "doc.text.magnifyingglass",
                tint: .orange
            )
        case .question:
            if entry.questions?.isEmpty == false {
                StructuredQuestionCard(
                    entry: entry,
                    submit: { resolveQuestion(entry.id, $0) }
                )
            } else {
                eventCard(icon: "questionmark.bubble.fill", tint: .bl00pPinkText)
            }
        case .approval:
            approvalCard
        case .handoff:
            eventCard(icon: "arrowshape.turn.up.right.fill", tint: .bl00pPinkText)
        }
    }

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 100)
            VStack(alignment: .trailing, spacing: 6) {
                VStack(alignment: .leading, spacing: 9) {
                    if !entry.text.isEmpty {
                        Text(entry.text)
                            .textSelection(.enabled)
                    }

                    if let attachments = entry.attachments, !attachments.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(attachments) { attachment in
                                AttachmentThumbnail(attachment: attachment)
                            }
                        }
                    }
                }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Color.bl00pUserBubble,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .foregroundStyle(Color.bl00pUserBubbleText)

                TimelineTimestamp(entry.timestamp)

                if entry.deliveryFailed == true {
                    HStack(spacing: 7) {
                        Label("Failed to send", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Button {
                            retry(entry.id)
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .disabled(!canRetryFailedMessage)
                    }
                    .font(.bl00p(.caption1, weight: .semibold))
                }
            }
        }
    }

    private var assistantMessage: some View {
        HStack(alignment: .top, spacing: 10) {
            BotAvatar(
                name: profile.name,
                provider: profile.provider,
                role: profile.role,
                size: 28
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(profile.name)
                        .font(.bl00p(.caption1, weight: .semibold))
                    TimelineTimestamp(entry.timestamp)
                }
                .foregroundStyle(.secondary)
                MarkdownMessageView(source: entry.text)
            }
            Spacer(minLength: 60)
        }
    }

    private var systemMessage: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.bl00p(.caption1))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                TimelineTimestamp(entry.timestamp)
            }
        }
        .font(.bl00p(.callout))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func eventCard(icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    if let title = entry.title {
                        Text(title)
                            .font(.bl00p(.callout, weight: .semibold))
                    }
                    Spacer()
                    TimelineTimestamp(entry.timestamp)
                }

                if entry.kind == .handoff {
                    MarkdownMessageView(source: entry.text)
                } else {
                    Text(entry.text)
                        .font(.bl00p(.callout))
                        .textSelection(.enabled)
                }

                if let detail = entry.detail {
                    Text(detail)
                        .font(.bl00p(.caption1))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            Color.bl00pControlBackground,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(entry.title ?? "Approval required", systemImage: "hand.raised.fill")
                    .font(.bl00p(.callout, weight: .bold))
                    .foregroundStyle(Color.bl00pPinkText)
                Spacer()
                TimelineTimestamp(entry.timestamp)
                if let state = entry.approvalState, state != .pending {
                    Text(state == .approved ? "Approved" : "Declined")
                        .font(.bl00p(.caption1, weight: .semibold))
                        .foregroundStyle(state == .approved ? .green : .secondary)
                }
            }

            if entry.contentFormat == .markdown {
                MarkdownMessageView(source: entry.text)
            } else {
                Text(entry.text)
                    .font(.bl00p(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }

            if let detail = entry.detail {
                Text(detail)
                    .font(.bl00p(.caption1))
                    .foregroundStyle(.secondary)
            }

            if entry.approvalState == .pending {
                HStack {
                    Button("Decline") {
                        resolveApproval(entry.id, false)
                    }
                    .buttonStyle(.bordered)

                    Button("Approve") {
                        resolveApproval(entry.id, true)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Color.bl00pAvatarInk)
                }
            }
        }
        .padding(15)
        .background(Color.bl00pPinkSoft, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.bl00pPink.opacity(0.40), lineWidth: 1)
        }
    }
}

private struct StructuredQuestionCard: View {
    let entry: TimelineEntry
    let submit: ([QuestionSelection]) -> Void

    @State private var selectedAnswers: [String: Set<String>] = [:]
    @State private var textAnswers: [String: String] = [:]
    @State private var isSubmitting = false

    private var questions: [StructuredQuestion] {
        entry.questions ?? []
    }

    private var state: QuestionResolutionState {
        entry.questionResolution?.state ?? .cancelled
    }

    private var isPending: Bool {
        state == .pending && !isSubmitting
    }

    private var canSubmit: Bool {
        state == .pending
            && !isSubmitting
            && questions.allSatisfy { !answers(for: $0).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Label(
                    entry.title ?? "Question",
                    systemImage: "questionmark.bubble.fill"
                )
                .font(.bl00p(.callout, weight: .bold))
                .foregroundStyle(Color.bl00pPinkText)
                Spacer()
                TimelineTimestamp(entry.timestamp)
                if state != .pending {
                    Text(state == .submitted ? "Submitted" : "Cancelled")
                        .font(.bl00p(.caption1, weight: .semibold))
                        .foregroundStyle(
                            state == .submitted ? Color.green : Color.secondary
                        )
                }
            }

            ForEach(Array(questions.enumerated()), id: \.element.id) {
                index,
                question in
                VStack(alignment: .leading, spacing: 9) {
                    if let header = question.header, !header.isEmpty {
                        Text(header)
                            .font(.bl00p(.caption1, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    Text(question.prompt)
                        .font(.bl00p(.callout, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    if question.options.isEmpty {
                        if state == .submitted {
                            submittedTextAnswer(for: question)
                        } else if state == .cancelled {
                            Text("No answer submitted")
                                .font(.bl00p(.caption1))
                                .foregroundStyle(.secondary)
                        } else {
                            TextField(
                                "Type your answer",
                                text: Binding(
                                    get: {
                                        textAnswers[question.id, default: ""]
                                    },
                                    set: { textAnswers[question.id] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .disabled(!isPending)
                        }
                    } else {
                        VStack(spacing: 7) {
                            ForEach(question.options) { option in
                                optionRow(option, for: question)
                            }
                        }
                    }
                }

                if index < questions.count - 1 {
                    Divider()
                }
            }

            if state == .pending {
                HStack {
                    Spacer()
                    Button(isSubmitting ? "Submitting…" : "Submit answer") {
                        isSubmitting = true
                        submit(
                            questions.map {
                                QuestionSelection(
                                    questionID: $0.id,
                                    answers: answers(for: $0)
                                )
                            }
                        )
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            isSubmitting = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Color.bl00pAvatarInk)
                    .disabled(!canSubmit)
                }
            }
        }
        .padding(15)
        .background(Color.bl00pPinkSoft, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.bl00pPink.opacity(0.40), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func optionRow(
        _ option: StructuredQuestionOption,
        for question: StructuredQuestion
    ) -> some View {
        let selected = answers(for: question).contains(option.label)
        Button {
            toggle(option.label, for: question)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(
                    systemName: question.multiSelect
                        ? (selected ? "checkmark.square.fill" : "square")
                        : (selected ? "circle.inset.filled" : "circle")
                )
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    selected ? Color.bl00pPinkText : Color.secondary
                )
                .frame(width: 18, height: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.label)
                        .font(.bl00p(.callout, weight: .semibold))
                    if let description = option.description {
                        Text(description)
                            .font(.bl00p(.caption1))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                selected
                    ? Color.bl00pPink.opacity(0.10)
                    : Color.bl00pControlBackground,
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        selected
                            ? Color.bl00pPink.opacity(0.55)
                            : Color.secondary.opacity(0.18),
                        lineWidth: 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isPending)
    }

    @ViewBuilder
    private func submittedTextAnswer(
        for question: StructuredQuestion
    ) -> some View {
        Text(answers(for: question).joined(separator: ", "))
            .font(.bl00p(.callout))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                Color.bl00pControlBackground,
                in: RoundedRectangle(cornerRadius: 10)
            )
    }

    private func answers(for question: StructuredQuestion) -> [String] {
        if state == .submitted {
            return entry.questionResolution?.selections
                .first(where: { $0.questionID == question.id })?
                .answers ?? []
        }
        if question.options.isEmpty {
            let answer = textAnswers[question.id, default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return answer.isEmpty ? [] : [answer]
        }
        let labels = selectedAnswers[question.id, default: []]
        return question.options.compactMap {
            labels.contains($0.label) ? $0.label : nil
        }
    }

    private func toggle(_ label: String, for question: StructuredQuestion) {
        if question.multiSelect {
            if selectedAnswers[question.id, default: []].contains(label) {
                selectedAnswers[question.id]?.remove(label)
            } else {
                selectedAnswers[question.id, default: []].insert(label)
            }
        } else {
            selectedAnswers[question.id] = [label]
        }
    }
}

private struct ToolCallCard: View {
    let entry: TimelineEntry
    let icon: String
    let tint: Color
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 28, height: 28)
                        .background(
                            tint.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 8)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title ?? "Tool call")
                            .font(.bl00p(.callout, weight: .semibold))
                        Text(entry.text)
                            .font(
                                entry.kind == .command
                                    ? .bl00p(.caption1, design: .monospaced)
                                    : .bl00p(.caption1)
                            )
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    TimelineTimestamp(entry.timestamp)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.vertical, 12)

                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.text)
                        .font(
                            entry.kind == .command
                                ? .bl00p(.callout, design: .monospaced)
                                : .bl00p(.callout)
                        )
                        .textSelection(.enabled)

                    if let detail = entry.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.bl00p(.caption1, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(14)
        .background(
            Color.bl00pControlBackground,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

private struct AttachmentThumbnail: View {
    let attachment: ImageAttachment

    var body: some View {
        AttachmentImageView(path: attachment.path)
        .frame(width: 72, height: 58)
        .background(.white.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.35), lineWidth: 1)
        }
        .help(attachment.filename)
    }
}

private struct ComposerView: View {
    let profileID: UUID
    @Binding var draft: String
    @Binding var attachments: [ImageAttachment]
    let isEnabled: Bool
    let send: () -> Void
    @State private var isDropTargeted = false
    @State private var editorWidth: CGFloat = 600
    @State private var didReachCharacterLimit = false
    @FocusState private var isEditorFocused: Bool

    private var editorHeight: CGFloat {
        ComposerTextMetrics.editorHeight(
            for: draft,
            width: editorWidth
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !attachments.isEmpty {
                #if os(macOS)
                ScrollView(.horizontal, showsIndicators: false) {
                    attachmentChips
                }
                #else
                // SwiftOpenUI's ScrollView has no showsIndicators toggle.
                ScrollView(.horizontal) {
                    attachmentChips
                }
                #endif
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextEditor(text: limitedDraft)
                    .focused($isEditorFocused)
                    .font(.bl00p(.body))
                    .scrollContentBackground(.hidden)
                    .frame(height: editorHeight)
                    .padding(.horizontal, 12)
                    .padding(.top, 11)
                    .padding(.bottom, 5)
                    .background {
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    editorWidth = geometry.size.width
                                }
                                .onChange(of: geometry.size.width) { _, width in
                                    editorWidth = width
                                }
                        }
                    }
                    .background(
                        Color.bl00pControlBackground,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    }

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.bl00pAvatarInk)
                        .frame(width: 36, height: 36)
                        .background(Color.bl00pPink, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled || !hasContent)
                .opacity(
                    isEnabled && hasContent ? 1 : 0.35
                )
                .keyboardShortcut(.return, modifiers: [.command])
            }

            HStack {
                Text(
                    isEnabled
                        ? "Drop images here · ⌘↩ to send"
                        : "Working…"
                )

                Spacer()

                Text(characterCountLabel)
                    .foregroundStyle(
                        didReachCharacterLimit ? Color.bl00pPinkText : .secondary
                    )
            }
            .font(.bl00p(.caption1))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.bl00pControlBackground)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.bl00pPink, style: .init(lineWidth: 2, dash: [6]))
                    .padding(7)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            addImages(urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .task(id: profileID) {
            await Task.yield()
            isEditorFocused = true
        }
    }

    private var hasContent: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
    }

    private var attachmentChips: some View {
        HStack(spacing: 8) {
            ForEach(attachments) { attachment in
                attachmentChip(attachment)
            }
        }
        .padding(.vertical, 2)
    }

    private var limitedDraft: Binding<String> {
        Binding(
            get: { draft },
            set: { proposedValue in
                didReachCharacterLimit =
                    proposedValue.count > ComposerLimits.maximumCharacters
                draft = ComposerLimits.clamp(proposedValue)
            }
        )
    }

    private var characterCountLabel: String {
        if didReachCharacterLimit {
            return "\(ComposerLimits.maximumCharacters.formatted()) character limit"
        }
        return "\(draft.count.formatted()) / \(ComposerLimits.maximumCharacters.formatted())"
    }

    private func attachmentChip(_ attachment: ImageAttachment) -> some View {
        HStack(spacing: 7) {
            AttachmentImageView(path: attachment.path)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Text(attachment.filename)
                .font(.bl00p(.caption1, weight: .medium))
                .lineLimit(1)

            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove image")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Color.bl00pControlBackground,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private func addImages(_ urls: [URL]) -> Bool {
        let existingPaths = Set(attachments.map(\.path))
        let additions = urls.compactMap { url -> ImageAttachment? in
            let standardized = url.standardizedFileURL
            guard standardized.isFileURL,
                  !existingPaths.contains(standardized.path),
                  AttachmentImageValidation.isLoadableImage(at: standardized)
            else { return nil }
            return ImageAttachment(path: standardized.path)
        }
        attachments.append(contentsOf: additions)
        return !additions.isEmpty
    }
}

private struct MarkdownMessageView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(TranscriptMarkdown.blocks(source)) { block in
                switch block.content {
                case .prose(let text):
                    Text(text)
                        .textSelection(.enabled)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                case .code(let code):
                    #if os(macOS)
                    ScrollView(.horizontal) {
                        Text(code)
                            .font(.bl00p(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true)
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.bl00pControlBackground,
                        in: RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                        .stroke(.quaternary, lineWidth: 1)
                    }
                    #else
                    Text(code)
                        .font(.bl00p(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            Color.bl00pControlBackground,
                            in: RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                            .stroke(.quaternary, lineWidth: 1)
                        }
                    #endif
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct TimelineTimestamp: View {
    let date: Date

    init(_ date: Date) {
        self.date = date
    }

    var body: some View {
        Text(TimelineTimestampFormatter.string(for: date))
            .font(.bl00p(.caption2))
            .foregroundStyle(.tertiary)
            .help(TimelineTimestampFormatter.fullString(for: date))
            #if os(macOS)
            .accessibilityLabel(
                Text(TimelineTimestampFormatter.fullString(for: date))
            )
            #else
            .accessibilityLabel(TimelineTimestampFormatter.fullString(for: date))
            #endif
    }
}

enum TimelineTimestampFormatter {
    static func string(
        for date: Date,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.setLocalizedDateFormatFromTemplate("jm")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("yMMMdjm")
        }
        return formatter.string(from: date)
    }

    static func fullString(
        for date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .long
        return formatter.string(from: date)
    }
}

enum TranscriptMarkdown {
    struct Block: Identifiable {
        enum Content {
            #if os(macOS)
            case prose(AttributedString)
            #else
            // SwiftOpenUI's Text only renders plain String, and this Linux
            // toolchain's AttributedString does not expose the Markdown
            // parsing initializer used below — inline formatting (bold,
            // links) is not rendered, but the raw markdown source (still
            // human-readable) is preserved verbatim.
            case prose(String)
            #endif
            case code(String)
        }

        let id: Int
        let content: Content
    }

    #if os(macOS)
    static func attributed(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
    }
    #else
    static func attributed(_ source: String) -> String { source }
    #endif

    static func blocks(_ source: String) -> [Block] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)

        var result: [Block] = []
        var proseLines: [String] = []
        var codeLines: [String] = []
        var activeFence: String?
        var lineIndex = 0

        func appendProse() {
            let prose = proseLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            guard !prose.isEmpty else {
                proseLines.removeAll()
                return
            }
            result.append(
                Block(id: result.count, content: .prose(attributed(prose)))
            )
            proseLines.removeAll()
        }

        func appendCode() {
            result.append(
                Block(
                    id: result.count,
                    content: .code(codeLines.joined(separator: "\n"))
                )
            )
            codeLines.removeAll()
        }

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fence = activeFence {
                if isClosingFence(trimmed, matching: fence) {
                    appendCode()
                    activeFence = nil
                } else {
                    codeLines.append(line)
                }
                lineIndex += 1
                continue
            }

            if let fence = openingFence(in: trimmed) {
                appendProse()
                activeFence = fence
                lineIndex += 1
            } else if isTableStart(at: lineIndex, in: lines) {
                appendProse()
                while lineIndex < lines.count,
                      isTableRow(lines[lineIndex]) {
                    codeLines.append(lines[lineIndex])
                    lineIndex += 1
                }
                appendCode()
            } else {
                proseLines.append(line)
                lineIndex += 1
            }
        }

        if activeFence != nil {
            appendCode()
        } else {
            appendProse()
        }
        return result
    }

    private static func isTableStart(
        at index: Int,
        in lines: [String]
    ) -> Bool {
        guard index + 1 < lines.count,
              isTableRow(lines[index]) else {
            return false
        }
        let separatorCells = tableCells(in: lines[index + 1])
        return separatorCells.count >= 2
            && separatorCells.allSatisfy { cell in
                let marker = cell.replacingOccurrences(of: ":", with: "")
                return marker.count >= 3
                    && marker.allSatisfy { $0 == "-" }
            }
    }

    private static func isTableRow(_ line: String) -> Bool {
        tableCells(in: line).count >= 2
    }

    private static func tableCells(in line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else {
            return []
        }
        return trimmed
            .dropFirst()
            .dropLast()
            .split(separator: "|", omittingEmptySubsequences: false)
            .map {
                $0.trimmingCharacters(in: .whitespaces)
            }
    }

    private static func openingFence(in line: String) -> String? {
        guard let marker = line.first, marker == "`" || marker == "~" else {
            return nil
        }
        let count = line.prefix { $0 == marker }.count
        guard count >= 3 else { return nil }
        return String(repeating: marker, count: count)
    }

    private static func isClosingFence(
        _ line: String,
        matching fence: String
    ) -> Bool {
        guard let marker = fence.first,
              line.count >= fence.count,
              line.allSatisfy({ $0 == marker }) else {
            return false
        }
        return true
    }
}

enum ComposerLimits {
    static let maximumCharacters = 50_000
    static let maximumEditorHeight: CGFloat = 240

    static func clamp(_ text: String) -> String {
        guard text.count > maximumCharacters else { return text }
        return String(text.prefix(maximumCharacters))
    }
}

enum ComposerTextMetrics {
    static func editorHeight(
        for text: String,
        width: CGFloat
    ) -> CGFloat {
        if text.count > 5_000 {
            return ComposerLimits.maximumEditorHeight
        }

        let availableWidth = max(80, width - 36)

        #if os(macOS)
        let font = NSFont.systemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize + 2
        )
        let measuredText = (text.isEmpty ? " " : text) + "\u{200B}"
        let bounds = (measuredText as NSString).boundingRect(
            with: NSSize(
                width: availableWidth,
                height: .greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let measuredHeight = ceil(bounds.height) + 6
        #else
        let measuredHeight = PortableTextMetrics.wrappedHeight(
            for: text,
            width: availableWidth,
            pointSize: Bl00pTextStyle.body.pointSize + 2
        ) + 6
        #endif

        return min(
            ComposerLimits.maximumEditorHeight,
            max(24, measuredHeight)
        )
    }
}
