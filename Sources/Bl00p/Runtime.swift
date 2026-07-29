import Foundation

enum AgentEvent: Sendable {
    case status(AgentStatus)
    case entry(TimelineEntry)
    case upsertEntry(TimelineEntry)
    case approvalResolved(UUID, ApprovalState)
    case questionResolved(UUID, QuestionResolution)
    case sessionID(String)
}

protocol AgentRuntime: Sendable {
    func start(profile: BotProfile, resumeThreadID: String?) async -> AsyncStream<AgentEvent>
    func respond(
        to message: String,
        attachments: [ImageAttachment],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent>
    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent>
    func resolveQuestion(
        entryID: UUID,
        selections: [QuestionSelection],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent>
    func stop(profile: BotProfile) async
}

extension AgentRuntime {
    func resolveQuestion(
        entryID: UUID,
        selections: [QuestionSelection],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { $0.finish() }
    }
}

struct DemoAgentRuntime: AgentRuntime {
    func start(profile: BotProfile, resumeThreadID: String?) async -> AsyncStream<AgentEvent> {
        stream([
            (.status(.launching), 0),
            (.sessionID("demo-\(profile.id.uuidString.lowercased())"), 180),
            (.entry(.init(
                kind: .system,
                text: "\(profile.provider.displayName) session launched",
                detail: profile.workingDirectory.isEmpty
                    ? "Choose a working directory before connecting a real runtime."
                    : profile.workingDirectory
            )), 220),
            (.status(.working), 160),
            (.entry(.init(
                kind: .assistant,
                text: openingMessage(for: profile.role)
            )), 420),
            (.entry(.init(
                kind: .question,
                title: questionTitle(for: profile.role),
                text: question(for: profile.role)
            )), 320),
            (.status(.needsAnswer), 80)
        ])
    }

    func respond(
        to message: String,
        attachments: [ImageAttachment],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        switch profile.role {
        case .builder:
            stream([
                (.status(.working), 0),
                (.entry(.init(
                    kind: .assistant,
                    text: "I have the ticket. I’ll inspect the repository and establish a clean baseline before changing anything."
                )), 260),
                (.entry(.init(
                    kind: .command,
                    title: "Repository preflight",
                    text: "git status --short && git branch --show-current",
                    detail: profile.workingDirectory.isEmpty ? "Working directory not configured" : profile.workingDirectory
                )), 440),
                (.entry(.init(
                    kind: .assistant,
                    text: "The implementation pass is ready for review. In a real session, the diff and test results will appear here as structured events."
                )), 520),
                (.status(.completed), 120)
            ])

        case .reviewer:
            stream([
                (.status(.working), 0),
                (.entry(.init(
                    kind: .assistant,
                    text: "I’ll review the change for correctness first, then tests, maintainability, and security."
                )), 260),
                (.entry(.init(
                    kind: .command,
                    title: "Review scope",
                    text: "git diff --stat main...HEAD && git diff main...HEAD",
                    detail: profile.workingDirectory.isEmpty ? "Working directory not configured" : profile.workingDirectory
                )), 420),
                (.entry(.init(
                    kind: .diff,
                    title: "Review finding · Medium",
                    text: "The change looks focused. Add a regression test for the failure path before merging.",
                    detail: "This card will eventually link directly to the affected file and line."
                )), 520),
                (.status(.completed), 120)
            ])

        case .publisher:
            stream([
                (.status(.working), 0),
                (.entry(.init(
                    kind: .assistant,
                    text: "I’ve updated the documentation and prepared a concise draft PR description. Publishing remains behind your approval gate."
                )), 320),
                (.entry(.init(
                    kind: .approval,
                    title: "Approval required",
                    text: "git push --force-with-lease && gh pr create --draft",
                    detail: "Review the branch, commit, and PR copy before this runs.",
                    approvalState: .pending
                )), 460),
                (.status(.needsApproval), 80)
            ])

        case .manager:
            stream([
                (.status(.working), 0),
                (.entry(.init(
                    kind: .assistant,
                    text: "I’ve turned the request into a focused implementation brief with acceptance criteria and verification expectations."
                )), 320),
                (.status(.completed), 120)
            ])
        }
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        if approved {
            return stream([
                (.approvalResolved(entryID, .approved), 0),
                (.status(.working), 0),
                (.entry(.init(
                    kind: .command,
                    title: "Approved by you",
                    text: "git push --force-with-lease && gh pr create --draft",
                    detail: "Demo runtime: no external command was executed."
                )), 380),
                (.entry(.init(
                    kind: .assistant,
                    text: "Draft PR prepared. The real adapter will return its URL here."
                )), 360),
                (.status(.completed), 100)
            ])
        }

        return stream([
            (.approvalResolved(entryID, .declined), 0),
            (.entry(.init(
                kind: .system,
                text: "Publishing was declined. No command was run."
            )), 0),
            (.status(.needsAnswer), 80)
        ])
    }

    func resolveQuestion(
        entryID: UUID,
        selections: [QuestionSelection],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        stream([
            (
                .questionResolved(
                    entryID,
                    QuestionResolution(
                        state: .submitted,
                        selections: selections
                    )
                ),
                0
            ),
            (.status(.working), 0),
            (.entry(.init(
                kind: .assistant,
                text: "Thanks — I’ll continue with those choices."
            )), 220),
            (.status(.completed), 80)
        ])
    }

    func stop(profile: BotProfile) async {}

    private func stream(_ scheduledEvents: [(AgentEvent, UInt64)]) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            let task = Task {
                for (event, delay) in scheduledEvents {
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay * 1_000_000)
                    }
                    guard !Task.isCancelled else { break }
                    continuation.yield(event)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func openingMessage(for role: AgentRole) -> String {
        switch role {
        case .builder:
            "Ready to implement. I’ll keep the change narrow, test it, and leave a clear handoff for review."
        case .reviewer:
            "Ready to review independently. I’ll report actionable findings without taking over the implementation."
        case .publisher:
            "Ready for the documentation, readability, and git pass. Nothing will be pushed without your confirmation."
        case .manager:
            "Ready to coordinate an optional delivery workflow while keeping you in control."
        }
    }

    private func questionTitle(for role: AgentRole) -> String {
        switch role {
        case .builder: "What should I build?"
        case .reviewer: "What should I review?"
        case .publisher: "What should I prepare?"
        case .manager: "What should the team work on?"
        }
    }

    private func question(for role: AgentRole) -> String {
        switch role {
        case .builder: "Paste a ticket, describe the task, or provide a Linear issue reference."
        case .reviewer: "Paste the PR URL, branch name, or review handoff from the builder."
        case .publisher: "Share the resolved review notes and the PR or branch you want polished."
        case .manager: "Describe the outcome you want. I’ll prepare and coordinate the work when a team is configured."
        }
    }
}

actor AgentRuntimeRouter: AgentRuntime {
    private let demo = DemoAgentRuntime()
    private let claude = ClaudeRuntime()
    private let codex = CodexAppServerRuntime()
    private var activeProviders: [UUID: AgentProvider] = [:]

    func start(profile: BotProfile, resumeThreadID: String?) async -> AsyncStream<AgentEvent> {
        await stop(profile: profile)
        activeProviders[profile.id] = profile.provider

        if profile.provider == .codex {
            return await codex.start(profile: profile, resumeThreadID: resumeThreadID)
        }
        return await claude.start(profile: profile, resumeThreadID: resumeThreadID)
    }

    func respond(
        to message: String,
        attachments: [ImageAttachment],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        let provider = activeProviders[profile.id] ?? profile.provider
        if provider == .codex {
            return await codex.respond(
                to: message,
                attachments: attachments,
                profile: profile
            )
        }
        return await claude.respond(
            to: message,
            attachments: attachments,
            profile: profile
        )
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        let provider = activeProviders[profile.id] ?? profile.provider
        if provider == .codex {
            return await codex.resolveApproval(
                entryID: entryID,
                approved: approved,
                profile: profile
            )
        }
        return await claude.resolveApproval(
            entryID: entryID,
            approved: approved,
            profile: profile
        )
    }

    func resolveQuestion(
        entryID: UUID,
        selections: [QuestionSelection],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        let provider = activeProviders[profile.id] ?? profile.provider
        if provider == .codex {
            return await codex.resolveQuestion(
                entryID: entryID,
                selections: selections,
                profile: profile
            )
        }
        return await claude.resolveQuestion(
            entryID: entryID,
            selections: selections,
            profile: profile
        )
    }

    func stop(profile: BotProfile) async {
        let provider = activeProviders.removeValue(forKey: profile.id) ?? profile.provider
        if provider == .codex {
            await codex.stop(profile: profile)
        } else {
            await claude.stop(profile: profile)
        }
    }
}
