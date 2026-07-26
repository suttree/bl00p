import Foundation

struct ClaudeInvocation: Sendable {
    let sessionID: String
    let resume: Bool
    let profile: BotProfile
    let prompt: String

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
        result.append(contentsOf: [
            resume ? "--resume" : "--session-id",
            sessionID,
            "--",
            prompt
        ])
        return result
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
            "Bash(swift test:*)",
            "Bash(swift build:*)",
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
