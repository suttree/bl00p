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
    case blocked
    case completed
    case failed

    var label: String {
        switch self {
        case .stopped: "Stopped"
        case .launching: "Launching"
        case .working: "Working"
        case .needsApproval: "Approval needed"
        case .needsAnswer: "Question"
        case .blocked: "Blocked"
        case .completed: "Finished"
        case .failed: "Failed"
        }
    }

    var needsAttention: Bool {
        self == .needsApproval || self == .needsAnswer || self == .blocked || self == .failed
    }

    var allowsFailedMessageRetry: Bool {
        self == .stopped || self == .completed || self == .blocked || self == .failed
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

    var canSelectApprovalMode: Bool {
        provider != .claude || role != .manager
    }

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
    var ownerSessionID: UUID?
    var repositoryPath: String
    var worktreePath: String
    var branch: String
    var baseRevision: String

    init(
        ownerProfileID: UUID,
        ownerSessionID: UUID? = nil,
        repositoryPath: String,
        worktreePath: String,
        branch: String,
        baseRevision: String
    ) {
        self.ownerProfileID = ownerProfileID
        self.ownerSessionID = ownerSessionID
        self.repositoryPath = repositoryPath
        self.worktreePath = worktreePath
        self.branch = branch
        self.baseRevision = baseRevision
    }
}

enum HandoffTestStatus: String, Codable, Hashable, Sendable {
    case notRun
    case passed
    case failed
    case unverified

    var label: String {
        switch self {
        case .notRun: "Not run"
        case .passed: "Passed"
        case .failed: "Failed"
        case .unverified: "Unverified (blocked)"
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
    var testEvidenceAt: Date?
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
        testEvidenceAt: Date? = nil,
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
        self.testEvidenceAt = testEvidenceAt
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

    var timelineDetail: String {
        """
        Branch: \(branch)
        HEAD: \(headRevision)
        Tests: \(testStatus.label)
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
        // Kept as a source-compatible legacy value. Decoding maps persisted
        // occurrences directly to publishing.
        case .verifying: "Legacy workflow"
        case .publishing: "Documenting & publishing"
        case .reporting: "Finishing"
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
        case .publishing: 4
        case .reporting: 5
        case .completed: 6
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if value == Self.verifying.rawValue {
            self = .publishing
        } else if let stage = Self(rawValue: value) {
            self = stage
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown manager workflow stage: \(value)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ReviewDisposition: String, Sendable {
    case clean
    case changesRequested

    static let marker = "BL00P_REVIEW_DISPOSITION:"

    static func parse(from response: String) -> ReviewDisposition? {
        let matchingLines = response
            .split(whereSeparator: \.isNewline)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { $0.hasPrefix(marker) }
        guard matchingLines.count == 1 else { return nil }
        let value = matchingLines[0]
            .dropFirst(marker.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ReviewDisposition(rawValue: value)
    }

    static func removingProtocolLines(from response: String) -> String {
        response
            .components(separatedBy: .newlines)
            .filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .hasPrefix(marker)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ManagerWorkflowDispatchKind: String, Codable, Hashable, Sendable {
    case initialBuild
    case initialReview
    case revision
    case verification
    case publishing
    case reporting

    var stage: ManagerWorkflowStage {
        switch self {
        case .initialBuild: .building
        case .initialReview: .reviewing
        case .revision: .revising
        case .verification: .verifying
        case .publishing: .publishing
        case .reporting: .reporting
        }
    }
}

struct ManagerWorkflowDispatch: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: ManagerWorkflowDispatchKind
    var sourceProfileID: UUID
    var targetProfileID: UUID
    var summary: String
    var handoff: GitHandoffPackage?
    /// Readable detail of the permission denial(s) recorded when the Builder
    /// turn that produced this dispatch ended `.blocked`, or nil for a normal
    /// completed turn. Lets the readiness gate distinguish "tests didn't run
    /// because the test command was blocked" from a genuine gap.
    var builderTurnBlockedDetail: String?

    init(
        id: UUID = UUID(),
        kind: ManagerWorkflowDispatchKind,
        sourceProfileID: UUID,
        targetProfileID: UUID,
        summary: String,
        handoff: GitHandoffPackage? = nil,
        builderTurnBlockedDetail: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sourceProfileID = sourceProfileID
        self.targetProfileID = targetProfileID
        self.summary = summary
        self.handoff = handoff
        self.builderTurnBlockedDetail = builderTurnBlockedDetail
    }
}

struct ManagerWorkflow: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var managerProfileID: UUID
    var repositoryPath: String
    var team: ManagerTeamConfiguration
    var request: String
    var implementationPlan: String?
    var planApprovalEntryID: UUID?
    var approvedPlanEntryID: UUID?
    var pendingDispatch: ManagerWorkflowDispatch?
    var deliveredDispatchID: UUID?
    var deliveredDispatch: ManagerWorkflowDispatch?
    var resumeAvailableAfterRestart: Bool?
    var stage: ManagerWorkflowStage
    var branch: String?
    var pullRequestURL: String?
    var verificationSummary: String?
    var publisherSummary: String?
    var revisionRounds: Int?
    var latestHandoff: GitHandoffPackage?
    var reviewSummary: String?
    var revisionStartedAt: Date?
    var isPaused: Bool
    var pauseReason: String?
    /// Set when the Builder handoff readiness gate hard-pauses this workflow
    /// while it is `.building`/`.revising`. Lets the workflow re-run the gate
    /// and auto-advance the next time the Builder reaches a terminal status,
    /// instead of requiring a manual resume.
    var awaitingBuilderHandoffRetry: Bool
    var startedAt: Date
    var updatedAt: Date
    var participantSessionIDs: [AgentRole: UUID]

    init(
        id: UUID = UUID(),
        managerProfileID: UUID,
        repositoryPath: String = "",
        team: ManagerTeamConfiguration,
        request: String,
        implementationPlan: String? = nil,
        planApprovalEntryID: UUID? = nil,
        approvedPlanEntryID: UUID? = nil,
        pendingDispatch: ManagerWorkflowDispatch? = nil,
        deliveredDispatchID: UUID? = nil,
        deliveredDispatch: ManagerWorkflowDispatch? = nil,
        resumeAvailableAfterRestart: Bool? = nil,
        stage: ManagerWorkflowStage = .planning,
        branch: String? = nil,
        pullRequestURL: String? = nil,
        verificationSummary: String? = nil,
        publisherSummary: String? = nil,
        revisionRounds: Int = 0,
        latestHandoff: GitHandoffPackage? = nil,
        reviewSummary: String? = nil,
        revisionStartedAt: Date? = nil,
        isPaused: Bool = false,
        pauseReason: String? = nil,
        awaitingBuilderHandoffRetry: Bool = false,
        startedAt: Date = .now,
        updatedAt: Date = .now,
        participantSessionIDs: [AgentRole: UUID] = [:]
    ) {
        self.id = id
        self.managerProfileID = managerProfileID
        self.repositoryPath = repositoryPath
        self.team = team
        self.request = request
        self.implementationPlan = implementationPlan
        self.planApprovalEntryID = planApprovalEntryID
        self.approvedPlanEntryID = approvedPlanEntryID
        self.pendingDispatch = pendingDispatch
        self.deliveredDispatchID = deliveredDispatchID
        self.deliveredDispatch = deliveredDispatch
        self.resumeAvailableAfterRestart = resumeAvailableAfterRestart
        self.stage = stage
        self.branch = branch
        self.pullRequestURL = pullRequestURL
        self.verificationSummary = verificationSummary
        self.publisherSummary = publisherSummary
        self.revisionRounds = revisionRounds
        self.latestHandoff = latestHandoff
        self.reviewSummary = reviewSummary
        self.revisionStartedAt = revisionStartedAt
        self.isPaused = isPaused
        self.pauseReason = pauseReason
        self.awaitingBuilderHandoffRetry = awaitingBuilderHandoffRetry
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.participantSessionIDs = participantSessionIDs
    }

    enum CodingKeys: String, CodingKey {
        case id, managerProfileID, repositoryPath, team, request, implementationPlan
        case planApprovalEntryID, approvedPlanEntryID, pendingDispatch
        case deliveredDispatchID, deliveredDispatch
        case resumeAvailableAfterRestart
        case stage, branch, pullRequestURL
        case verificationSummary, publisherSummary, revisionRounds
        case latestHandoff, reviewSummary, revisionStartedAt
        case isPaused, pauseReason, awaitingBuilderHandoffRetry
        case startedAt, updatedAt, participantSessionIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        managerProfileID = try container.decode(UUID.self, forKey: .managerProfileID)
        repositoryPath = try container.decodeIfPresent(
            String.self,
            forKey: .repositoryPath
        ) ?? ""
        team = try container.decode(ManagerTeamConfiguration.self, forKey: .team)
        request = try container.decode(String.self, forKey: .request)
        implementationPlan = try container.decodeIfPresent(String.self, forKey: .implementationPlan)
        planApprovalEntryID = try container.decodeIfPresent(UUID.self, forKey: .planApprovalEntryID)
        approvedPlanEntryID = try container.decodeIfPresent(
            UUID.self,
            forKey: .approvedPlanEntryID
        )
        pendingDispatch = try container.decodeIfPresent(
            ManagerWorkflowDispatch.self,
            forKey: .pendingDispatch
        )
        deliveredDispatchID = try container.decodeIfPresent(
            UUID.self,
            forKey: .deliveredDispatchID
        )
        deliveredDispatch = try container.decodeIfPresent(
            ManagerWorkflowDispatch.self,
            forKey: .deliveredDispatch
        )
        resumeAvailableAfterRestart = try container.decodeIfPresent(
            Bool.self,
            forKey: .resumeAvailableAfterRestart
        )
        stage = try container.decode(ManagerWorkflowStage.self, forKey: .stage)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        pullRequestURL = try container.decodeIfPresent(String.self, forKey: .pullRequestURL)
        verificationSummary = try container.decodeIfPresent(
            String.self,
            forKey: .verificationSummary
        )
        publisherSummary = try container.decodeIfPresent(
            String.self,
            forKey: .publisherSummary
        )
        revisionRounds = try container.decodeIfPresent(
            Int.self,
            forKey: .revisionRounds
        ) ?? 0
        latestHandoff = try container.decodeIfPresent(GitHandoffPackage.self, forKey: .latestHandoff)
        reviewSummary = try container.decodeIfPresent(
            String.self,
            forKey: .reviewSummary
        )
        revisionStartedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .revisionStartedAt
        )
        isPaused = try container.decode(Bool.self, forKey: .isPaused)
        pauseReason = try container.decodeIfPresent(String.self, forKey: .pauseReason)
        awaitingBuilderHandoffRetry = try container.decodeIfPresent(
            Bool.self,
            forKey: .awaitingBuilderHandoffRetry
        ) ?? false
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        participantSessionIDs = try container.decodeIfPresent(
            [AgentRole: UUID].self,
            forKey: .participantSessionIDs
        ) ?? [:]
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

enum TimelineContentFormat: String, Codable, Sendable {
    case markdown
}

struct StructuredQuestionOption: Identifiable, Codable, Hashable, Sendable {
    var label: String
    var description: String?

    var id: String { label }
}

struct StructuredQuestion: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var header: String?
    var prompt: String
    var options: [StructuredQuestionOption]
    var multiSelect: Bool
}

struct QuestionSelection: Codable, Hashable, Sendable {
    var questionID: String
    var answers: [String]
}

enum QuestionSelectionValidator {
    static func isValid(
        _ selections: [QuestionSelection],
        for questions: [StructuredQuestion]
    ) -> Bool {
        guard selections.count == questions.count else { return false }
        let byID = Dictionary(
            selections.map { ($0.questionID, $0.answers) },
            uniquingKeysWith: { _, latest in latest }
        )
        guard byID.count == selections.count else { return false }

        return questions.allSatisfy { question in
            guard let answers = byID[question.id], !answers.isEmpty else {
                return false
            }
            if question.options.isEmpty {
                return answers.count == 1
                    && !answers[0]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
            }
            let labels = Set(question.options.map(\.label))
            return (question.multiSelect || answers.count == 1)
                && Set(answers).count == answers.count
                && answers.allSatisfy(labels.contains)
        }
    }
}

enum QuestionResolutionState: String, Codable, Sendable {
    case pending
    case submitted
    case cancelled
}

struct QuestionResolution: Codable, Hashable, Sendable {
    var state: QuestionResolutionState
    var selections: [QuestionSelection]

    static let pending = QuestionResolution(state: .pending, selections: [])
    static let cancelled = QuestionResolution(state: .cancelled, selections: [])
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
    var contentFormat: TimelineContentFormat?
    var questions: [StructuredQuestion]?
    var questionResolution: QuestionResolution?

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
        contentFormat: TimelineContentFormat? = nil,
        questions: [StructuredQuestion]? = nil,
        questionResolution: QuestionResolution? = nil
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
        self.contentFormat = contentFormat
        self.questions = questions
        self.questionResolution = questionResolution
    }
}

struct AgentSessionState: Codable, Sendable {
    var id: UUID = UUID()
    var ownerProfileID: UUID?
    var repositoryPath = ""
    var title = "New chat"
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var status: AgentStatus = .stopped
    var entries: [TimelineEntry] = []
    var hasUnreadCompletion = false
    var sessionID: String?
    var codexTurnModeVersion: Int?
    var pendingHandoff: GitHandoffPackage? = nil
    var handoffWorktreePath: String? = nil
    var worktreeSeedID: UUID? = nil
    var worktree: GitWorktreeOwnership?
    var draft = ""
    var instructionsOverride: String?

    enum CodingKeys: String, CodingKey {
        case id, ownerProfileID, repositoryPath, title, createdAt, updatedAt
        case status, entries
        case hasUnreadCompletion, sessionID, codexTurnModeVersion
        case pendingHandoff, handoffWorktreePath, worktreeSeedID, worktree, draft
        case instructionsOverride
    }

    init(
        id: UUID = UUID(),
        ownerProfileID: UUID? = nil,
        repositoryPath: String = "",
        title: String = "New chat",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        status: AgentStatus = .stopped,
        entries: [TimelineEntry] = [],
        hasUnreadCompletion: Bool = false,
        sessionID: String? = nil,
        codexTurnModeVersion: Int? = nil,
        pendingHandoff: GitHandoffPackage? = nil,
        handoffWorktreePath: String? = nil,
        worktreeSeedID: UUID? = nil,
        worktree: GitWorktreeOwnership? = nil,
        draft: String = "",
        instructionsOverride: String? = nil
    ) {
        self.id = id
        self.ownerProfileID = ownerProfileID
        self.repositoryPath = repositoryPath
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.entries = entries
        self.hasUnreadCompletion = hasUnreadCompletion
        self.sessionID = sessionID
        self.codexTurnModeVersion = codexTurnModeVersion
        self.pendingHandoff = pendingHandoff
        self.handoffWorktreePath = handoffWorktreePath
        self.worktreeSeedID = worktreeSeedID
        self.worktree = worktree
        self.draft = draft
        self.instructionsOverride = instructionsOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        ownerProfileID = try container.decodeIfPresent(UUID.self, forKey: .ownerProfileID)
        repositoryPath = try container.decodeIfPresent(
            String.self,
            forKey: .repositoryPath
        ) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "New chat"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        status = try container.decodeIfPresent(AgentStatus.self, forKey: .status) ?? .stopped
        entries = try container.decodeIfPresent([TimelineEntry].self, forKey: .entries) ?? []
        hasUnreadCompletion = try container.decodeIfPresent(Bool.self, forKey: .hasUnreadCompletion) ?? false
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        codexTurnModeVersion = try container.decodeIfPresent(Int.self, forKey: .codexTurnModeVersion)
        pendingHandoff = try container.decodeIfPresent(GitHandoffPackage.self, forKey: .pendingHandoff)
        handoffWorktreePath = try container.decodeIfPresent(
            String.self,
            forKey: .handoffWorktreePath
        ) ?? pendingHandoff?.worktreePath
        worktreeSeedID = try container.decodeIfPresent(UUID.self, forKey: .worktreeSeedID)
        worktree = try container.decodeIfPresent(GitWorktreeOwnership.self, forKey: .worktree)
        draft = try container.decodeIfPresent(String.self, forKey: .draft) ?? ""
        instructionsOverride = try container.decodeIfPresent(String.self, forKey: .instructionsOverride)
    }

    /// Resolves the prompt that should actually be sent to the runtime for a
    /// given chat: the session's override when present and non-blank,
    /// otherwise the bot's default `instructions`.
    static func effectiveInstructions(profile: BotProfile, session: AgentSessionState?) -> String {
        guard let override = session?.instructionsOverride,
              !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return profile.instructions
        }
        return override
    }
}

typealias ChatSession = AgentSessionState

struct PersistedAppState: Codable, Sendable {
    var profiles: [BotProfile]
    var sessions: [UUID: AgentSessionState]
    var selectedBotID: UUID?
    var managerWorkflows: [UUID: ManagerWorkflow]
    var sessionOrder: [UUID: [UUID]]
    var selectedSessionIDs: [UUID: UUID]

    init(
        profiles: [BotProfile],
        sessions: [UUID: AgentSessionState],
        selectedBotID: UUID?,
        managerWorkflows: [UUID: ManagerWorkflow] = [:],
        sessionOrder: [UUID: [UUID]] = [:],
        selectedSessionIDs: [UUID: UUID] = [:]
    ) {
        self.profiles = profiles
        self.sessions = sessions
        self.selectedBotID = selectedBotID
        self.managerWorkflows = managerWorkflows
        self.sessionOrder = sessionOrder
        self.selectedSessionIDs = selectedSessionIDs
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
        sessionOrder = try container.decodeIfPresent(
            [UUID: [UUID]].self,
            forKey: .sessionOrder
        ) ?? [:]
        selectedSessionIDs = try container.decodeIfPresent(
            [UUID: UUID].self,
            forKey: .selectedSessionIDs
        ) ?? [:]
    }
}
