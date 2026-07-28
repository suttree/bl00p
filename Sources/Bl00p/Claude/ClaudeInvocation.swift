import Foundation

struct ClaudeInvocation: Sendable {
    let sessionID: String
    let resume: Bool
    let profile: BotProfile
    let prompt: String
    let attachments: [ImageAttachment]

    /// A directory holding copies of `attachments`, created fresh per turn so
    /// `--add-dir` grants Claude access only to the attached files rather
    /// than to their original parent directories (e.g. all of ~/Desktop).
    let stagedAttachmentDirectory: URL?
    private let stagedAttachments: [ImageAttachment]

    init(
        sessionID: String,
        resume: Bool,
        profile: BotProfile,
        prompt: String,
        attachments: [ImageAttachment] = []
    ) throws {
        self.sessionID = sessionID
        self.resume = resume
        self.profile = profile
        self.prompt = prompt
        self.attachments = attachments

        guard !attachments.isEmpty else {
            self.stagedAttachmentDirectory = nil
            self.stagedAttachments = []
            return
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bl00p-attachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        self.stagedAttachmentDirectory = directory
        self.stagedAttachments = try attachments.enumerated().map { index, attachment in
            let source = URL(fileURLWithPath: attachment.path)
            let slot = directory.appendingPathComponent("\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            let destination = slot.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: destination)
            return ImageAttachment(id: attachment.id, path: destination.path)
        }
    }

    var arguments: [String] {
        var result = [
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--permission-mode", "default",
            "--permission-prompt-tool", "stdio",
            "--append-system-prompt", systemPrompt,
            "--setting-sources", profile.loadProjectInstructions
                ? "user,project,local"
                : "user",
            "--allowedTools"
        ]

        result.append(contentsOf: allowedTools)
        if let modelID = profile.modelID, !modelID.isEmpty {
            result.append(contentsOf: ["--model", modelID])
        }
        if let stagedAttachmentDirectory {
            result.append("--add-dir")
            result.append(stagedAttachmentDirectory.path)
        }
        result.append(contentsOf: [
            resume ? "--resume" : "--session-id",
            sessionID
        ])
        return result
    }

    var inputMessage: JSONValue {
        .object([
            "type": .string("user"),
            "message": .object([
                "role": .string("user"),
                "content": .string(promptWithAttachments)
            ]),
            "parent_tool_use_id": .null,
            "session_id": .string(sessionID)
        ])
    }

    private var promptWithAttachments: String {
        guard !stagedAttachments.isEmpty else { return prompt }
        let paths = stagedAttachments.map { "- \($0.path)" }.joined(separator: "\n")
        let request = prompt.isEmpty ? "Please inspect the attached image(s)." : prompt
        return """
        \(request)

        The user attached these local images. Use the Read tool to inspect them:
        \(paths)
        """
    }

    private var systemPrompt: String {
        """
        You are running inside bl00p, a human-in-the-loop coding harness.

        \(profile.instructions)

        \(roleBoundary)

        The user is supervising this turn in the bl00p transcript. Work only inside the selected working directory. Explain important decisions and report the verification you performed. If bl00p pauses for tool approval, wait for the user's decision. If a tool is denied, do not work around the policy: use the denial as feedback and explain any blocked outcome.

        Never commit, push, force-push, create or update a pull request, reset or clean the repository, delete files, or run another destructive command unless bl00p presents a separate explicit approval for that exact action.
        """
    }

    private var roleBoundary: String {
        switch profile.role {
        case .builder:
            "You implement and test code. Create local commits when the task or attached workflow handoff requires them, but do not push or open pull requests."
        case .reviewer:
            "You perform a read-only review. Report actionable findings clearly and do not edit, commit, push, or publish."
        case .publisher:
            "You update documentation, run final verification, commit the completed work, push the branch, and create a draft pull request when asked and approved."
        case .manager:
            "You coordinate work and communicate with the user. Prepare task briefs and delivery summaries, but do not edit code, commit, push, or publish."
        }
    }

    private var allowedTools: [String] {
        var tools = [
            "Read",
            "Glob",
            "Grep",
            "ToolSearch",
            "WebFetch",
            "WebSearch",
            "mcp__linear__get_issue",
            "mcp__linear__list_issues",
            "mcp__linear__search_issues",
            "mcp__linear__get_issue_comments",
            "mcp__linear__list_comments",
            "mcp__linear__get_project",
            "mcp__linear__list_projects",
            "mcp__linear__get_team",
            "mcp__linear__list_teams",
            "Bash(git status:*)",
            "Bash(git diff:*)",
            "Bash(git log:*)",
            "Bash(git show:*)",
            "Bash(git branch:*)",
            "Bash(git rev-parse:*)",
            "Bash(git merge-base:*)",
            "Bash(git ls-files:*)",
            "Bash(git grep:*)",
        ]

        tools.append(
            contentsOf: [
                "swift --version",
                "swift test",
                "swift build",
                "env swift --version",
                "xcrun --find swift",
                "xcrun swift test",
                "xcrun swift build",
                "xcode-select -p",
                "xcodebuild test",
                "xcodebuild build",
                "npm test",
                "npm run test",
                "npm run lint",
                "npm run typecheck",
                "pnpm test",
                "pnpm lint",
                "yarn test",
                "cargo test",
                "go test",
                "pytest"
            ]
                .flatMap(Self.exactAndArgumentBearingBashRules)
        )
        // Claude checks each pipeline segment independently. Keep the output
        // filter exact so this does not allow tail to read arbitrary paths.
        tools.append(contentsOf: [
            "Bash(tail -20)",
            "Bash(tail -n 20)"
        ])

        if profile.role == .builder || profile.role == .publisher {
            tools.append(contentsOf: ["Edit", "Write", "NotebookEdit"])
        }
        return tools
    }

    private static func exactAndArgumentBearingBashRules(
        for command: String
    ) -> [String] {
        // Keep the exact form for bare commands and emit both current and
        // legacy argument-prefix forms for compatibility across Claude CLI
        // matcher versions.
        [
            "Bash(\(command))",
            "Bash(\(command) *)",
            "Bash(\(command):*)"
        ]
    }
}
