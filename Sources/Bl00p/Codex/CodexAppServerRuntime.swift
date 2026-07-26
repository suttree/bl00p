import Foundation

actor CodexAppServerRuntime: AgentRuntime {
    private struct PendingApproval: Sendable {
        let requestID: JSONValue
        let method: String
    }

    private struct CodexQuestion: Sendable {
        let id: String
        let header: String?
        let prompt: String
        let options: [String]
    }

    private struct PendingQuestion: Sendable {
        let requestID: JSONValue
        let questions: [CodexQuestion]
        var answers: [String: String] = [:]
        var currentIndex = 0
    }

    private struct Session {
        let client: CodexAppServerClient
        var threadID: String
        var approvalMode: ApprovalMode
        var currentTurnID: String?
        var lifecycleContinuation: AsyncStream<AgentEvent>.Continuation?
        var currentContinuation: AsyncStream<AgentEvent>.Continuation?
        var pendingQuestion: PendingQuestion?
        var pendingApprovals: [UUID: PendingApproval] = [:]
        var timelineIDs: [String: UUID] = [:]
        var diffEntryID: UUID?
        var listenerTask: Task<Void, Never>?
    }

    private let locator = CodexExecutableLocator()
    private var sessions: [UUID: Session] = [:]

    func start(
        profile: BotProfile,
        resumeThreadID: String?
    ) async -> AsyncStream<AgentEvent> {
        await stop(profile: profile)

        let pair = AsyncStream.makeStream(of: AgentEvent.self)
        pair.continuation.yield(.status(.launching))

        guard let workingDirectory = validatedDirectory(profile.workingDirectory) else {
            pair.continuation.yield(
                .entry(
                    .init(
                        kind: .system,
                        text: "Codex needs a working directory",
                        detail: "Open Bot Settings and choose the repository this bot should use."
                    )
                )
            )
            pair.continuation.yield(.status(.failed))
            pair.continuation.finish()
            return pair.stream
        }

        guard let executableURL = locator.locate() else {
            pair.continuation.yield(
                .entry(
                    .init(
                        kind: .system,
                        text: "Codex runtime not found",
                        detail: "Install Codex CLI or the ChatGPT desktop app, then launch the bot again."
                    )
                )
            )
            pair.continuation.yield(.status(.failed))
            pair.continuation.finish()
            return pair.stream
        }

        let client = CodexAppServerClient(executableURL: executableURL)

        do {
            let userAgent = try await client.connect()
            let listener = Task { [weak self] in
                for await message in client.messages {
                    guard !Task.isCancelled else { break }
                    await self?.handle(message, profileID: profile.id)
                }
            }

            sessions[profile.id] = Session(
                client: client,
                threadID: "",
                approvalMode: profile.approvalMode,
                lifecycleContinuation: pair.continuation,
                listenerTask: listener
            )

            let result = try await openThread(
                client: client,
                profile: profile,
                workingDirectory: workingDirectory,
                resumeThreadID: resumeThreadID
            )

            guard let threadID = result["thread"]?["id"]?.stringValue else {
                throw CodexAppServerError.invalidResponse(result.compactDescription)
            }

            if var session = sessions[profile.id] {
                session.threadID = threadID
                sessions[profile.id] = session
            }

            pair.continuation.yield(.sessionID(threadID))
            pair.continuation.yield(
                .entry(
                    .init(
                        kind: .system,
                        text: resumeThreadID == threadID
                            ? "Resumed Codex session"
                            : "Connected to Codex app-server",
                        detail: "\(userAgent) · Read-only · \(workingDirectory)"
                    )
                )
            )
            pair.continuation.yield(
                .entry(
                    .init(
                        kind: .question,
                        title: "What should I work on?",
                        text: "Give this bot its next task. Codex can use the git and MCP connections already configured for this account."
                    )
                )
            )
            pair.continuation.yield(.status(.needsAnswer))
            // Keep `pair.continuation` open and attached to `lifecycleContinuation`
            // so a later idle disconnect (no turn in progress) still has a
            // continuation to report through; see `closeSession`.
        } catch {
            await client.stop()
            sessions[profile.id]?.listenerTask?.cancel()
            sessions[profile.id] = nil
            pair.continuation.yield(
                .entry(
                    .init(
                        kind: .system,
                        text: "Could not launch Codex",
                        detail: error.localizedDescription
                    )
                )
            )
            pair.continuation.yield(.status(.failed))
            pair.continuation.finish()
        }

        return pair.stream
    }

    func respond(
        to message: String,
        attachments: [ImageAttachment],
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        guard var session = sessions[profile.id] else {
            return singleEventStream(
                .entry(
                    .init(
                        kind: .system,
                        text: "Codex is not connected. Launch it before sending work."
                    )
                ),
                finalStatus: .failed
            )
        }

        if let pendingQuestion = session.pendingQuestion {
            guard attachments.isEmpty else {
                return singleEventStream(
                    .entry(
                        .init(
                            kind: .system,
                            text: "Codex can't accept image attachments while answering a question.",
                            detail: "Remove the attachment and resend your answer as text."
                        )
                    ),
                    finalStatus: .needsAnswer
                )
            }

            var updatedQuestion = pendingQuestion
            let currentQuestion = updatedQuestion.questions[updatedQuestion.currentIndex]
            updatedQuestion.answers[currentQuestion.id] = message

            if updatedQuestion.currentIndex + 1 < updatedQuestion.questions.count {
                updatedQuestion.currentIndex += 1
                session.pendingQuestion = updatedQuestion
                sessions[profile.id] = session
                session.currentContinuation?.yield(
                    .entry(questionEntry(for: updatedQuestion.questions[updatedQuestion.currentIndex]))
                )
                session.currentContinuation?.yield(.status(.needsAnswer))
                return emptyStream()
            }

            do {
                let answers = Dictionary(
                    uniqueKeysWithValues: updatedQuestion.answers.map {
                        ($0.key, JSONValue.object(["answers": .array([.string($0.value)])]))
                    }
                )
                try await session.client.respond(
                    to: pendingQuestion.requestID,
                    result: .object(["answers": .object(answers)])
                )
                guard var connectedSession = sessions[profile.id] else {
                    return singleEventStream(
                        .entry(
                            .init(
                                kind: .system,
                                text: "Codex disconnected before receiving the answer."
                            )
                        ),
                        finalStatus: .failed
                    )
                }
                connectedSession.pendingQuestion = nil
                connectedSession.currentContinuation?.yield(.status(.working))
                sessions[profile.id] = connectedSession
                return emptyStream()
            } catch {
                return singleEventStream(
                    .entry(
                        .init(
                            kind: .system,
                            text: "Could not answer Codex",
                            detail: error.localizedDescription
                        )
                    ),
                    finalStatus: .failed
                )
            }
        }

        guard session.currentContinuation == nil else {
            return singleEventStream(
                .entry(
                    .init(
                        kind: .system,
                        text: "Codex is still working on the current task."
                    )
                ),
                finalStatus: nil
            )
        }

        let pair = AsyncStream.makeStream(of: AgentEvent.self)
        session.currentContinuation = pair.continuation
        session.diffEntryID = nil
        sessions[profile.id] = session
        pair.continuation.yield(.status(.working))

        do {
            let request = CodexTurnRequest.make(
                threadID: session.threadID,
                message: message,
                attachments: attachments,
                modelID: profile.modelID
            )
            let result = try await session.client.request(
                method: request.method,
                params: request.params
            )

            if let turnID = result["turn"]?["id"]?.stringValue,
               var updated = sessions[profile.id] {
                updated.currentTurnID = turnID
                sessions[profile.id] = updated
            }
        } catch {
            if var updated = sessions[profile.id] {
                updated.currentContinuation?.yield(
                    .entry(
                        .init(
                            kind: .system,
                            text: "Codex could not start the task",
                            detail: error.localizedDescription
                        )
                    )
                )
                updated.currentContinuation?.yield(.status(.failed))
                updated.currentContinuation?.finish()
                updated.currentContinuation = nil
                sessions[profile.id] = updated
            }
        }

        return pair.stream
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        guard let session = sessions[profile.id],
              let pending = session.pendingApprovals[entryID] else {
            return emptyStream()
        }

        do {
            try await session.client.respond(
                to: pending.requestID,
                result: .object([
                    "decision": .string(approved ? "accept" : "decline")
                ])
            )
            guard var connectedSession = sessions[profile.id],
                  connectedSession.pendingApprovals[entryID] != nil else {
                return singleEventStream(
                    .entry(
                        .init(
                            kind: .system,
                            text: "Codex disconnected before receiving the approval decision."
                        )
                    ),
                    finalStatus: .failed
                )
            }
            connectedSession.pendingApprovals.removeValue(forKey: entryID)
            connectedSession.currentContinuation?.yield(
                .approvalResolved(entryID, approved ? .approved : .declined)
            )
            connectedSession.currentContinuation?.yield(.status(approved ? .working : .needsAnswer))
            sessions[profile.id] = connectedSession
            return emptyStream()
        } catch {
            return singleEventStream(
                .entry(
                    .init(
                        kind: .system,
                        text: "Could not send the approval decision",
                        detail: error.localizedDescription
                    )
                ),
                finalStatus: .needsApproval
            )
        }
    }

    func stop(profile: BotProfile) async {
        guard let session = sessions.removeValue(forKey: profile.id) else { return }
        session.listenerTask?.cancel()
        session.currentContinuation?.finish()
        session.lifecycleContinuation?.finish()

        if let turnID = session.currentTurnID {
            _ = try? await session.client.request(
                method: "turn/interrupt",
                params: [
                    "threadId": .string(session.threadID),
                    "turnId": .string(turnID)
                ],
                timeout: .seconds(2)
            )
        }

        await session.client.stop()
    }

    private func openThread(
        client: CodexAppServerClient,
        profile: BotProfile,
        workingDirectory: String,
        resumeThreadID: String?
    ) async throws -> JSONValue {
        let shared = CodexThreadConfiguration.parameters(
            profile: profile,
            workingDirectory: workingDirectory
        )

        if let resumeThreadID {
            do {
                var resume = shared
                resume["threadId"] = .string(resumeThreadID)
                return try await client.request(method: "thread/resume", params: resume)
            } catch {
                // A stale or incompatible local thread should not prevent the
                // bot from launching; start a new one below.
            }
        }

        var start = shared
        start["serviceName"] = .string("bl00p")
        start["threadSource"] = .string("bl00p")
        start["ephemeral"] = .bool(false)
        return try await client.request(method: "thread/start", params: start)
    }

    private func handle(_ message: JSONValue, profileID: UUID) async {
        guard let method = message["method"]?.stringValue else { return }

        if message["id"] != nil {
            await handleServerRequest(message, method: method, profileID: profileID)
            return
        }

        let params = message["params"] ?? .object([:])

        switch method {
        case "item/started":
            handleItem(params["item"], completed: false, profileID: profileID)

        case "item/completed":
            handleItem(params["item"], completed: true, profileID: profileID)

        case "turn/diff/updated":
            handleDiff(params, profileID: profileID)

        case "turn/completed":
            handleTurnCompleted(params, profileID: profileID)

        case "error", "warning", "guardianWarning", "configWarning", "deprecationNotice":
            let detail = params["message"]?.stringValue
                ?? params["error"]?["message"]?.stringValue
                ?? params.compactDescription
            yield(
                .entry(
                    .init(
                        kind: .system,
                        text: method == "error" ? "Codex reported an error" : "Codex notice",
                        detail: detail
                    )
                ),
                profileID: profileID
            )

        case "transport/decodeError":
            let detail = [
                params["message"]?.stringValue,
                params["rawLine"]?.stringValue
            ]
                .compactMap { $0 }
                .joined(separator: "\n")
            yield(
                .entry(
                    .init(
                        kind: .system,
                        text: "Skipped an unreadable Codex event",
                        detail: detail
                    )
                ),
                profileID: profileID
            )

        case "transport/closed":
            let detail = params["message"]?.stringValue ?? params.compactDescription
            closeSession(profileID: profileID, detail: detail)

        default:
            break
        }
    }

    private func handleServerRequest(
        _ message: JSONValue,
        method: String,
        profileID: UUID
    ) async {
        guard let requestID = message["id"],
              var session = sessions[profileID] else { return }
        let params = message["params"] ?? .object([:])

        switch method {
        case "item/commandExecution/requestApproval":
            let command = params["command"]?.stringValue ?? "Command requested by Codex"
            let detail = [
                params["reason"]?.stringValue,
                params["cwd"]?.stringValue
            ]
                .compactMap { $0 }
                .joined(separator: "\n")

            if session.approvalMode == .auto {
                await autoApprove(
                    requestID: requestID,
                    logText: "Auto-approved command",
                    logDetail: detail.isEmpty ? command : "\(command)\n\(detail)",
                    session: session,
                    profileID: profileID
                )
                return
            }

            let entryID = UUID()
            session.pendingApprovals[entryID] = PendingApproval(
                requestID: requestID,
                method: method
            )
            session.currentContinuation?.yield(
                .entry(
                    .init(
                        id: entryID,
                        kind: .approval,
                        title: "Codex requests approval",
                        text: command,
                        detail: detail.isEmpty ? nil : detail,
                        approvalState: .pending
                    )
                )
            )
            session.currentContinuation?.yield(.status(.needsApproval))

        case "item/fileChange/requestApproval":
            let reason = params["reason"]?.stringValue
                ?? "Codex requested permission to change files."

            if session.approvalMode == .auto {
                await autoApprove(
                    requestID: requestID,
                    logText: "Auto-approved file change",
                    logDetail: [reason, params["grantRoot"]?.stringValue]
                        .compactMap { $0 }
                        .joined(separator: "\n"),
                    session: session,
                    profileID: profileID
                )
                return
            }

            let entryID = UUID()
            session.pendingApprovals[entryID] = PendingApproval(
                requestID: requestID,
                method: method
            )
            session.currentContinuation?.yield(
                .entry(
                    .init(
                        id: entryID,
                        kind: .approval,
                        title: "File change approval",
                        text: reason,
                        detail: params["grantRoot"]?.stringValue,
                        approvalState: .pending
                    )
                )
            )
            session.currentContinuation?.yield(.status(.needsApproval))

        case "item/tool/requestUserInput":
            let questions: [CodexQuestion] = (params["questions"]?.arrayValue ?? []).compactMap { question in
                guard let id = question["id"]?.stringValue else { return nil }
                return CodexQuestion(
                    id: id,
                    header: question["header"]?.stringValue,
                    prompt: question["question"]?.stringValue ?? "Codex needs your input.",
                    options: question["options"]?.arrayValue?
                        .compactMap { $0["label"]?.stringValue } ?? []
                )
            }

            guard let firstQuestion = questions.first else {
                do {
                    try await session.client.respondError(
                        to: requestID,
                        code: -32602,
                        message: "requestUserInput did not include any valid questions"
                    )
                } catch {
                    yieldTransportError(error, profileID: profileID)
                }
                return
            }

            session.pendingQuestion = PendingQuestion(
                requestID: requestID,
                questions: questions
            )
            session.currentContinuation?.yield(
                .entry(questionEntry(for: firstQuestion))
            )
            session.currentContinuation?.yield(.status(.needsAnswer))

        default:
            do {
                try await session.client.respondError(
                    to: requestID,
                    code: -32601,
                    message: "bl00p does not support the \(method) request"
                )
            } catch {
                yieldTransportError(error, profileID: profileID)
            }
            return
        }

        sessions[profileID] = session
    }

    private func handleItem(
        _ item: JSONValue?,
        completed: Bool,
        profileID: UUID
    ) {
        guard let item,
              let type = item["type"]?.stringValue,
              let itemID = item["id"]?.stringValue,
              var session = sessions[profileID] else { return }

        let timelineID = session.timelineIDs[itemID] ?? UUID()
        session.timelineIDs[itemID] = timelineID

        let entry: TimelineEntry?
        switch type {
        case "agentMessage":
            guard completed, let text = item["text"]?.stringValue, !text.isEmpty else {
                sessions[profileID] = session
                return
            }
            entry = .init(
                id: timelineID,
                kind: .assistant,
                text: text
            )

        case "commandExecution":
            let command = item["command"]?.stringValue ?? "Running command"
            let cwd = item["cwd"]?.stringValue
            let output = item["aggregatedOutput"]?.stringValue
            let status = item["status"]?.stringValue
            let detail = [cwd, completed ? output?.trimmedForTimeline : status]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            entry = .init(
                id: timelineID,
                kind: .command,
                title: completed ? "Command finished" : "Running command",
                text: command,
                detail: detail.isEmpty ? nil : detail
            )

        case "mcpToolCall":
            let server = item["server"]?.stringValue ?? "MCP"
            let tool = item["tool"]?.stringValue ?? "tool"
            let status = item["status"]?.stringValue ?? (completed ? "completed" : "running")
            let error = item["error"]?["message"]?.stringValue
            entry = .init(
                id: timelineID,
                kind: .command,
                title: "\(server) · \(status)",
                text: tool,
                detail: error ?? item["arguments"]?.compactDescription
            )

        case "fileChange":
            entry = .init(
                id: timelineID,
                kind: .diff,
                title: completed ? "File changes" : "Preparing file changes",
                text: item["changes"]?.compactDescription ?? "Codex proposed file changes.",
                detail: item["status"]?.stringValue
            )

        case "plan":
            guard completed, let text = item["text"]?.stringValue, !text.isEmpty else {
                sessions[profileID] = session
                return
            }
            entry = .init(
                id: timelineID,
                kind: .system,
                text: "Review plan",
                detail: text
            )

        case "enteredReviewMode":
            entry = .init(
                id: timelineID,
                kind: .system,
                text: "Codex entered review mode",
                detail: item["review"]?.stringValue
            )

        case "exitedReviewMode":
            entry = .init(
                id: timelineID,
                kind: .system,
                text: "Codex completed review mode",
                detail: item["review"]?.stringValue
            )

        default:
            entry = nil
        }

        sessions[profileID] = session
        if let entry {
            yield(.upsertEntry(entry), profileID: profileID)
        }
    }

    private func handleDiff(_ params: JSONValue, profileID: UUID) {
        guard let diff = params["diff"]?.stringValue,
              !diff.isEmpty,
              var session = sessions[profileID] else { return }

        let entryID = session.diffEntryID ?? UUID()
        session.diffEntryID = entryID
        sessions[profileID] = session
        yield(
            .upsertEntry(
                .init(
                    id: entryID,
                    kind: .diff,
                    title: "Working diff",
                    text: diff.trimmedForTimeline
                )
            ),
            profileID: profileID
        )
    }

    private func handleTurnCompleted(_ params: JSONValue, profileID: UUID) {
        let status = params["turn"]?["status"]?.stringValue ?? "failed"
        if status == "completed" {
            finishTurn(profileID: profileID, status: .completed)
        } else if status == "interrupted" {
            yield(
                .entry(.init(kind: .system, text: "Codex turn interrupted.")),
                profileID: profileID
            )
            finishTurn(profileID: profileID, status: .stopped)
        } else {
            let detail = params["turn"]?["error"]?["message"]?.stringValue
            yield(
                .entry(
                    .init(
                        kind: .system,
                        text: "Codex turn failed",
                        detail: detail
                    )
                ),
                profileID: profileID
            )
            finishTurn(profileID: profileID, status: .failed)
        }
    }

    private func finishTurn(profileID: UUID, status: AgentStatus) {
        guard var session = sessions[profileID] else { return }
        session.currentContinuation?.yield(.status(status))
        session.currentContinuation?.finish()
        session.currentContinuation = nil
        session.currentTurnID = nil
        session.pendingQuestion = nil
        session.pendingApprovals.removeAll()
        sessions[profileID] = session
    }

    private func closeSession(profileID: UUID, detail: String) {
        guard let session = sessions.removeValue(forKey: profileID) else { return }
        let continuation = session.currentContinuation ?? session.lifecycleContinuation
        continuation?.yield(
            .entry(
                .init(
                    kind: .system,
                    text: "Codex connection closed",
                    detail: detail
                )
            )
        )
        continuation?.yield(.status(.failed))
        session.currentContinuation?.finish()
        session.lifecycleContinuation?.finish()
        session.listenerTask?.cancel()
    }

    private func autoApprove(
        requestID: JSONValue,
        logText: String,
        logDetail: String,
        session: Session,
        profileID: UUID
    ) async {
        do {
            try await session.client.respond(
                to: requestID,
                result: .object(["decision": .string("accept")])
            )
        } catch {
            yieldTransportError(error, profileID: profileID)
            return
        }
        yield(
            .entry(
                .init(
                    kind: .system,
                    text: logText,
                    detail: logDetail.isEmpty ? nil : logDetail
                )
            ),
            profileID: profileID
        )
    }

    private func questionEntry(for question: CodexQuestion) -> TimelineEntry {
        let options = question.options.isEmpty
            ? nil
            : "Options: \(question.options.joined(separator: " · "))"
        return .init(
            kind: .question,
            title: question.header ?? "Codex has a question",
            text: [question.prompt, options]
                .compactMap { $0 }
                .joined(separator: "\n")
        )
    }

    private func yieldTransportError(_ error: any Error, profileID: UUID) {
        yield(
            .entry(
                .init(
                    kind: .system,
                    text: "Could not answer Codex app-server",
                    detail: error.localizedDescription
                )
            ),
            profileID: profileID
        )
    }

    private func yield(_ event: AgentEvent, profileID: UUID) {
        sessions[profileID]?.currentContinuation?.yield(event)
    }

    private func validatedDirectory(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func emptyStream() -> AsyncStream<AgentEvent> {
        AsyncStream { $0.finish() }
    }

    private func singleEventStream(
        _ event: AgentEvent,
        finalStatus: AgentStatus?
    ) -> AsyncStream<AgentEvent> {
        AsyncStream { continuation in
            continuation.yield(event)
            if let finalStatus {
                continuation.yield(.status(finalStatus))
            }
            continuation.finish()
        }
    }
}

struct CodexTurnRequest {
    let method: String
    let params: [String: JSONValue]

    static func make(
        threadID: String,
        message: String,
        attachments: [ImageAttachment],
        modelID: String?
    ) -> CodexTurnRequest {
        var input: [JSONValue] = []
        if !message.isEmpty {
            input.append(
                .object([
                    "type": .string("text"),
                    "text": .string(message),
                    "text_elements": .array([])
                ])
            )
        }
        input.append(
            contentsOf: attachments.map {
                .object([
                    "type": .string("localImage"),
                    "path": .string($0.path)
                ])
            }
        )

        var params: [String: JSONValue] = [
            "threadId": .string(threadID),
            "input": .array(input)
        ]
        if let modelID, !modelID.isEmpty {
            params["model"] = .string(modelID)
        }
        return CodexTurnRequest(method: "turn/start", params: params)
    }
}

enum CodexThreadConfiguration {
    static let turnModeVersion = 1

    static func parameters(
        profile: BotProfile,
        workingDirectory: String
    ) -> [String: JSONValue] {
        var parameters: [String: JSONValue] = [
            "cwd": .string(workingDirectory),
            "runtimeWorkspaceRoots": .array([.string(workingDirectory)]),
            "approvalPolicy": .string(profile.approvalMode == .auto ? "never" : "on-request"),
            "approvalsReviewer": .string("user"),
            "sandbox": .string("read-only"),
            "developerInstructions": .string(profile.instructions)
        ]
        if let modelID = profile.modelID, !modelID.isEmpty {
            parameters["model"] = .string(modelID)
        }
        return parameters
    }
}

private extension String {
    var trimmedForTimeline: String {
        let limit = 3_000
        guard count > limit else { return self }
        return String(prefix(1_900))
            + "\n…output truncated by bl00p…\n"
            + String(suffix(900))
    }
}
