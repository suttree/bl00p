import Foundation

actor ClaudeRuntime: AgentRuntime {
    private struct PendingApproval: Sendable {
        let requestID: String
        let toolInput: JSONValue
    }

    private struct PendingTurn {
        let message: String
        let attachments: [ImageAttachment]
        let profile: BotProfile
        var didFallBackToFreshSession = false
    }

    private struct Session {
        let executableURL: URL
        let workingDirectory: URL
        let approvalMode: ApprovalMode
        let role: AgentRole
        var sessionID: String
        var shouldResume: Bool
        var currentClient: (any ClaudeClient)?
        var currentContinuation: AsyncStream<AgentEvent>.Continuation?
        var listenerTask: Task<Void, Never>?
        var currentAttemptID: UUID?
        var pendingTurn: PendingTurn?
        var toolEntries: [String: TimelineEntry] = [:]
        var assistantTexts: Set<String> = []
        var receivedResult = false
        var stagedAttachmentDirectory: URL?
        var pendingApprovals: [UUID: PendingApproval] = [:]
        var handledControlRequestIDs: Set<String> = []
    }

    private let locator: ClaudeExecutableLocator
    private let authenticationStatusOverride: (@Sendable (URL) -> AuthenticationStatus)?
    private let clientFactory: @Sendable (URL) -> any ClaudeClient
    private var sessions: [UUID: Session] = [:]

    init(
        locator: ClaudeExecutableLocator = ClaudeExecutableLocator(),
        authenticationStatus: (@Sendable (URL) -> AuthenticationStatus)? = nil,
        clientFactory: @escaping @Sendable (URL) -> any ClaudeClient = {
            ClaudeCLIClient(executableURL: $0)
        }
    ) {
        self.locator = locator
        authenticationStatusOverride = authenticationStatus
        self.clientFactory = clientFactory
    }

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
                        text: "Claude needs a working directory",
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
                        text: "Claude CLI not found",
                        detail: "Install Claude Code, then launch this bot again."
                    )
                )
            )
            pair.continuation.yield(.status(.failed))
            pair.continuation.finish()
            return pair.stream
        }

        switch authenticationStatus(executableURL: executableURL) {
        case .loggedOut:
            pair.continuation.yield(
                .entry(
                    .init(
                        kind: .system,
                        text: "Claude needs you to log in",
                        detail: "Run `claude auth login` in Terminal, complete the browser flow, then launch this bot again."
                    )
                )
            )
            pair.continuation.yield(.status(.failed))
            pair.continuation.finish()
            return pair.stream

        case .unavailable(let detail):
            pair.continuation.yield(
                .entry(
                    .init(
                        kind: .system,
                        text: "Could not check Claude authentication",
                        detail: detail
                    )
                )
            )
            pair.continuation.yield(.status(.failed))
            pair.continuation.finish()
            return pair.stream

        case .loggedIn:
            break
        }

        let resumedID = resumeThreadID.flatMap { UUID(uuidString: $0) }.map(\.uuidString)
        let sessionID = resumedID ?? UUID().uuidString.lowercased()
        sessions[profile.id] = Session(
            executableURL: executableURL,
            workingDirectory: workingDirectory,
            approvalMode: profile.approvalMode,
            role: profile.role,
            sessionID: sessionID,
            shouldResume: resumedID != nil
        )

        pair.continuation.yield(.sessionID(sessionID))
        pair.continuation.yield(.entry(openingQuestion(for: profile.role)))
        pair.continuation.yield(.status(.needsAnswer))
        pair.continuation.finish()
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
                        text: "Launch this Claude bot before sending a message."
                    )
                ),
                finalStatus: .failed
            )
        }

        guard session.currentContinuation == nil else {
            return singleEventStream(
                .entry(
                    .init(
                        kind: .system,
                        text: "Claude is already working on this turn."
                    )
                ),
                finalStatus: nil
            )
        }

        let pair = AsyncStream.makeStream(of: AgentEvent.self)
        session.currentContinuation = pair.continuation
        session.pendingTurn = PendingTurn(
            message: message,
            attachments: attachments,
            profile: profile
        )
        session.toolEntries.removeAll()
        session.assistantTexts.removeAll()
        session.receivedResult = false
        session.pendingApprovals.removeAll()
        session.handledControlRequestIDs.removeAll()
        sessions[profile.id] = session
        pair.continuation.yield(.status(.working))

        do {
            try await launchClient(for: profile.id)
        } catch {
            failTurnToStart(profileID: profile.id, error: error)
        }

        return pair.stream
    }

    func resolveApproval(
        entryID: UUID,
        approved: Bool,
        profile: BotProfile
    ) async -> AsyncStream<AgentEvent> {
        guard let session = sessions[profile.id],
              let client = session.currentClient,
              let pending = session.pendingApprovals[entryID] else {
            return emptyStream()
        }

        do {
            try await client.respond(
                to: pending.requestID,
                result: ClaudeToolApprovalResponse.result(
                    approved: approved,
                    toolInput: pending.toolInput
                )
            )
            guard var activeSession = sessions[profile.id],
                  activeSession.pendingApprovals[entryID] != nil else {
                return singleEventStream(
                    .entry(
                        .init(
                            kind: .system,
                            text: "Claude stopped before receiving the approval decision."
                        )
                    ),
                    finalStatus: .failed
                )
            }

            activeSession.pendingApprovals.removeValue(forKey: entryID)
            activeSession.currentContinuation?.yield(
                .approvalResolved(entryID, approved ? .approved : .declined)
            )
            activeSession.currentContinuation?.yield(
                .status(
                    activeSession.pendingApprovals.isEmpty
                        ? .working
                        : .needsApproval
                )
            )
            sessions[profile.id] = activeSession
            return emptyStream()
        } catch {
            return singleEventStream(
                .entry(
                    .init(
                        kind: .system,
                        text: "Could not send the Claude approval decision",
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
        if let directory = session.stagedAttachmentDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
        if let client = session.currentClient {
            await client.stop()
        }
    }

    private func launchClient(for profileID: UUID) async throws {
        guard var session = sessions[profileID],
              let pendingTurn = session.pendingTurn else {
            throw ClaudeCLIError.processLaunch("The pending turn was lost.")
        }

        if let staleDirectory = session.stagedAttachmentDirectory {
            try? FileManager.default.removeItem(at: staleDirectory)
            session.stagedAttachmentDirectory = nil
        }

        let attemptID = UUID()
        let client = clientFactory(session.executableURL)
        let invocation = try ClaudeInvocation(
            sessionID: session.sessionID,
            resume: session.shouldResume,
            profile: pendingTurn.profile,
            prompt: pendingTurn.message,
            attachments: pendingTurn.attachments
        )
        let listener = Task { [weak self] in
            for await event in client.messages {
                guard !Task.isCancelled else { break }
                await self?.handle(
                    event,
                    profileID: profileID,
                    attemptID: attemptID
                )
            }
        }

        session.currentClient = client
        session.listenerTask = listener
        session.currentAttemptID = attemptID
        session.stagedAttachmentDirectory = invocation.stagedAttachmentDirectory
        sessions[profileID] = session

        do {
            try await client.connect(
                arguments: invocation.arguments,
                workingDirectory: session.workingDirectory
            )
            try await client.send(invocation.inputMessage)
        } catch {
            listener.cancel()
            await client.stop()
            throw error
        }
    }

    private func failTurnToStart(profileID: UUID, error: any Error) {
        guard var session = sessions[profileID] else { return }
        session.currentContinuation?.yield(
            .entry(
                .init(
                    kind: .system,
                    text: "Could not start Claude",
                    detail: error.localizedDescription
                )
            )
        )
        session.currentContinuation?.yield(.status(.failed))
        session.currentContinuation?.finish()
        clearTurnState(&session, cancelListener: true)
        sessions[profileID] = session
    }

    private func handle(
        _ event: JSONValue,
        profileID: UUID,
        attemptID: UUID
    ) async {
        guard let type = event["type"]?.stringValue,
              sessions[profileID]?.currentAttemptID == attemptID else { return }

        switch type {
        case "system":
            handleSystem(event, profileID: profileID)

        case "assistant":
            handleAssistant(event, profileID: profileID)

        case "user":
            handleToolResults(event, profileID: profileID)

        case "result":
            await handleResult(event, profileID: profileID)

        case "control_request":
            await handleControlRequest(event, profileID: profileID)

        case "control_cancel_request":
            handleControlCancellation(event, profileID: profileID)

        case "transport_decode_error":
            yield(
                .entry(
                    .init(
                        kind: .system,
                        text: "Skipped an unreadable Claude event",
                        detail: [
                            event["message"]?.stringValue,
                            event["raw_line"]?.stringValue
                        ]
                            .compactMap { $0 }
                            .joined(separator: "\n")
                    )
                ),
                profileID: profileID
            )

        case "transport_closed":
            handleTransportClosed(event, profileID: profileID)

        default:
            break
        }
    }

    private func handleControlRequest(
        _ event: JSONValue,
        profileID: UUID
    ) async {
        guard let requestID = event["request_id"]?.stringValue,
              let request = event["request"],
              let subtype = request["subtype"]?.stringValue,
              var session = sessions[profileID],
              let client = session.currentClient else { return }

        guard subtype == "can_use_tool",
              let approval = ClaudeToolApprovalRequest(request: request) else {
            do {
                try await client.respondError(
                    to: requestID,
                    message: "bl00p does not support Claude control request: \(subtype)"
                )
            } catch {
                yield(
                    .entry(
                        .init(
                            kind: .system,
                            text: "Could not answer Claude's control request",
                            detail: error.localizedDescription
                        )
                    ),
                    profileID: profileID
                )
            }
            return
        }

        guard !session.pendingApprovals.values.contains(where: {
            $0.requestID == requestID
        }),
        !session.handledControlRequestIDs.contains(requestID) else { return }

        session.handledControlRequestIDs.insert(requestID)
        sessions[profileID] = session

        let decision = ClaudeToolApprovalPolicy.decision(
            for: approval,
            mode: session.approvalMode,
            role: session.role,
            workingDirectory: session.workingDirectory,
            stagedAttachmentDirectory: session.stagedAttachmentDirectory
        )

        switch decision {
        case .allow:
            do {
                try await client.respond(
                    to: requestID,
                    result: ClaudeToolApprovalResponse.result(
                        approved: true,
                        toolInput: approval.toolInput
                    )
                )
                yield(
                    .entry(approval.autoApprovalEntry()),
                    profileID: profileID
                )
            } catch {
                await failAutomaticControlResponse(
                    profileID: profileID,
                    text: "Could not auto-approve Claude's action",
                    action: approval.primaryAction,
                    error: error
                )
            }
            return

        case .deny(let reason):
            do {
                try await client.respond(
                    to: requestID,
                    result: ClaudeToolApprovalResponse.deniedByPolicy(reason)
                )
                yield(
                    .entry(approval.blockedEntry(reason: reason)),
                    profileID: profileID
                )
            } catch {
                await failAutomaticControlResponse(
                    profileID: profileID,
                    text: "Could not enforce Claude's approval boundary",
                    action: approval.primaryAction,
                    error: error
                )
            }
            return

        case .ask:
            let entry = approval.timelineEntry()
            session.pendingApprovals[entry.id] = PendingApproval(
                requestID: requestID,
                toolInput: approval.toolInput
            )
            sessions[profileID] = session
            session.currentContinuation?.yield(.entry(entry))
            session.currentContinuation?.yield(.status(.needsApproval))
        }
    }

    private func failAutomaticControlResponse(
        profileID: UUID,
        text: String,
        action: String,
        error: any Error
    ) async {
        guard var session = sessions[profileID] else { return }
        let client = session.currentClient
        session.currentContinuation?.yield(
            .entry(
                .init(
                    kind: .system,
                    title: "Claude permission response failed",
                    text: text,
                    detail: "\(action)\n\(error.localizedDescription)"
                )
            )
        )
        session.currentContinuation?.yield(.status(.failed))
        session.currentContinuation?.finish()
        clearTurnState(&session, cancelListener: true)
        sessions[profileID] = session
        if let client {
            await client.stop()
        }
    }

    private func handleControlCancellation(
        _ event: JSONValue,
        profileID: UUID
    ) {
        guard let requestID = event["request_id"]?.stringValue,
              var session = sessions[profileID],
              let cancelled = session.pendingApprovals.first(where: {
                  $0.value.requestID == requestID
              }) else { return }

        session.pendingApprovals.removeValue(forKey: cancelled.key)
        session.currentContinuation?.yield(
            .approvalResolved(cancelled.key, .declined)
        )
        session.currentContinuation?.yield(
            .status(
                session.pendingApprovals.isEmpty
                    ? .working
                    : .needsApproval
            )
        )
        sessions[profileID] = session
    }

    private func handleSystem(_ event: JSONValue, profileID: UUID) {
        guard event["subtype"]?.stringValue == "init" else { return }

        if let sessionID = event["session_id"]?.stringValue,
           var session = sessions[profileID] {
            session.sessionID = sessionID
            session.shouldResume = true
            sessions[profileID] = session
            yield(.sessionID(sessionID), profileID: profileID)
        }

        let model = event["model"]?.stringValue
        let serverCount = event["mcp_servers"]?.arrayValue?.count ?? 0
        yield(
            .entry(
                .init(
                    kind: .system,
                    text: "Claude turn started",
                    detail: [
                        model,
                        "\(serverCount) MCP server\(serverCount == 1 ? "" : "s") loaded"
                    ]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                )
            ),
            profileID: profileID
        )
    }

    private func handleAssistant(_ event: JSONValue, profileID: UUID) {
        guard let content = event["message"]?["content"]?.arrayValue else { return }

        for block in content {
            switch block["type"]?.stringValue {
            case "text":
                guard let text = block["text"]?.stringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !text.isEmpty,
                    var session = sessions[profileID],
                    !session.assistantTexts.contains(text) else { continue }

                session.assistantTexts.insert(text)
                sessions[profileID] = session
                yield(.entry(.init(kind: .assistant, text: text)), profileID: profileID)

            case "tool_use":
                handleToolUse(block, profileID: profileID)

            default:
                continue
            }
        }
    }

    private func handleToolUse(_ block: JSONValue, profileID: UUID) {
        guard let toolID = block["id"]?.stringValue,
              let name = block["name"]?.stringValue,
              var session = sessions[profileID] else { return }

        let input = block["input"] ?? .object([:])
        let existingID = session.toolEntries[toolID]?.id ?? UUID()
        let entry = toolEntry(
            id: existingID,
            name: name,
            input: input,
            result: nil,
            isError: false
        )
        session.toolEntries[toolID] = entry
        sessions[profileID] = session
        yield(.upsertEntry(entry), profileID: profileID)
    }

    private func handleToolResults(_ event: JSONValue, profileID: UUID) {
        guard let content = event["message"]?["content"]?.arrayValue else { return }

        for block in content where block["type"]?.stringValue == "tool_result" {
            guard let toolID = block["tool_use_id"]?.stringValue,
                  var session = sessions[profileID],
                  let previous = session.toolEntries[toolID] else { continue }

            let result = readableContent(block["content"])
            var entry = previous
            entry.title = (block["is_error"]?.boolValue == true)
                ? "Tool failed"
                : "Tool finished"
            if !result.isEmpty {
                entry.detail = result.trimmedForClaudeTimeline
            }
            session.toolEntries[toolID] = entry
            sessions[profileID] = session
            yield(.upsertEntry(entry), profileID: profileID)
        }
    }

    private func handleResult(_ event: JSONValue, profileID: UUID) async {
        guard var session = sessions[profileID] else { return }
        session.receivedResult = true
        let failed = event["is_error"]?.boolValue == true
        let result = event["result"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let errors = event["errors"]?.arrayValue?
            .compactMap(\.stringValue)
            .joined(separator: "\n")
        let failureDetail = result?.isEmpty == false ? result : errors
        let permissionDenials = event["permission_denials"]?.arrayValue ?? []

        if failed,
           session.shouldResume,
           session.pendingTurn?.didFallBackToFreshSession == false,
           ClaudeResumeRecovery.shouldStartFresh(after: event) {
            if let client = session.currentClient {
                await client.stop()
            }
            let replacementID = UUID().uuidString.lowercased()
            session.sessionID = replacementID
            session.shouldResume = false
            session.currentClient = nil
            session.listenerTask = nil
            session.currentAttemptID = nil
            session.receivedResult = false
            session.handledControlRequestIDs.removeAll()
            session.pendingTurn?.didFallBackToFreshSession = true
            sessions[profileID] = session

            yield(
                .entry(
                    .init(
                        kind: .system,
                        text: "Claude session recovered",
                        detail: "The saved Claude conversation could not be reopened, so bl00p continued in a fresh session while keeping this transcript."
                    )
                ),
                profileID: profileID
            )
            yield(.sessionID(replacementID), profileID: profileID)

            do {
                try await launchClient(for: profileID)
            } catch {
                failTurnToStart(profileID: profileID, error: error)
            }
            return
        }

        if failed {
            yield(
                .entry(
                    .init(
                        kind: .system,
                        text: result == "Not logged in · Please run /login"
                            ? "Claude authentication expired"
                            : "Claude could not complete the turn",
                        detail: failureDetail
                    )
                ),
                profileID: profileID
            )
        } else if let result,
                  !result.isEmpty,
                  !session.assistantTexts.contains(result) {
            yield(.entry(.init(kind: .assistant, text: result)), profileID: profileID)
        }

        if !permissionDenials.isEmpty {
            yield(
                .entry(
                    .init(
                        kind: .question,
                        title: "Some actions were blocked",
                        text: "Claude could not run every requested action. Review its response, then tell it how you want to proceed.",
                        detail: ClaudePermissionDenials
                            .readableDetail(for: permissionDenials)
                    )
                ),
                profileID: profileID
            )
        }

        for entryID in session.pendingApprovals.keys {
            session.currentContinuation?.yield(
                .approvalResolved(entryID, .declined)
            )
        }
        session.pendingApprovals.removeAll()
        if let client = session.currentClient {
            await client.finishInput()
        }
        session.currentContinuation?.yield(
            .status(
                ClaudeTurnOutcome.status(
                    failed: failed,
                    permissionDenials: permissionDenials
                )
            )
        )
        session.currentContinuation?.finish()
        session.shouldResume = true
        clearTurnState(&session)
        sessions[profileID] = session
    }

    private func handleTransportClosed(_ event: JSONValue, profileID: UUID) {
        guard var session = sessions[profileID] else { return }
        defer {
            clearTurnState(&session)
            sessions[profileID] = session
        }

        guard session.currentContinuation != nil else { return }
        for entryID in session.pendingApprovals.keys {
            session.currentContinuation?.yield(
                .approvalResolved(entryID, .declined)
            )
        }
        let exitStatus = event["exit_status"]?.intValue ?? -1
        let stderr = event["stderr"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        session.currentContinuation?.yield(
            .entry(
                .init(
                    kind: .system,
                    text: "Claude CLI closed before returning a result",
                    detail: [
                        "Exit status \(exitStatus)",
                        stderr?.isEmpty == false ? stderr : nil
                    ]
                        .compactMap { $0 }
                        .joined(separator: "\n")
                )
            )
        )
        session.currentContinuation?.yield(.status(.failed))
        session.currentContinuation?.finish()
        session.currentContinuation = nil
    }

    private func clearTurnState(
        _ session: inout Session,
        cancelListener: Bool = false
    ) {
        if cancelListener {
            session.listenerTask?.cancel()
        }
        session.currentContinuation = nil
        session.currentClient = nil
        session.listenerTask = nil
        session.currentAttemptID = nil
        session.pendingTurn = nil
        session.pendingApprovals.removeAll()
        session.handledControlRequestIDs.removeAll()
        if let directory = session.stagedAttachmentDirectory {
            try? FileManager.default.removeItem(at: directory)
            session.stagedAttachmentDirectory = nil
        }
    }

    private func toolEntry(
        id: UUID,
        name: String,
        input: JSONValue,
        result: String?,
        isError: Bool
    ) -> TimelineEntry {
        let kind: TimelineKind
        let title: String
        let text: String

        switch name {
        case "Bash":
            kind = .command
            title = isError ? "Command failed" : "Running command"
            text = input["command"]?.stringValue ?? "Shell command"

        case "Edit", "Write", "NotebookEdit":
            kind = .diff
            title = isError ? "\(name) failed" : "\(name) · file change"
            text = input["file_path"]?.stringValue
                ?? input["notebook_path"]?.stringValue
                ?? "Preparing a file change"

        default:
            kind = .command
            title = isError ? "\(name) failed" : "Using \(name)"
            text = name
        }

        return .init(
            id: id,
            kind: kind,
            title: title,
            text: text,
            detail: result?.trimmedForClaudeTimeline ?? input.compactDescription
        )
    }

    private func readableContent(_ content: JSONValue?) -> String {
        guard let content else { return "" }
        if let string = content.stringValue {
            return string
        }
        if let blocks = content.arrayValue {
            return blocks
                .compactMap { block in
                    block["text"]?.stringValue
                        ?? block["content"]?.stringValue
                        ?? block.compactDescription
                }
                .joined(separator: "\n")
        }
        return content.compactDescription
    }

    private func openingQuestion(for role: AgentRole) -> TimelineEntry {
        switch role {
        case .builder:
            .init(
                kind: .question,
                title: "What should I build?",
                text: "Paste a ticket, describe the task, or provide a Linear issue reference."
            )
        case .reviewer:
            .init(
                kind: .question,
                title: "What should I review?",
                text: "Paste a PR URL, branch name, commit, or review handoff."
            )
        case .publisher:
            .init(
                kind: .question,
                title: "What should I prepare?",
                text: "Share the reviewed branch whose documentation and draft PR should be prepared."
            )
        case .manager:
            .init(
                kind: .question,
                title: "What should the team work on?",
                text: "Describe the outcome you want. I’ll prepare and coordinate the work when a team is configured."
            )
        }
    }

    private func authenticationStatus(executableURL: URL) -> AuthenticationStatus {
        if let authenticationStatusOverride {
            return authenticationStatusOverride(executableURL)
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["auth", "status"]
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            return value["loggedIn"]?.boolValue == true ? .loggedIn : .loggedOut
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    private func validatedDirectory(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private func yield(_ event: AgentEvent, profileID: UUID) {
        sessions[profileID]?.currentContinuation?.yield(event)
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

    private func emptyStream() -> AsyncStream<AgentEvent> {
        AsyncStream { $0.finish() }
    }
}
enum AuthenticationStatus: Sendable {
    case loggedIn
    case loggedOut
    case unavailable(String)
}

enum ClaudeResumeRecovery {
    static func shouldStartFresh(after event: JSONValue) -> Bool {
        guard event["is_error"]?.boolValue == true else { return false }

        let errors = event["errors"]?.arrayValue?
            .compactMap(\.stringValue)
            .joined(separator: "\n")
            .lowercased() ?? ""
        return errors.contains("no conversation found with session id")
            || errors.contains("failed to load conversation")
            || errors.contains("invalid session")
    }
}

enum ClaudeTurnOutcome {
    static func status(
        failed: Bool,
        permissionDenials: [JSONValue]
    ) -> AgentStatus {
        if failed {
            return .failed
        }
        return permissionDenials.isEmpty ? .completed : .needsAnswer
    }
}

enum ClaudePermissionDenials {
    static func readableDetail(for denials: [JSONValue]) -> String {
        let lines = denials.compactMap { denial -> String? in
            let input = denial["tool_input"]
            let command = input?["command"]?.stringValue
            let description = input?["description"]?.stringValue
            let tool = denial["tool_name"]?.stringValue

            if let command, !command.isEmpty {
                if let description, !description.isEmpty {
                    return "• \(description)\n  \(command)"
                }
                return "• \(command)"
            }
            if let tool, !tool.isEmpty {
                return "• \(tool)"
            }
            return nil
        }

        return lines.isEmpty
            ? "One or more actions were not permitted."
            : lines.joined(separator: "\n")
                .trimmedForClaudeTimeline
    }

    static func readableLegacyDetail(_ detail: String?) -> String {
        guard let detail, !detail.isEmpty else {
            return "One or more actions were not permitted."
        }
        let denials = detail
            .split(separator: "\n")
            .compactMap { line in
                try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
            }
        return readableDetail(for: denials)
    }
}

struct ClaudeToolApprovalRequest: Sendable {
    let toolName: String
    let toolInput: JSONValue
    let title: String?
    let displayName: String?
    let description: String?
    let decisionReason: String?
    let blockedPath: String?

    init?(request: JSONValue) {
        guard request["subtype"]?.stringValue == "can_use_tool",
              let toolName = request["tool_name"]?.stringValue,
              let toolInput = request["input"],
              toolInput.objectValue != nil else { return nil }
        self.toolName = toolName
        self.toolInput = toolInput
        title = request["title"]?.stringValue
        displayName = request["display_name"]?.stringValue
        description = request["description"]?.stringValue
        decisionReason = request["decision_reason"]?.stringValue
        blockedPath = request["blocked_path"]?.stringValue
    }

    func timelineEntry(id: UUID = UUID()) -> TimelineEntry {
        .init(
            id: id,
            kind: .approval,
            title: displayName ?? "\(toolName) approval",
            text: primaryAction,
            detail: detail,
            approvalState: .pending
        )
    }

    func autoApprovalEntry(id: UUID = UUID()) -> TimelineEntry {
        .init(
            id: id,
            kind: .system,
            title: "Auto-approved Claude action",
            text: primaryAction,
            detail: detail
        )
    }

    func blockedEntry(
        id: UUID = UUID(),
        reason: String
    ) -> TimelineEntry {
        .init(
            id: id,
            kind: .system,
            title: "Claude action blocked",
            text: primaryAction,
            detail: reason
        )
    }

    var primaryAction: String {
        toolInput["command"]?.stringValue
            ?? toolInput["file_path"]?.stringValue
            ?? toolInput["notebook_path"]?.stringValue
            ?? title
            ?? toolName
    }

    func requestedPaths(relativeTo workingDirectory: URL) -> [URL] {
        let inputPaths = Self.pathStrings(in: toolInput)
        return (inputPaths + [blockedPath].compactMap { $0 })
            .map { path in
                let expanded = (path as NSString).expandingTildeInPath
                if expanded.hasPrefix("/") {
                    return URL(fileURLWithPath: expanded)
                }
                return URL(
                    fileURLWithPath: expanded,
                    relativeTo: workingDirectory
                )
            }
            .map {
                $0.standardizedFileURL.resolvingSymlinksInPath()
            }
    }

    private static func pathStrings(in value: JSONValue) -> [String] {
        switch value {
        case .object(let object):
            return object.flatMap { key, nestedValue in
                let normalizedKey = key.lowercased()
                if [
                    "path", "paths", "file_path", "file_paths",
                    "notebook_path", "directory", "working_directory", "cwd"
                ].contains(normalizedKey) {
                    return stringValues(in: nestedValue)
                }
                return pathStrings(in: nestedValue)
            }
        case .array(let values):
            return values.flatMap(pathStrings)
        case .string, .number, .bool, .null:
            return []
        }
    }

    private static func stringValues(in value: JSONValue) -> [String] {
        switch value {
        case .string(let string):
            return [string]
        case .array(let values):
            return values.flatMap(stringValues)
        case .object, .number, .bool, .null:
            return []
        }
    }

    private var detail: String? {
        let values = [
            title == primaryAction ? nil : title,
            description,
            decisionReason,
            blockedPath.map { "Blocked path: \($0)" },
            toolInput.compactDescription == primaryAction
                ? nil
                : toolInput.compactDescription
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return values.isEmpty
            ? nil
            : values.joined(separator: "\n").trimmedForClaudeTimeline
    }
}

enum ClaudeToolApprovalResponse {
    static func deniedByPolicy(_ reason: String) -> JSONValue {
        .object([
            "behavior": .string("deny"),
            "message": .string(reason)
        ])
    }

    static func result(
        approved: Bool,
        toolInput: JSONValue
    ) -> JSONValue {
        if approved {
            return .object([
                "behavior": .string("allow"),
                "updatedInput": toolInput
            ])
        }
        return .object([
            "behavior": .string("deny"),
            "message": .string("The user declined this action in bl00p.")
        ])
    }
}

enum ClaudeToolApprovalDecision: Equatable, Sendable {
    case ask
    case allow
    case deny(String)
}

enum ClaudeToolApprovalPolicy {
    static func decision(
        for approval: ClaudeToolApprovalRequest,
        mode: ApprovalMode,
        role: AgentRole,
        workingDirectory: URL,
        stagedAttachmentDirectory: URL?
    ) -> ClaudeToolApprovalDecision {
        if role == .manager {
            return .deny(
                "Claude Managers are read-only and cannot escalate permissions."
            )
        }
        if role == .reviewer,
           ["Edit", "Write", "NotebookEdit"].contains(approval.toolName) {
            return .deny(
                "Claude Reviewers are read-only and cannot escalate permissions."
            )
        }
        guard mode == .auto else { return .ask }

        let roots = [workingDirectory, stagedAttachmentDirectory]
            .compactMap { $0 }
            .map(canonicalURL)
        let requestedPaths = approval.requestedPaths(
            relativeTo: workingDirectory
        )
        if let outsidePath = requestedPaths.first(where: {
            !isInsideAllowedRoots($0, roots: roots)
        }) {
            return .deny(
                "Auto-approval is limited to the selected workspace. This request targets \(outsidePath.path)."
            )
        }

        switch approval.toolName {
        case "Edit", "Write", "NotebookEdit":
            guard !requestedPaths.isEmpty else {
                return .deny(
                    "Auto-approval requires a verifiable file path inside the selected workspace."
                )
            }
            return .allow

        case "Bash":
            guard let command = approval.toolInput["command"]?.stringValue,
                  !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .deny(
                    "Auto-approval requires a readable shell command."
                )
            }
            return shellDecision(
                command,
                workingDirectory: workingDirectory,
                roots: roots
            )

        default:
            return .ask
        }
    }

    private static func shellDecision(
        _ command: String,
        workingDirectory: URL,
        roots: [URL]
    ) -> ClaudeToolApprovalDecision {
        let forbiddenSyntax = ["\n", ";", "&&", "||", "|", "`", "$(", ">", "<"]
        guard !forbiddenSyntax.contains(where: command.contains),
              !containsShellVariableSyntax(command) else {
            return .deny(
                "Compound commands, shell expansion, and redirection require explicit approval."
            )
        }

        let tokens = command
            .split(whereSeparator: \.isWhitespace)
            .map {
                String($0).trimmingCharacters(
                    in: CharacterSet(charactersIn: "\"'")
                )
            }
        guard !tokens.isEmpty else {
            return .deny("Auto-approval requires a readable shell command.")
        }

        if URL(fileURLWithPath: tokens[0]).lastPathComponent == "env"
            || tokens[0].contains("=") {
            return .deny(
                "Environment-prefixed commands require explicit approval."
            )
        }
        guard let executableToken = tokens.first else {
            return .deny("Auto-approval requires a readable shell command.")
        }
        guard !executableToken.contains("/") else {
            return .deny(
                "Commands launched through an explicit executable path require explicit approval."
            )
        }
        let executable = URL(fileURLWithPath: executableToken).lastPathComponent
        let arguments = Array(tokens.dropFirst())

        let pathArguments = arguments.compactMap {
            shellPath(
                from: $0,
                relativeTo: workingDirectory
            )
        }
        if let outsidePath = pathArguments.first(where: {
            !isInsideAllowedRoots($0, roots: roots)
        }) {
            return .deny(
                "Auto-approved shell commands cannot access paths outside the selected workspace: \(outsidePath.path)."
            )
        }

        let supported: Bool
        switch executable {
        case "grep", "ls", "pwd", "cat", "head", "tail", "wc",
             "stat", "file", "which", "type":
            supported = true

        case "rg":
            supported = !arguments.contains("--pre")
                && !arguments.contains(where: { $0.hasPrefix("--pre=") })

        case "find":
            supported = !arguments.contains(where: {
                [
                    "-delete", "-exec", "-execdir", "-ok", "-okdir",
                    "-fprint", "-fls", "-fprintf"
                ].contains($0)
            })

        case "git":
            supported = !arguments.contains("--ext-diff")
                && !arguments.contains("--textconv")
                && (arguments.first.map {
                [
                    "status", "diff", "log", "show", "rev-parse",
                    "merge-base", "ls-files", "grep"
                ].contains($0)
            } ?? false)

        case "swift":
            supported = ["test", "build", "--version"].contains(
                arguments.first ?? ""
            )

        case "xcrun":
            if arguments.first == "swift" {
                supported = ["test", "build", "--version"].contains(
                    arguments.dropFirst().first ?? ""
                )
            } else {
                supported = arguments.prefix(2) == ["--find", "swift"]
            }

        case "xcodebuild":
            supported = ["test", "build"].contains(arguments.first ?? "")

        case "npm":
            supported = arguments.first == "test"
                || arguments.prefix(2) == ["run", "test"]
                || arguments.prefix(2) == ["run", "lint"]
                || arguments.prefix(2) == ["run", "typecheck"]

        case "pnpm", "yarn":
            supported = ["test", "lint", "typecheck"].contains(
                arguments.first ?? ""
            )

        case "cargo":
            supported = arguments.first == "test"

        case "go":
            supported = arguments.first == "test"

        case "pytest":
            supported = true

        default:
            supported = false
        }

        return supported
            ? .allow
            : .deny(
                "\(executable) is outside Claude auto-approval's safe command set. Switch to Ask to review it explicitly."
            )
    }

    private static func shellPath(
        from argument: String,
        relativeTo workingDirectory: URL
    ) -> URL? {
        let cleaned = argument.trimmingCharacters(
            in: CharacterSet(charactersIn: "\"',")
        )
        guard !cleaned.isEmpty else {
            return nil
        }
        if cleaned.hasPrefix("--"),
           let separator = cleaned.firstIndex(of: "=") {
            let value = String(cleaned[cleaned.index(after: separator)...])
            guard !value.isEmpty else { return nil }
            return shellPath(from: value, relativeTo: workingDirectory)
        }
        if cleaned.hasPrefix("-f"), cleaned.count > 2 {
            return shellPath(
                from: String(cleaned.dropFirst(2)),
                relativeTo: workingDirectory
            )
        }
        guard !cleaned.hasPrefix("-"), !cleaned.contains("=") else {
            return nil
        }
        guard !cleaned.hasPrefix("~") else {
            return URL(fileURLWithPath: cleaned)
        }
        if cleaned.hasPrefix("/") {
            return canonicalURL(URL(fileURLWithPath: cleaned))
        }
        return canonicalURL(
            URL(fileURLWithPath: cleaned, relativeTo: workingDirectory)
        )
    }

    private static func containsShellVariableSyntax(_ command: String) -> Bool {
        let characters = Array(command)
        for index in characters.indices where characters[index] == "$" {
            guard index + 1 < characters.count else { continue }
            let next = characters[index + 1]
            if next.isLetter || next == "_" || next == "{" {
                return true
            }
        }
        return false
    }

    private static func isInsideAllowedRoots(
        _ url: URL,
        roots: [URL]
    ) -> Bool {
        let candidate = canonicalURL(url).path
        return roots.contains { root in
            candidate == root.path || candidate.hasPrefix(root.path + "/")
        }
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

private extension String {
    var trimmedForClaudeTimeline: String {
        let limit = 3_000
        guard count > limit else { return self }
        return String(prefix(1_900))
            + "\n…output truncated by bl00p…\n"
            + String(suffix(900))
    }
}
