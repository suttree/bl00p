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
    var modelID: String?

    init(
        id: UUID = UUID(),
        name: String,
        provider: AgentProvider,
        role: AgentRole,
        instructions: String,
        workingDirectory: String = "",
        loadProjectInstructions: Bool = true,
        requireApprovalBeforePush: Bool = true,
        modelID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.role = role
        self.instructions = instructions
        self.workingDirectory = workingDirectory
        self.loadProjectInstructions = loadProjectInstructions
        self.requireApprovalBeforePush = requireApprovalBeforePush
        self.modelID = modelID
    }

    var modelDisplayName: String {
        guard let modelID, !modelID.isEmpty else { return "Default model" }
        return provider.modelOptions.first(where: { $0.id == modelID })?.displayName
            ?? modelID
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
    var attachments: [ImageAttachment]?

    init(
        id: UUID = UUID(),
        kind: TimelineKind,
        title: String? = nil,
        text: String,
        detail: String? = nil,
        timestamp: Date = .now,
        approvalState: ApprovalState? = nil,
        attachments: [ImageAttachment]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.detail = detail
        self.timestamp = timestamp
        self.approvalState = approvalState
        self.attachments = attachments
    }
}

struct AgentSessionState: Codable, Sendable {
    var status: AgentStatus = .stopped
    var entries: [TimelineEntry] = []
    var hasUnreadCompletion = false
    var sessionID: String?
    var codexTurnModeVersion: Int?
}

struct PersistedAppState: Codable, Sendable {
    var profiles: [BotProfile]
    var sessions: [UUID: AgentSessionState]
    var selectedBotID: UUID?
}
