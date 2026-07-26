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
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--permission-mode", "dontAsk",
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
            sessionID,
            "--",
            promptWithAttachments
        ])
        return result
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

        The user is supervising this turn in the bl00p transcript. Work only inside the selected working directory. Explain important decisions and report the verification you performed. If a tool is denied, do not work around the policy: explain what you wanted to do and ask the user for the next step.

        Never commit, push, force-push, create or update a pull request, reset or clean the repository, delete files, or run another destructive command unless bl00p presents a separate explicit approval for that exact action. This runtime does not yet provide that approval bridge, so stop and ask instead.
        """
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
            "Bash(swift --version:*)",
            "Bash(swift test:*)",
            "Bash(swift build:*)",
            "Bash(env swift --version:*)",
            "Bash(xcrun --find swift:*)",
            "Bash(xcrun swift test:*)",
            "Bash(xcrun swift build:*)",
            "Bash(xcode-select -p:*)",
            "Bash(xcodebuild test:*)",
            "Bash(xcodebuild build:*)",
            "Bash(npm test:*)",
            "Bash(npm run test:*)",
            "Bash(npm run lint:*)",
            "Bash(npm run typecheck:*)",
            "Bash(pnpm test:*)",
            "Bash(pnpm lint:*)",
            "Bash(yarn test:*)",
            "Bash(cargo test:*)",
            "Bash(go test:*)",
            "Bash(pytest:*)"
        ]

        if profile.role != .reviewer {
            tools.append(contentsOf: ["Edit", "Write", "NotebookEdit"])
        }
        return tools
    }
}
