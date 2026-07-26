import Foundation
import Testing
@testable import Bl00p

@Test
func defaultProfilesCoverTheLoop() {
    #expect(BotProfile.defaults.map(\.role) == [.builder, .reviewer, .publisher])
    #expect(Set(BotProfile.defaults.map(\.provider)) == [.claude, .codex])
    #expect(BotProfile.defaults.map(\.name) == ["Claude", "Codex", "Claude"])
}

@Test
func providersChooseSensibleHiddenRolesForNewBots() {
    #expect(AgentProvider.claude.defaultRole == .builder)
    #expect(AgentProvider.codex.defaultRole == .reviewer)
}

@Test
func attentionStatesAreExplicit() {
    #expect(AgentStatus.needsApproval.needsAttention)
    #expect(AgentStatus.needsAnswer.needsAttention)
    #expect(AgentStatus.failed.needsAttention)
    #expect(!AgentStatus.working.needsAttention)
    #expect(!AgentStatus.completed.needsAttention)
}

@Test
func attentionNoticesOnlyFireOnRelevantStatusTransitions() {
    #expect(
        AgentAttentionNotice.transition(from: .working, to: .needsAnswer)
            == .needsAnswer
    )
    #expect(
        AgentAttentionNotice.transition(from: .working, to: .needsApproval)
            == .needsApproval
    )
    #expect(
        AgentAttentionNotice.transition(from: .working, to: .completed)
            == .completed
    )
    #expect(
        AgentAttentionNotice.transition(from: .needsAnswer, to: .needsAnswer)
            == nil
    )
    #expect(
        AgentAttentionNotice.transition(from: .launching, to: .working)
            == nil
    )
}

@MainActor
@Test
func completedAgentPostsNotificationAndUpdatesDockBadge() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-notifications-\(UUID().uuidString)", isDirectory: true)
    let notifications = RecordingNotificationDelivery()
    let model = AppModel(
        runtime: ImmediateRecordingRuntime(),
        store: AppStateStore(fileURL: directory.appendingPathComponent("state.json")),
        notifications: notifications
    )
    let backgroundProfile = try #require(model.profiles.dropFirst().first)

    model.prepareNotifications()
    model.send("Finish this task", to: backgroundProfile.id)

    for _ in 0..<30
        where model.session(for: backgroundProfile.id).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(notifications.authorizationRequestCount == 1)
    #expect(notifications.notices.map(\.notice) == [.completed])
    #expect(notifications.notices.first?.profileID == backgroundProfile.id)
    #expect(notifications.badgeCounts.last == 1)

    model.markViewed(backgroundProfile.id)
    #expect(notifications.badgeCounts.last == 0)
    try? FileManager.default.removeItem(at: directory)
}

@Test
func composerGrowsWhenTextWrapsWithoutANewline() {
    let shortHeight = ComposerTextMetrics.editorHeight(
        for: "Short message",
        width: 420
    )
    let wrappedHeight = ComposerTextMetrics.editorHeight(
        for: String(repeating: "A long command with several words ", count: 8),
        width: 420
    )

    #expect(wrappedHeight > shortHeight)
    #expect(wrappedHeight <= ComposerLimits.maximumEditorHeight)
}

@Test
func composerUsesAGenerousExplicitCharacterLimit() {
    let oversized = String(
        repeating: "a",
        count: ComposerLimits.maximumCharacters + 1_000
    )
    let clamped = ComposerLimits.clamp(oversized)

    #expect(clamped.count == 50_000)
    #expect(
        ComposerTextMetrics.editorHeight(for: clamped, width: 420)
            == ComposerLimits.maximumEditorHeight
    )
}

@Test
func assistantMarkdownProducesClickableLinksAndPreservesLayout() throws {
    let rendered = TranscriptMarkdown.attributed(
        """
        Draft PR created: [suttree/bl00p#1](https://github.com/suttree/bl00p/pull/1)

        - Branch: `feature/improve-agent-workflows`
        """
    )
    let link = try #require(rendered.runs.compactMap(\.link).first)

    #expect(link.absoluteString == "https://github.com/suttree/bl00p/pull/1")
    #expect(String(rendered.characters).contains("suttree/bl00p#1"))
    #expect(String(rendered.characters).contains("\n\n- Branch:"))
    #expect(!String(rendered.characters).contains("https://github.com"))
}

@Test
func codexBotsUseGeneralTurnsInsteadOfInheritingReviewMode() {
    let request = CodexTurnRequest.make(
        threadID: "document-thread",
        message: "Document the existing changes",
        attachments: [],
        modelID: nil
    )

    #expect(request.method == "turn/start")
    #expect(request.params["threadId"]?.stringValue == "document-thread")
    #expect(
        request.params["input"]?.arrayValue?.first?["text"]?.stringValue
            == "Document the existing changes"
    )
}

@Test
func codexThreadConfigurationKeepsBotPromptsSeparate() {
    let reviewer = BotProfile(
        name: "Review",
        provider: .codex,
        role: .reviewer,
        instructions: "Review this code."
    )
    let documenter = BotProfile(
        name: "Document",
        provider: .codex,
        role: .publisher,
        instructions: "Document this code."
    )

    let reviewParameters = CodexThreadConfiguration.parameters(
        profile: reviewer,
        workingDirectory: "/tmp/project"
    )
    let documentParameters = CodexThreadConfiguration.parameters(
        profile: documenter,
        workingDirectory: "/tmp/project"
    )

    #expect(
        reviewParameters["developerInstructions"]?.stringValue
            == "Review this code."
    )
    #expect(
        documentParameters["developerInstructions"]?.stringValue
            == "Document this code."
    )
}

@Test
func persistedStateRoundTrips() throws {
    let profile = BotProfile.defaults[0]
    let state = PersistedAppState(
        profiles: [profile],
        sessions: [
            profile.id: AgentSessionState(
                status: .completed,
                entries: [
                    TimelineEntry(kind: .assistant, text: "Done")
                ],
                hasUnreadCompletion: true,
                sessionID: "session-1"
            )
        ],
        selectedBotID: profile.id
    )

    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(PersistedAppState.self, from: data)

    #expect(decoded.profiles == [profile])
    #expect(decoded.sessions[profile.id]?.status == .completed)
    #expect(decoded.sessions[profile.id]?.entries.first?.text == "Done")
}

@Test
func appStateStoreReadsWhatItWrites() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-tests-\(UUID().uuidString)", isDirectory: true)
    let fileURL = directory.appendingPathComponent("state.json")
    let profile = BotProfile.defaults[1]
    let expected = PersistedAppState(
        profiles: [profile],
        sessions: [
            profile.id: AgentSessionState(
                status: .needsAnswer,
                entries: [TimelineEntry(kind: .question, text: "Which PR?")],
                sessionID: "session-2"
            )
        ],
        selectedBotID: profile.id
    )
    let store = AppStateStore(fileURL: fileURL)

    store.save(expected)
    let actual = try #require(store.load())

    #expect(actual.selectedBotID == expected.selectedBotID)
    #expect(actual.sessions[profile.id]?.entries.first?.timestamp != nil)
    #expect(actual.sessions[profile.id]?.entries.first?.text == "Which PR?")

    try? FileManager.default.removeItem(at: directory)
}

@Test
func jsonValuePreservesRPCPayloads() throws {
    let source = """
    {"id":7,"result":{"thread":{"id":"thr_123"}},"ok":true}
    """
    let value = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(source.utf8)
    )

    #expect(value["id"]?.intValue == 7)
    #expect(value["id"]?.requestIDKey == "n:7")
    #expect(value["result"]?["thread"]?["id"]?.stringValue == "thr_123")
    #expect(value["ok"]?.boolValue == true)
}

@Test
func jsonValueAcceptsFoundationJSONObjects() throws {
    let data = Data(
        """
        {"method":"turn/completed","params":{"count":2,"ready":false,"error":null}}
        """.utf8
    )
    let raw = try JSONSerialization.jsonObject(with: data)
    let value = try JSONValue(any: raw)

    #expect(value["method"]?.stringValue == "turn/completed")
    #expect(value["params"]?["count"]?.intValue == 2)
    #expect(value["params"]?["ready"]?.boolValue == false)
    #expect(value["params"]?["error"] == .null)
}

@Test
func locatesBundledCodexBeforeBrokenShellShims() throws {
    let url = try #require(CodexExecutableLocator().locate())
    #expect(
        url.path == "/Applications/ChatGPT.app/Contents/Resources/codex"
            || url.path.contains("/.codex/plugins/.plugin-appserver/")
    )
}

@Test
func locatesInstalledClaudeCLI() throws {
    let url = try #require(ClaudeExecutableLocator().locate())
    #expect(url.lastPathComponent == "claude")
    #expect(FileManager.default.isExecutableFile(atPath: url.path))
}

@Test
func claudeBuilderInvocationIsResumableAndConservative() throws {
    var profile = BotProfile.defaults[0]
    profile.workingDirectory = "/tmp/project"
    let invocation = try ClaudeInvocation(
        sessionID: "64bfaf39-9db2-45b9-9f10-03a13ea2e772",
        resume: false,
        profile: profile,
        prompt: "Implement BLOOP-42"
    )

    #expect(invocation.arguments.contains("--session-id"))
    #expect(!invocation.arguments.contains("--resume"))
    #expect(invocation.arguments.contains("Edit"))
    #expect(invocation.arguments.contains("Write"))
    #expect(invocation.arguments.contains("Bash(swift test:*)"))
    #expect(invocation.arguments.contains("Bash(xcrun swift test:*)"))
    let toolRules = invocation.arguments.filter { $0.hasPrefix("Bash(") }
    #expect(!toolRules.contains(where: { $0.contains("git push") }))
    #expect(!toolRules.contains(where: { $0.contains("git reset") }))
    #expect(invocation.arguments.suffix(2) == ["--", "Implement BLOOP-42"])
}

@Test
func claudeReviewerInvocationStaysReadOnly() throws {
    let profile = BotProfile.defaults[1]
    let invocation = try ClaudeInvocation(
        sessionID: "64bfaf39-9db2-45b9-9f10-03a13ea2e772",
        resume: true,
        profile: profile,
        prompt: "Review HEAD"
    )

    #expect(invocation.arguments.contains("--resume"))
    #expect(!invocation.arguments.contains("--session-id"))
    #expect(!invocation.arguments.contains("Edit"))
    #expect(!invocation.arguments.contains("Write"))
    #expect(invocation.arguments.contains("Read"))
    #expect(invocation.arguments.contains("Bash(git diff:*)"))
}

@Test
func claudeInvocationPassesTheSelectedModelAndAttachedImages() throws {
    var profile = BotProfile.defaults[0]
    profile.modelID = "sonnet"

    let sourceDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00pTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: sourceDirectory) }
    let sourceFile = sourceDirectory.appendingPathComponent("failure.png")
    try Data("fake image".utf8).write(to: sourceFile)

    let invocation = try ClaudeInvocation(
        sessionID: "64bfaf39-9db2-45b9-9f10-03a13ea2e772",
        resume: false,
        profile: profile,
        prompt: "What is wrong with this screenshot?",
        attachments: [
            ImageAttachment(path: sourceFile.path)
        ]
    )
    defer {
        if let directory = invocation.stagedAttachmentDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    #expect(invocation.arguments.contains("--model"))
    #expect(invocation.arguments.contains("sonnet"))
    #expect(invocation.arguments.contains("--add-dir"))
    #expect(!invocation.arguments.contains(sourceDirectory.path))
    #expect(invocation.arguments.last?.contains("failure.png") == true)
    #expect(invocation.arguments.last?.contains(sourceFile.path) == false)
}

@Test
func missingClaudeConversationTriggersFreshSessionRecovery() throws {
    let event = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(
            """
            {
              "type": "result",
              "is_error": true,
              "num_turns": 0,
              "duration_api_ms": 0,
              "errors": ["No conversation found with session ID: missing"]
            }
            """.utf8
        )
    )

    #expect(ClaudeResumeRecovery.shouldStartFresh(after: event))
}

@Test
func ordinaryClaudeTurnFailureDoesNotDiscardTheSession() throws {
    let event = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(
            """
            {
              "type": "result",
              "is_error": true,
              "num_turns": 1,
              "duration_api_ms": 250,
              "errors": ["The request failed after starting"]
            }
            """.utf8
        )
    )

    #expect(!ClaudeResumeRecovery.shouldStartFresh(after: event))
}

@Test
func earlyUnrelatedFailureDoesNotDiscardTheSession() throws {
    let event = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(
            """
            {
              "type": "result",
              "is_error": true,
              "num_turns": 0,
              "duration_api_ms": 0,
              "errors": ["Invalid model: not-a-real-model"]
            }
            """.utf8
        )
    )

    #expect(!ClaudeResumeRecovery.shouldStartFresh(after: event))
}

@Test
func permissionDenialsProduceAReadableAttentionState() throws {
    let denial = try JSONDecoder().decode(
        JSONValue.self,
        from: Data(
            """
            {
              "tool_name": "Bash",
              "tool_input": {
                "description": "Run tests using Xcode",
                "command": "xcrun swift test"
              }
            }
            """.utf8
        )
    )

    #expect(
        ClaudeTurnOutcome.status(
            failed: false,
            permissionDenials: [denial]
        ) == .needsAnswer
    )
    #expect(
        ClaudePermissionDenials.readableDetail(for: [denial])
            == "• Run tests using Xcode\n  xcrun swift test"
    )
}

@MainActor
@Test
func activeSessionsRestoreAsStopped() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-restore-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[1]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .working,
                    entries: [],
                    sessionID: "thread-to-resume",
                    codexTurnModeVersion: CodexThreadConfiguration.turnModeVersion
                )
            ],
            selectedBotID: profile.id
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)

    #expect(model.session(for: profile.id).status == .stopped)
    #expect(model.session(for: profile.id).sessionID == "thread-to-resume")
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func legacyCodexReviewThreadsRestartWithoutLosingTheirTranscript() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-codex-mode-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[1]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .completed,
                    entries: [.init(kind: .assistant, text: "Previous review output")],
                    sessionID: "legacy-review-thread"
                )
            ],
            selectedBotID: profile.id
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)
    let restored = model.session(for: profile.id)

    #expect(restored.sessionID == nil)
    #expect(restored.status == .stopped)
    #expect(restored.entries.map(\.text) == ["Previous review output"])
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func prototypeStarterCardsAreRemovedWhenStateIsRestored() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-starters-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[1]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .needsAnswer,
                    entries: [
                        TimelineEntry(
                            kind: .system,
                            text: "Resumed Codex review session"
                        ),
                        TimelineEntry(
                            kind: .question,
                            title: "What should I review?",
                            text: "Which PR?"
                        ),
                        TimelineEntry(
                            kind: .assistant,
                            text: "A real saved response"
                        )
                    ]
                )
            ],
            selectedBotID: profile.id
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)

    #expect(model.session(for: profile.id).entries.count == 1)
    #expect(model.session(for: profile.id).entries.first?.text == "A real saved response")
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func legacyPermissionBoundaryIsRestoredAsReadableAttention() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-permission-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[0]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    let rawDenial = """
    {"tool_name":"Bash","tool_input":{"description":"Run tests","command":"xcrun swift test"}}
    """
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .completed,
                    entries: [
                        TimelineEntry(kind: .assistant, text: "Changes applied."),
                        TimelineEntry(
                            kind: .system,
                            text: "Claude stopped at a permission boundary",
                            detail: rawDenial
                        )
                    ],
                    sessionID: "permission-session"
                )
            ],
            selectedBotID: profile.id
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)
    let session = model.session(for: profile.id)

    #expect(session.status == .needsAnswer)
    #expect(session.entries.last?.kind == .question)
    #expect(session.entries.last?.title == "Some actions were blocked")
    #expect(session.entries.last?.detail?.contains("xcrun swift test") == true)
    #expect(session.entries.last?.detail?.contains("tool_input") == false)
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func legacyDefaultNamesMigrateButCustomNamesRemain() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-names-\(UUID().uuidString)", isDirectory: true)
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    var builder = BotProfile.defaults[0]
    builder.name = "Claude Builder"
    var reviewer = BotProfile.defaults[1]
    reviewer.name = "Security pass"
    store.save(
        PersistedAppState(
            profiles: [builder, reviewer],
            sessions: [
                builder.id: AgentSessionState(),
                reviewer.id: AgentSessionState()
            ],
            selectedBotID: builder.id
        )
    )

    let model = AppModel(runtime: DemoAgentRuntime(), store: store)

    #expect(model.profiles[0].name == "Claude")
    #expect(model.profiles[1].name == "Security pass")
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func renamingABotTrimsAndPersistsTheName() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-rename-\(UUID().uuidString)", isDirectory: true)
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    let model = AppModel(runtime: DemoAgentRuntime(), store: store)
    let profileID = try #require(model.profiles.first?.id)

    model.rename(profileID, to: "  Release notes  ")

    #expect(model.profiles.first?.name == "Release notes")
    #expect(store.load()?.profiles.first?.name == "Release notes")
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func firstMessageLaunchesAStoppedBotWithoutAddingAQuestionCard() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-autolaunch-\(UUID().uuidString)", isDirectory: true)
    let runtime = ImmediateRecordingRuntime()
    let model = AppModel(
        runtime: runtime,
        store: AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    )
    let profileID = try #require(model.profiles.first?.id)

    model.send("Inspect the repository", to: profileID)

    for _ in 0..<20 where model.session(for: profileID).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(await runtime.startCount == 1)
    #expect(await runtime.responseCount == 1)
    #expect(model.session(for: profileID).status == .completed)
    #expect(
        model.session(for: profileID).entries.map(\.kind)
            == [.user, .assistant]
    )
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func resumingAStoppedBotKeepsItsExistingTranscript() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-resume-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[0]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .stopped,
                    entries: [.init(kind: .assistant, text: "Earlier answer")],
                    sessionID: "existing-session"
                )
            ],
            selectedBotID: profile.id
        )
    )
    let runtime = ImmediateRecordingRuntime()
    let model = AppModel(runtime: runtime, store: store)

    model.send("Continue", to: profile.id)

    for _ in 0..<20 where model.session(for: profile.id).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(
        model.session(for: profile.id).entries.map(\.text)
            == ["Earlier answer", "Continue", "Working on Continue"]
    )
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func persistedCompletedBotReconnectsBeforeItsNextMessage() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-reconnect-\(UUID().uuidString)", isDirectory: true)
    let profile = BotProfile.defaults[0]
    let store = AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    store.save(
        PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .completed,
                    entries: [.init(kind: .assistant, text: "Previous result")],
                    sessionID: "persisted-session"
                )
            ],
            selectedBotID: profile.id
        )
    )
    let runtime = ImmediateRecordingRuntime()
    let model = AppModel(runtime: runtime, store: store)

    model.send("Resume this work", to: profile.id)

    for _ in 0..<20 where model.session(for: profile.id).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(await runtime.startCount == 1)
    #expect(await runtime.responseCount == 1)
    #expect(
        model.session(for: profile.id).entries.map(\.text)
            == ["Previous result", "Resume this work", "Working on Resume this work"]
    )
    try? FileManager.default.removeItem(at: directory)
}

@MainActor
@Test
func aLongLivedStartupStreamDoesNotBlockTheFirstTurn() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-startup-stream-\(UUID().uuidString)", isDirectory: true)
    let runtime = LongLivedStartupRuntime()
    let model = AppModel(
        runtime: runtime,
        store: AppStateStore(fileURL: directory.appendingPathComponent("state.json"))
    )
    let profileID = try #require(model.profiles.first?.id)

    model.send("Run the review", to: profileID)

    for _ in 0..<30 where model.session(for: profileID).status != .completed {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(await runtime.responseCount == 1)
    #expect(model.session(for: profileID).status == .completed)
    #expect(model.session(for: profileID).entries.last?.text == "Review started")
    try? FileManager.default.removeItem(at: directory)
}

private actor ImmediateRecordingRuntime: AgentRuntime {
    private(set) var startCount = 0
    private(set) var responseCount = 0

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        startCount += 1
        return AsyncStream { continuation in
            continuation.yield(.sessionID("session-\(profile.id.uuidString)"))
            continuation.yield(
                .entry(.init(kind: .question, text: "What should I do?"))
            )
            continuation.yield(.status(.needsAnswer))
            continuation.finish()
        }
    }

    func respond(
        to message: String,
        attachments: [ImageAttachment],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        responseCount += 1
        return AsyncStream { continuation in
            continuation.yield(
                .entry(.init(kind: .assistant, text: "Working on \(message)"))
            )
            continuation.yield(.status(.completed))
            continuation.finish()
        }
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { $0.finish() }
    }

    func stop(profile: BotProfile) async {}
}

@MainActor
private final class RecordingNotificationDelivery: AgentNotificationDelivering {
    struct PostedNotice {
        let notice: AgentAttentionNotice
        let profileID: UUID
    }

    private(set) var authorizationRequestCount = 0
    private(set) var notices: [PostedNotice] = []
    private(set) var badgeCounts: [Int] = []

    func requestAuthorization() {
        authorizationRequestCount += 1
    }

    func post(_ notice: AgentAttentionNotice, for profile: BotProfile) {
        notices.append(.init(notice: notice, profileID: profile.id))
    }

    func setBadgeCount(_ count: Int) {
        badgeCounts.append(count)
    }
}

private actor LongLivedStartupRuntime: AgentRuntime {
    private var startupContinuation: AsyncStream<AgentEvent>.Continuation?
    private(set) var responseCount = 0

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        let pair = AsyncStream.makeStream(of: AgentEvent.self)
        startupContinuation = pair.continuation
        pair.continuation.yield(.sessionID(resumeThreadID ?? "review-session"))
        pair.continuation.yield(.status(.needsAnswer))
        return pair.stream
    }

    func respond(
        to message: String,
        attachments: [ImageAttachment],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        responseCount += 1
        return AsyncStream { continuation in
            continuation.yield(.status(.working))
            continuation.yield(.entry(.init(kind: .assistant, text: "Review started")))
            continuation.yield(.status(.completed))
            continuation.finish()
        }
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { $0.finish() }
    }

    func stop(profile: BotProfile) async {
        startupContinuation?.finish()
        startupContinuation = nil
    }
}
