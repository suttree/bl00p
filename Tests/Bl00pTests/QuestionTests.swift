import Foundation
import Testing
@testable import Bl00p

@Test
func claudeAskUserQuestionPreservesDescriptionsAndBuildsExactResponse() throws {
    let request = try decodeJSON(
        """
        {
          "subtype": "can_use_tool",
          "tool_name": "AskUserQuestion",
          "input": {
            "questions": [
              {
                "question": "How should I format the output?",
                "header": "Format",
                "options": [
                  {"label": "Summary", "description": "Brief overview"},
                  {"label": "Detailed", "description": "Full explanation"}
                ],
                "multiSelect": false
              },
              {
                "question": "Which sections should I include?",
                "header": "Sections",
                "options": [
                  {"label": "Introduction", "description": "Opening context"},
                  {"label": "Conclusion", "description": "Final summary"}
                ],
                "multiSelect": true
              }
            ]
          }
        }
        """
    )
    let parsed = try #require(ClaudeQuestionRequest(request: request))

    #expect(parsed.questions.count == 2)
    #expect(parsed.questions[0].header == "Format")
    #expect(parsed.questions[0].options[1].description == "Full explanation")
    #expect(parsed.questions[1].allowsMultiple)
    #expect(
        parsed.result(
            answers: [
                "question-0": QuestionAnswer(selectedOptionIDs: ["option-0"]),
                "question-1": QuestionAnswer(
                    selectedOptionIDs: ["option-0", "option-1"]
                )
            ]
        ) == .object([
            "behavior": .string("allow"),
            "updatedInput": .object([
                "questions": request["input"]!["questions"]!,
                "answers": .object([
                    "How should I format the output?": .string("Summary"),
                    "Which sections should I include?": .array([
                        .string("Introduction"),
                        .string("Conclusion")
                    ])
                ])
            ])
        ])
    )
}

@Test
func claudeQuestionSupportsOtherTextWithoutRawProviderDataInTimeline() throws {
    let request = try decodeJSON(
        """
        {
          "subtype": "can_use_tool",
          "tool_name": "AskUserQuestion",
          "input": {
            "questions": [{
              "question": "Which environment?",
              "header": "Target",
              "options": [{"label": "Staging", "description": "Safe test target"}],
              "multiSelect": false
            }]
          }
        }
        """
    )
    let parsed = try #require(ClaudeQuestionRequest(request: request))
    let question = parsed.questions[0]
    let answer = QuestionAnswer(otherText: "A temporary preview environment")
    let entry = TimelineEntry(
        kind: .question,
        title: question.header,
        text: question.text,
        question: question
    )

    #expect(answer.isValid(for: question))
    #expect(entry.detail == nil)
    #expect(entry.text == "Which environment?")
    #expect(
        parsed.result(answers: [question.id: answer])?["updatedInput"]?["answers"]?[
            "Which environment?"
        ] == .string("A temporary preview environment")
    )
}

@Test
func codexRequestUserInputBuildsAnswersByProviderQuestionID() throws {
    let params = try decodeJSON(
        """
        {
          "questions": [
            {
              "id": "database",
              "header": "Database",
              "question": "Choose a database",
              "options": [
                {"label": "Postgres", "description": "Relational"},
                {"label": "SQLite", "description": "Embedded"}
              ]
            },
            {
              "id": "features",
              "header": "Features",
              "question": "Choose features",
              "multiSelect": true,
              "options": [
                {"label": "Search", "description": "Full text"},
                {"label": "Audit", "description": "Change history"}
              ]
            }
          ]
        }
        """
    )
    let parsed = try #require(CodexQuestionRequest(params: params))

    #expect(parsed.questions[0].options[0].description == "Relational")
    #expect(
        parsed.result(
            answers: [
                "database": QuestionAnswer(selectedOptionIDs: ["option-1"]),
                "features": QuestionAnswer(
                    selectedOptionIDs: ["option-0"],
                    otherText: "Exports"
                )
            ]
        ) == .object([
            "answers": .object([
                "database": .object([
                    "answers": .array([.string("SQLite")])
                ]),
                "features": .object([
                    "answers": .array([.string("Search"), .string("Exports")])
                ])
            ])
        ])
    )
}

@Test
func malformedAndDuplicateProviderQuestionsAreRejected() throws {
    let malformedClaude = try decodeJSON(
        """
        {
          "subtype": "can_use_tool",
          "tool_name": "AskUserQuestion",
          "input": {"questions": [{"header": "Missing", "options": []}]}
        }
        """
    )
    let duplicateCodex = try decodeJSON(
        """
        {
          "questions": [
            {"id": "same", "question": "First", "options": []},
            {"id": "same", "question": "Second", "options": []}
          ]
        }
        """
    )

    #expect(ClaudeQuestionRequest(request: malformedClaude) == nil)
    #expect(CodexQuestionRequest(params: duplicateCodex) == nil)
}

@Test
func concurrentQuestionRequestsQueueWithoutOverwritingAndCancelCleanly() {
    let question = testQuestion(allowsMultiple: false)
    var queue = QuestionRequestQueue<String, String>()

    let first = queue.enqueue(
        requestID: "request-1",
        request: "first",
        questions: [question]
    )
    let second = queue.enqueue(
        requestID: "request-2",
        request: "second",
        questions: [question]
    )
    let duplicate = queue.enqueue(
        requestID: "request-2",
        request: "duplicate",
        questions: [question]
    )

    #expect(first != nil)
    #expect(second != nil)
    #expect(duplicate == nil)
    #expect(queue.first?.request == "first")

    let queuedCancellation = queue.cancel(requestID: "request-2")
    #expect(queuedCancellation?.wasActive == false)
    #expect(queue.first?.request == "first")

    _ = queue.enqueue(
        requestID: "request-3",
        request: "third",
        questions: [question]
    )
    let activeCancellation = queue.cancel(requestID: "request-1")
    #expect(activeCancellation?.wasActive == true)
    #expect(queue.first?.request == "third")
}

@Test
func questionBatchAdvancesInOrderAndRetainsAnswersUntilSubmission() throws {
    let questions = [
        testQuestion(id: "first", allowsMultiple: false),
        testQuestion(id: "second", allowsMultiple: true)
    ]
    var queue = QuestionRequestQueue<String, String>()
    let enqueued = queue.enqueue(
        requestID: "batch",
        request: "provider request",
        questions: questions
    )
    var pending = try #require(enqueued)
    let firstEntryID = pending.entryID

    #expect(
        pending.record(
            entryID: firstEntryID,
            answer: QuestionAnswer(selectedOptionIDs: ["one"])
        ) == .next
    )
    #expect(pending.currentQuestion.id == "second")
    #expect(pending.entryID != firstEntryID)
    #expect(pending.answers["first"]?.selectedOptionIDs == ["one"])
    #expect(
        pending.record(
            entryID: pending.entryID,
            answer: QuestionAnswer(selectedOptionIDs: ["one", "two"])
        ) == .readyToSubmit
    )
    #expect(pending.answers.count == 2)
}

@Test
func questionDraftEnforcesSingleMultiAndOtherSelectionRules() {
    let single = testQuestion(allowsMultiple: false)
    var singleDraft = QuestionResponseDraft()
    #expect(!singleDraft.canContinue(for: single))

    singleDraft.toggleOption("one", for: single)
    #expect(singleDraft.selectedOptionIDs == ["one"])
    #expect(singleDraft.canContinue(for: single))
    singleDraft.toggleOption("two", for: single)
    #expect(singleDraft.selectedOptionIDs == ["two"])
    singleDraft.toggleOther(for: single)
    #expect(singleDraft.selectedOptionIDs.isEmpty)
    #expect(!singleDraft.canContinue(for: single))
    singleDraft.otherText = "Custom"
    #expect(singleDraft.canContinue(for: single))

    let multi = testQuestion(allowsMultiple: true)
    var multiDraft = QuestionResponseDraft()
    multiDraft.toggleOption("one", for: multi)
    multiDraft.toggleOption("two", for: multi)
    multiDraft.toggleOther(for: multi)
    multiDraft.otherText = "Custom"
    #expect(
        multiDraft.answer(for: multi).displayValues(for: multi)
            == ["First", "Second", "Custom"]
    )
}

@Test
func answeredQuestionCardsRoundTripWithoutProviderJSON() throws {
    var question = testQuestion(allowsMultiple: true)
    question.answer = QuestionAnswer(
        selectedOptionIDs: ["one"],
        otherText: "Custom"
    )
    question.resolutionState = .answered
    let entry = TimelineEntry(
        kind: .question,
        title: question.header,
        text: question.text,
        question: question
    )

    let data = try JSONEncoder().encode(entry)
    let restored = try JSONDecoder().decode(TimelineEntry.self, from: data)

    #expect(restored.question?.resolutionState == .answered)
    #expect(
        restored.question?.answer?.displayValues(for: question)
            == ["First", "Custom"]
    )
    #expect(!String(decoding: data, as: UTF8.self).contains("updatedInput"))
}

@Test
@MainActor
func appModelUsesDedicatedQuestionResponseAndGatesComposerMessages() async throws {
    let runtime = QuestionRecordingRuntime()
    let profile = BotProfile(
        name: "Question bot",
        provider: .codex,
        role: .reviewer,
        instructions: "",
        workingDirectory: "/tmp"
    )
    let store = try temporaryStore(
        state: PersistedAppState(
            profiles: [profile],
            sessions: [profile.id: AgentSessionState()],
            selectedBotID: profile.id
        )
    )
    let model = AppModel(runtime: runtime, store: store)

    model.launch(profile.id)
    try await eventually {
        model.session(for: profile.id).hasPendingQuestion
    }
    model.send("This must not start a new turn", to: profile.id)
    try await Task.sleep(for: .milliseconds(30))
    #expect(await runtime.normalMessageCount == 0)

    let entry = try #require(
        model.session(for: profile.id).entries.first(where: {
            $0.question?.resolutionState == .pending
        })
    )
    model.resolveQuestion(
        entry.id,
        answer: QuestionAnswer(selectedOptionIDs: ["one"]),
        for: profile.id
    )
    try await eventually { () -> Bool in
        let resolved = model.session(for: profile.id).entries.first(where: {
            $0.id == entry.id
        })?.question?.resolutionState
        return resolved == QuestionResolutionState.answered
    }

    #expect(await runtime.questionResponseCount == 1)
    #expect(model.session(for: profile.id).status == AgentStatus.working)
}

@Test
@MainActor
func questionTransportFailureLeavesThePendingCardAnswerable() async throws {
    let runtime = QuestionRecordingRuntime(failQuestionResponse: true)
    let profile = BotProfile(
        name: "Question bot",
        provider: .claude,
        role: .reviewer,
        instructions: "",
        workingDirectory: "/tmp"
    )
    let store = try temporaryStore(
        state: PersistedAppState(
            profiles: [profile],
            sessions: [profile.id: AgentSessionState()],
            selectedBotID: profile.id
        )
    )
    let model = AppModel(runtime: runtime, store: store)

    model.launch(profile.id)
    try await eventually {
        model.session(for: profile.id).hasPendingQuestion
    }
    let entry = try #require(
        model.session(for: profile.id).entries.first(where: {
            $0.question?.resolutionState == .pending
        })
    )
    model.resolveQuestion(
        entry.id,
        answer: QuestionAnswer(selectedOptionIDs: ["one"]),
        for: profile.id
    )
    try await eventually {
        model.session(for: profile.id).entries.contains(where: {
            $0.text == "Could not send the answer"
        })
    }

    #expect(model.session(for: profile.id).hasPendingQuestion)
    #expect(model.session(for: profile.id).status == AgentStatus.needsAnswer)
}

@Test
@MainActor
func pendingQuestionsAreCancelledWhenRestoredAfterRestart() throws {
    let profile = BotProfile(
        name: "Question bot",
        provider: .claude,
        role: .builder,
        instructions: ""
    )
    let question = testQuestion(allowsMultiple: false)
    let store = try temporaryStore(
        state: PersistedAppState(
            profiles: [profile],
            sessions: [
                profile.id: AgentSessionState(
                    status: .needsAnswer,
                    entries: [
                        TimelineEntry(
                            kind: .question,
                            title: question.header,
                            text: question.text,
                            question: question
                        )
                    ]
                )
            ],
            selectedBotID: profile.id
        )
    )

    let restored = AppModel(runtime: QuestionRecordingRuntime(), store: store)
    #expect(restored.session(for: profile.id).status == AgentStatus.stopped)
    #expect(
        restored.session(for: profile.id).entries[0].question?.resolutionState
            == .cancelled
    )
    #expect(!restored.session(for: profile.id).hasPendingQuestion)
}

private func testQuestion(
    id: String = "test",
    allowsMultiple: Bool
) -> InteractiveQuestion {
    InteractiveQuestion(
        id: id,
        header: "Choice",
        text: "Choose an option",
        options: [
            QuestionOption(id: "one", label: "First", description: "First choice"),
            QuestionOption(id: "two", label: "Second", description: "Second choice")
        ],
        allowsMultiple: allowsMultiple
    )
}

private func decodeJSON(_ source: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8))
}

private func temporaryStore(state: PersistedAppState) throws -> AppStateStore {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bl00p-question-tests-\(UUID().uuidString)")
    let store = AppStateStore(
        fileURL: directory.appendingPathComponent("state.json")
    )
    store.save(state)
    return store
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Condition was not met before timeout")
}

private actor QuestionRecordingRuntime: AgentRuntime {
    private(set) var normalMessageCount = 0
    private(set) var questionResponseCount = 0
    let failQuestionResponse: Bool

    init(failQuestionResponse: Bool = false) {
        self.failQuestionResponse = failQuestionResponse
    }

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        let question = testQuestion(allowsMultiple: false)
        return AsyncStream { continuation in
            continuation.yield(.sessionID("question-session"))
            continuation.yield(
                .entry(
                    .init(
                        id: UUID(uuidString: "63FB1448-C8D7-42B8-A566-2964051492E8")!,
                        kind: .question,
                        title: question.header,
                        text: question.text,
                        question: question
                    )
                )
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
        normalMessageCount += 1
        return AsyncStream { $0.finish() }
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        AsyncStream { $0.finish() }
    }

    func resolveQuestion(
        entryID: UUID,
        answer: QuestionAnswer,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        questionResponseCount += 1
        return AsyncStream { continuation in
            if failQuestionResponse {
                continuation.yield(
                    .entry(
                        .init(
                            kind: .system,
                            text: "Could not send the answer"
                        )
                    )
                )
                continuation.yield(.status(.needsAnswer))
            } else {
                continuation.yield(
                    .questionResolved(entryID, answer, .answered)
                )
                continuation.yield(.status(.working))
            }
            continuation.finish()
        }
    }

    func stop(profile: BotProfile) async {}
}
