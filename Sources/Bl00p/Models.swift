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
}

enum AgentRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case builder
    case reviewer
    case publisher

    var id: Self { self }

    var displayName: String {
        switch self {
        case .builder: "Builder"
        case .reviewer: "Reviewer"
        case .publisher: "PR Writer"
        }
    }

    var launchLabel: String {
        switch self {
        case .builder: "Launch Build"
        case .reviewer: "Launch Review"
        case .publisher: "Launch PR Pass"
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

    init(
        id: UUID = UUID(),
        name: String,
        provider: AgentProvider,
        role: AgentRole,
        instructions: String,
        workingDirectory: String = "",
        loadProjectInstructions: Bool = true,
        requireApprovalBeforePush: Bool = true
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.role = role
        self.instructions = instructions
        self.workingDirectory = workingDirectory
        self.loadProjectInstructions = loadProjectInstructions
        self.requireApprovalBeforePush = requireApprovalBeforePush
    }

    static let defaults: [BotProfile] = [
        BotProfile(
            name: "Claude Builder",
            provider: .claude,
            role: .builder,
            instructions: """
            You are the implementation owner. Follow our engineering standards, keep changes focused, and verify your work with the relevant tests. Use our git mixup workflow. Never use git push --force; use --force-with-lease when rewriting a remote branch is genuinely necessary.
            """
        ),
        BotProfile(
            name: "Codex Reviewer",
            provider: .codex,
            role: .reviewer,
            instructions: """
            You are an exacting but pragmatic pull-request reviewer. Look for correctness defects, regressions, missing tests, security risks, and unnecessary complexity. Explain findings plainly, rank them by impact, and do not edit code unless asked.
            """
        ),
        BotProfile(
            name: "Claude PR Writer",
            provider: .claude,
            role: .publisher,
            instructions: """
            You are a git, pull-request, and documentation expert. Make comments and PR descriptions readable, concrete, and free of unnecessary jargon. Show the proposed commit and PR text before publishing. Create draft pull requests unless explicitly told otherwise.
            """
        )
    ]
}

enum TimelineKind: String, Codable, Sendable {
    case user
    case assistant
    case system
    case command
    case diff
    case question
    case approval
}

enum ApprovalState: String, Codable, Sendable {
    case pending
    case approved
    case declined
}

struct TimelineEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: TimelineKind
    var title: String?
    var text: String
    var detail: String?
    var timestamp: Date
    var approvalState: ApprovalState?

    init(
        id: UUID = UUID(),
        kind: TimelineKind,
        title: String? = nil,
        text: String,
        detail: String? = nil,
        timestamp: Date = .now,
        approvalState: ApprovalState? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.detail = detail
        self.timestamp = timestamp
        self.approvalState = approvalState
    }
}

struct AgentSessionState: Codable, Sendable {
    var status: AgentStatus = .stopped
    var entries: [TimelineEntry] = []
    var hasUnreadCompletion = false
    var sessionID: String?
}

struct PersistedAppState: Codable, Sendable {
    var profiles: [BotProfile]
    var sessions: [UUID: AgentSessionState]
    var selectedBotID: UUID?
}
