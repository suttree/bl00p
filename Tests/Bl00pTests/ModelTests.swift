import Foundation
import Testing
@testable import Bl00p

@Test
func defaultProfilesCoverTheLoop() {
    #expect(BotProfile.defaults.map(\.role) == [.builder, .reviewer, .publisher])
    #expect(Set(BotProfile.defaults.map(\.provider)) == [.claude, .codex])
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
func claudeBuilderInvocationIsResumableAndConservative() {
    var profile = BotProfile.defaults[0]
    profile.workingDirectory = "/tmp/project"
    let invocation = ClaudeInvocation(
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
    let toolRules = invocation.arguments.filter { $0.hasPrefix("Bash(") }
    #expect(!toolRules.contains(where: { $0.contains("git push") }))
    #expect(!toolRules.contains(where: { $0.contains("git reset") }))
    #expect(invocation.arguments.suffix(2) == ["--", "Implement BLOOP-42"])
}

@Test
func claudeReviewerInvocationStaysReadOnly() {
    let profile = BotProfile.defaults[1]
    let invocation = ClaudeInvocation(
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
                    sessionID: "thread-to-resume"
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
