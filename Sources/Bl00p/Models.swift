import Foundation

enum AgentProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    var id: Self { self }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var shortMark: String {
        switch self {
        case .claude: "C"
        case .codex: "X"
        }
    }

    var defaultRole: AgentRole {
        switch self {
        case .claude: .builder
        case .codex: .reviewer
        }
    }

    var modelOptions: [AgentModelOption] {
        switch self {
        case .claude:
            [
                .init(id: "", displayName: "Default"),
                .init(id: "opus", displayName: "Claude Opus"),
                .init(id: "sonnet", displayName: "Claude Sonnet"),
                .init(id: "haiku", displayName: "Claude Haiku"),
                .init(id: "fable", displayName: "Claude Fable")
            ]
        case .codex:
            AgentModelOption.codexOptions
        }
    }
}

struct AgentModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String

    fileprivate static var codexOptions: [AgentModelOption] {
        let fallback = [
            AgentModelOption(id: "gpt-5.6-sol", displayName: "GPT-5.6-Sol"),
            AgentModelOption(id: "gpt-5.6-terra", displayName: "GPT-5.6-Terra"),
            AgentModelOption(id: "gpt-5.6-luna", displayName: "GPT-5.6-Luna"),
            AgentModelOption(id: "gpt-5.5", displayName: "GPT-5.5"),
            AgentModelOption(id: "gpt-5.4", displayName: "GPT-5.4"),
            AgentModelOption(id: "gpt-5.4-mini", displayName: "GPT-5.4-Mini"),
            AgentModelOption(
                id: "gpt-5.3-codex-spark",
                displayName: "GPT-5.3-Codex-Spark"
            )
        ]

        let cacheURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(CodexModelCache.self, from: data) else {
            return [.init(id: "", displayName: "Default")] + fallback
        }

        var seenDisplayNames = Set<String>()
        let visible = cache.models
            .filter { $0.visibility == nil || $0.visibility == "list" }
            .sorted { ($0.priority ?? .max) < ($1.priority ?? .max) }
            .compactMap { model -> AgentModelOption? in
                guard !model.slug.hasPrefix("codex-auto-"),
                      seenDisplayNames.insert(model.displayName).inserted else {
                    return nil
                }
                return AgentModelOption(
                    id: model.slug,
                    displayName: model.displayName
                )
            }
        return [.init(id: "", displayName: "Default")] + (visible.isEmpty ? fallback : visible)
    }
}

private struct CodexModelCache: Decodable {
    let models: [CodexCachedModel]
}

private struct CodexCachedModel: Decodable {
    let slug: String
    let displayName: String
    let visibility: String?
    let priority: Int?

    enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case visibility
        case priority
    }
}

enum AgentRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case builder
    case reviewer
    case publisher
    case manager

    var id: Self { self }

    var displayName: String {
        switch self {
        case .builder: "Builder"
        case .reviewer: "Reviewer"
        case .publisher: "Documenter / PR Writer"
        case .manager: "Manager"
        }
    }

    var launchLabel: String {
        switch self {
        case .builder: "Launch Build"
        case .reviewer: "Launch Review"
        case .publisher: "Launch PR Pass"
        case .manager: "Launch Workflow"
        }
    }
}

enum AgentStatus: String, Codable, Sendable {
    case stopped
    case launching
    case working
    case needsApproval
    case needsAnswer
    case completed
    case failed

    var label: String {
        switch self {
        case .stopped: "Stopped"
        case .launching: "Launching"
        case .working: "Working"
        case .needsApproval: "Approval needed"
        case .needsAnswer: "Question"
        case .completed: "Finished"
        case .failed: "Failed"
        }
    }

    var needsAttention: Bool {
        self == .needsApproval || self == .needsAnswer || self == .failed
    }

    var allowsFailedMessageRetry: Bool {
        self == .stopped || self == .completed || self == .failed
    }
}

enum ApprovalMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case ask
    case auto

    var id: Self { self }

    var displayName: String {
        switch self {
        case .ask: "Ask before running"
        case .auto: "Auto-approve"
        }
    }
}

struct BotProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var provider: AgentProvider
    var role: AgentRole
    var instructions: String
    var workingDirectory: String
    var loadProjectInstructions: Bool
    var requireApprovalBeforePush: Bool
    var approvalMode: ApprovalMode
    var modelID: String?
    var worktree: GitWorktreeOwnership?
    var managerTeam: ManagerTeamConfiguration?

    init(
        id: UUID = UUID(),
        name: String,
        provider: AgentProvider,
        role: AgentRole,
        instructions: String,
        workingDirectory: String = "",
        loadProjectInstructions: Bool = true,
        requireApprovalBeforePush: Bool = true,
        approvalMode: ApprovalMode = .ask,
        modelID: String? = nil,
        worktree: GitWorktreeOwnership? = nil,
        managerTeam: ManagerTeamConfiguration? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.role = role
        self.instructions = instructions
        self.workingDirectory = workingDirectory
        self.loadProjectInstructions = loadProjectInstructions
        self.requireApprovalBeforePush = requireApprovalBeforePush
        self.approvalMode = approvalMode
        self.modelID = modelID
        self.worktree = worktree
        self.managerTeam = managerTeam
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        provider = try container.decode(AgentProvider.self, forKey: .provider)
        role = try container.decode(AgentRole.self, forKey: .role)
        instructions = try container.decode(String.self, forKey: .instructions)
        workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        loadProjectInstructions = try container.decode(Bool.self, forKey: .loadProjectInstructions)
        requireApprovalBeforePush = try container.decode(Bool.self, forKey: .requireApprovalBeforePush)
        approvalMode = try container.decodeIfPresent(ApprovalMode.self, forKey: .approvalMode) ?? .ask
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID)
        worktree = try container.decodeIfPresent(
            GitWorktreeOwnership.self,
            forKey: .worktree
        )
        managerTeam = try container.decodeIfPresent(
            ManagerTeamConfiguration.self,
            forKey: .managerTeam
        )
    }

    var modelDisplayName: String {
        guard let modelID, !modelID.isEmpty else { return "Default model" }
        return provider.modelOptions.first(where: { $0.id == modelID })?.displayName
            ?? modelID
    }

    var runtimeWorkingDirectory: String {
        worktree?.worktreePath ?? workingDirectory
    }

    static let defaults: [BotProfile] = [
        BotProfile(
            name: "Claude",
            provider: .claude,
            role: .builder,
            instructions: """
            You are the implementation owner. Follow our engineering standards, keep changes focused, and verify your work with the relevant tests. Use our git mixup workflow. Never use git push --force; use --force-with-lease when rewriting a remote branch is genuinely necessary.
            """
        ),
        BotProfile(
            name: "Codex",
            provider: .codex,
            role: .reviewer,
            instructions: """
            You are an exacting but pragmatic pull-request reviewer. Look for correctness defects, regressions, missing tests, security risks, and unnecessary complexity. Explain findings plainly, rank them by impact, and do not edit code unless asked.
            """
        ),
        BotProfile(
            name: "Claude",
            provider: .claude,
            role: .publisher,
            instructions: """
            You are a git, pull-request, and documentation expert. Make comments and PR descriptions readable, concrete, and free of unnecessary jargon. Show the proposed commit and PR text before publishing. Create draft pull requests unless explicitly told otherwise.
            """
        )
    ]
}

struct ManagerTeamConfiguration: Codable, Hashable, Sendable {
    var builderProfileID: UUID?
    var reviewerProfileID: UUID?
    var publisherProfileID: UUID?

    init(
        builderProfileID: UUID? = nil,
        reviewerProfileID: UUID? = nil,
        publisherProfileID: UUID? = nil
    ) {
        self.builderProfileID = builderProfileID
        self.reviewerProfileID = reviewerProfileID
        self.publisherProfileID = publisherProfileID
    }

    var isComplete: Bool {
        builderProfileID != nil
            && reviewerProfileID != nil
            && publisherProfileID != nil
    }
}

struct GitWorktreeOwnership: Codable, Hashable, Sendable {
    var ownerProfileID: UUID
    var repositoryPath: String
    var worktreePath: String
    var branch: String
    var baseRevision: String
}

enum HandoffTestStatus: String, Codable, Hashable, Sendable {
    case notRun
    case passed
    case failed

    var label: String {
        switch self {
        case .notRun: "Not run"
        case .passed: "Passed"
        case .failed: "Failed"
        }
    }
}

struct GitHandoffPackage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var sourceProfileID: UUID
    var sourceName: String
    var repositoryPath: String
    var worktreePath: String
    var branch: String
    var baseRevision: String
    var headRevision: String
    var taskContext: String
    var testStatus: HandoffTestStatus
    var testSummary: String
    var workingTreeSummary: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sourceProfileID: UUID,
        sourceName: String,
        repositoryPath: String,
        worktreePath: String,
        branch: String,
        baseRevision: String,
        headRevision: String,
        taskContext: String,
        testStatus: HandoffTestStatus,
        testSummary: String,
        workingTreeSummary: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sourceProfileID = sourceProfileID
        self.sourceName = sourceName
        self.repositoryPath = repositoryPath
        self.worktreePath = worktreePath
        self.branch = branch
        self.baseRevision = baseRevision
        self.headRevision = headRevision
        self.taskContext = taskContext
        self.testStatus = testStatus
        self.testSummary = testSummary
        self.workingTreeSummary = workingTreeSummary
        self.createdAt = createdAt
    }

    var agentContext: String {
        """
        A bl00p handoff package is attached to this task.

        Source bot: \(sourceName)
        Repository: \(repositoryPath)
        Source branch: \(branch)
        Source HEAD: \(headRevision)
        Base revision: \(baseRevision)
        Source worktree: \(worktreePath)

        Task context:
        \(taskContext)

        Test state: \(testStatus.label)
        \(testSummary)

        Working tree:
        \(workingTreeSummary)
        """
    }
}

enum ManagerWorkflowStage: String, Codable, CaseIterable, Sendable {
    case planning
    case building
    case reviewing
    case revising
    case verifying
    case publishing
    case reporting
    case completed

    var label: String {
        switch self {
        case .planning: "Planning"
        case .building: "Building"
        case .reviewing: "Reviewing"
        case .revising: "Fixing findings"
        case .verifying: "Re-checking"
        case .publishing: "Documenting & publishing"
        case .reporting: "Reporting"
        case .completed: "Complete"
        }
    }

    var progressIndex: Int {
        switch self {
        case .planning: 0
        case .building: 1
        case .reviewing: 2
        case .revising: 3
        case .verifying: 4
        case .publishing: 5
        case .reporting: 6
        case .completed: 7
        }
    }
}

struct ManagerWorkflow: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var managerProfileID: UUID
    var team: ManagerTeamConfiguration
    var request: String
    var implementationPlan: String?
    var planApprovalEntryID: UUID?
    var stage: ManagerWorkflowStage
    var branch: String?
    var pullRequestURL: String?
    var latestHandoff: GitHandoffPackage?
    var isPaused: Bool
    var pauseReason: String?
    var startedAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        managerProfileID: UUID,
        team: ManagerTeamConfiguration,
        request: String,
        implementationPlan: String? = nil,
        planApprovalEntryID: UUID? = nil,
        stage: ManagerWorkflowStage = .planning,
        branch: String? = nil,
        pullRequestURL: String? = nil,
        latestHandoff: GitHandoffPackage? = nil,
        isPaused: Bool = false,
        pauseReason: String? = nil,
        startedAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.managerProfileID = managerProfileID
        self.team = team
        self.request = request
        self.implementationPlan = implementationPlan
        self.planApprovalEntryID = planApprovalEntryID
        self.stage = stage
        self.branch = branch
        self.pullRequestURL = pullRequestURL
        self.latestHandoff = latestHandoff
        self.isPaused = isPaused
        self.pauseReason = pauseReason
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

struct ImageAttachment: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var path: String

    init(id: UUID = UUID(), path: String) {
        self.id = id
        self.path = path
    }

    var filename: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum TimelineKind: String, Codable, Sendable {
    case user
    case assistant
    case system
    case command
    case diff
    case question
    case approval
    case handoff
}

enum ApprovalState: String, Codable, Sendable {
    case pending
    case approved
    case declined
}

struct QuestionOption: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var label: String
    var description: String?
}

struct QuestionAnswer: Codable, Hashable, Sendable {
    var selectedOptionIDs: [String]
    var otherText: String?

    init(selectedOptionIDs: [String] = [], otherText: String? = nil) {
        self.selectedOptionIDs = selectedOptionIDs
        self.otherText = otherText?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    func isValid(for question: InteractiveQuestion) -> Bool {
        let validIDs = Set(question.options.map(\.id))
        let selections = Set(selectedOptionIDs)
        guard selections.count == selectedOptionIDs.count,
              selections.isSubset(of: validIDs) else {
            return false
        }
        let hasOther = !(otherText ?? "").isEmpty
        guard question.allowsOther || !hasOther else { return false }
        guard !selections.isEmpty || hasOther else { return false }
        return question.allowsMultiple || selections.count + (hasOther ? 1 : 0) == 1
    }

    func displayValues(for question: InteractiveQuestion) -> [String] {
        let labels = selectedOptionIDs.compactMap { id in
            question.options.first(where: { $0.id == id })?.label
        }
        guard let otherText, !otherText.isEmpty else { return labels }
        return labels + [otherText]
    }
}

enum QuestionResolutionState: String, Codable, Sendable {
    case pending
    case submitting
    case answered
    case cancelled
}

struct InteractiveQuestion: Codable, Hashable, Sendable {
    var id: String
    var header: String
    var text: String
    var options: [QuestionOption]
    var allowsMultiple: Bool
    var allowsOther: Bool
    var answer: QuestionAnswer?
    var resolutionState: QuestionResolutionState

    init(
        id: String,
        header: String,
        text: String,
        options: [QuestionOption],
        allowsMultiple: Bool = false,
        allowsOther: Bool = true,
        answer: QuestionAnswer? = nil,
        resolutionState: QuestionResolutionState = .pending
    ) {
        self.id = id
        self.header = header
        self.text = text
        self.options = options
        self.allowsMultiple = allowsMultiple
        self.allowsOther = allowsOther
        self.answer = answer
        self.resolutionState = resolutionState
    }
}

struct QuestionResponseDraft: Equatable, Sendable {
    var selectedOptionIDs: Set<String> = []
    var isOtherSelected = false
    var otherText = ""

    mutating func toggleOption(_ id: String, for question: InteractiveQuestion) {
        guard question.options.contains(where: { $0.id == id }) else { return }
        if question.allowsMultiple {
            if !selectedOptionIDs.insert(id).inserted {
                selectedOptionIDs.remove(id)
            }
        } else {
            selectedOptionIDs = selectedOptionIDs == Set([id]) ? [] : [id]
            isOtherSelected = false
        }
    }

    mutating func toggleOther(for question: InteractiveQuestion) {
        guard question.allowsOther else { return }
        isOtherSelected.toggle()
        if isOtherSelected, !question.allowsMultiple {
            selectedOptionIDs.removeAll()
        }
    }

    func answer(for question: InteractiveQuestion) -> QuestionAnswer {
        let orderedIDs = question.options
            .map(\.id)
            .filter(selectedOptionIDs.contains)
        return QuestionAnswer(
            selectedOptionIDs: orderedIDs,
            otherText: isOtherSelected ? otherText : nil
        )
    }

    func canContinue(for question: InteractiveQuestion) -> Bool {
        answer(for: question).isValid(for: question)
    }
}

struct TimelineEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: TimelineKind
    var title: String?
    var text: String
    var detail: String?
    var timestamp: Date
    var approvalState: ApprovalState?
    var attachments: [ImageAttachment]?
    var deliveryFailed: Bool?
    var question: InteractiveQuestion?

    init(
        id: UUID = UUID(),
        kind: TimelineKind,
        title: String? = nil,
        text: String,
        detail: String? = nil,
        timestamp: Date = .now,
        approvalState: ApprovalState? = nil,
        attachments: [ImageAttachment]? = nil,
        deliveryFailed: Bool? = nil,
        question: InteractiveQuestion? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.detail = detail
        self.timestamp = timestamp
        self.approvalState = approvalState
        self.attachments = attachments
        self.deliveryFailed = deliveryFailed
        self.question = question
    }
}

struct AgentSessionState: Codable, Sendable {
    var status: AgentStatus = .stopped
    var entries: [TimelineEntry] = []
    var hasUnreadCompletion = false
    var sessionID: String?
    var codexTurnModeVersion: Int?
    var pendingHandoff: GitHandoffPackage? = nil
    var worktreeSeedID: UUID? = nil

    var hasPendingQuestion: Bool {
        entries.contains {
            $0.question?.resolutionState == .pending
                || $0.question?.resolutionState == .submitting
        }
    }
}

struct PersistedAppState: Codable, Sendable {
    var profiles: [BotProfile]
    var sessions: [UUID: AgentSessionState]
    var selectedBotID: UUID?
    var managerWorkflows: [UUID: ManagerWorkflow]

    init(
        profiles: [BotProfile],
        sessions: [UUID: AgentSessionState],
        selectedBotID: UUID?,
        managerWorkflows: [UUID: ManagerWorkflow] = [:]
    ) {
        self.profiles = profiles
        self.sessions = sessions
        self.selectedBotID = selectedBotID
        self.managerWorkflows = managerWorkflows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decode([BotProfile].self, forKey: .profiles)
        sessions = try container.decode(
            [UUID: AgentSessionState].self,
            forKey: .sessions
        )
        selectedBotID = try container.decodeIfPresent(
            UUID.self,
            forKey: .selectedBotID
        )
        managerWorkflows = try container.decodeIfPresent(
            [UUID: ManagerWorkflow].self,
            forKey: .managerWorkflows
        ) ?? [:]
    }
}
