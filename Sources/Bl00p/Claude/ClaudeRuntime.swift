import Foundation

actor ClaudeRuntime: AgentRuntime {
    private struct Session {
        let executableURL: URL
        let workingDirectory: URL
        var sessionID: String
        var shouldResume: Bool
        var currentClient: ClaudeCLIClient?
        var currentContinuation: AsyncStream<AgentEvent>.Continuation?
        var listenerTask: Task<Void, Never>?
        var toolEntries: [String: TimelineEntry] = [:]
        var assistantTexts: Set<String> = []
        var receivedResult = false
    }

    private let locator = ClaudeExecutableLocator()
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
            sessionID: sessionID,
            shouldResume: resumedID != nil
        )

        pair.continuation.yield(.sessionID(sessionID))
        pair.continuation.yield(
            .entry(
                .init(
                    kind: .system,
                    text: resumedID == nil
                        ? "Connected to Claude Code"
                        : "Ready to resume Claude Code",
                    detail: "Human-supervised local tools · \(workingDirectory.path)"
                )
            )
        )
        pair.continuation.yield(.entry(openingQuestion(for: profile.role)))
        pair.continuation.yield(.status(.needsAnswer))
        pair.continuation.finish()
        return pair.stream
    }

    func respond(
        to message: String,
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
        let client = ClaudeCLIClient(executableURL: session.executableURL)
        let invocation = ClaudeInvocation(
            sessionID: session.sessionID,
            resume: session.shouldResume,
            profile: profile,
            prompt: message
        )
        let listener = Task { [weak self] in
            for await event in client.messages {
                guard !Task.isCancelled else { break }
                await self?.handle(event, profileID: profile.id)
            }
        }

        session.currentClient = client
        session.currentContinuation = pair.continuation
        session.listenerTask = listener
        session.toolEntries.removeAll()
        session.assistantTexts.removeAll()
        session.receivedResult = false
        sessions[profile.id] = session
        pair.continuation.yield(.status(.working))

        do {
            try await client.start(
                arguments: invocation.arguments,
                workingDirectory: session.workingDirectory
            )
        } catch {
            listener.cancel()
            if var updated = sessions[profile.id] {
                updated.currentContinuation?.yield(
                    .entry(
                        .init(
                            kind: .system,
                            text: "Could not start Claude",
                            detail: error.localizedDescription
                        )
                    )
                )
                updated.currentContinuation?.yield(.status(.failed))
                updated.currentContinuation?.finish()
                updated.currentContinuation = nil
                updated.currentClient = nil
                updated.listenerTask = nil
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
        singleEventStream(
            .entry(
                .init(
                    kind: .system,
                    text: "Claude tool approvals are not active in this build.",
                    detail: "No command was run. Tell Claude how you want to proceed in a new message."
                )
            ),
            finalStatus: .needsAnswer
        )
    }

    func stop(profile: BotProfile) async {
        guard let session = sessions.removeValue(forKey: profile.id) else { return }
        session.listenerTask?.cancel()
        session.currentContinuation?.finish()
        if let client = session.currentClient {
            await client.stop()
        }
    }

    private func handle(_ event: JSONValue, profileID: UUID) {
        guard let type = event["type"]?.stringValue,
              sessions[profileID] != nil else { return }

        switch type {
        case "system":
            handleSystem(event, profileID: profileID)

        case "assistant":
            handleAssistant(event, profileID: profileID)

        case "user":
            handleToolResults(event, profileID: profileID)

        case "result":
            handleResult(event, profileID: profileID)

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

    private func handleResult(_ event: JSONValue, profileID: UUID) {
        guard var session = sessions[profileID] else { return }
        session.receivedResult = true
        let failed = event["is_error"]?.boolValue == true
        let result = event["result"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if failed {
            yield(
                .entry(
                    .init(
                        kind: .system,
                        text: result == "Not logged in · Please run /login"
                            ? "Claude authentication expired"
                            : "Claude could not complete the turn",
                        detail: result
                    )
                ),
                profileID: profileID
            )
        } else if let result,
                  !result.isEmpty,
                  !session.assistantTexts.contains(result) {
            yield(.entry(.init(kind: .assistant, text: result)), profileID: profileID)
        }

        if let denials = event["permission_denials"]?.arrayValue,
           !denials.isEmpty {
            yield(
                .entry(
                    .init(
                        kind: .system,
                        text: "Claude stopped at a permission boundary",
                        detail: denials
                            .map(\.compactDescription)
                            .joined(separator: "\n")
                            .trimmedForClaudeTimeline
                    )
                ),
                profileID: profileID
            )
        }

        session.currentContinuation?.yield(.status(failed ? .failed : .completed))
        session.currentContinuation?.finish()
        session.currentContinuation = nil
        session.currentClient = nil
        session.shouldResume = true
        sessions[profileID] = session
    }

    private func handleTransportClosed(_ event: JSONValue, profileID: UUID) {
        guard var session = sessions[profileID] else { return }
        defer {
            session.currentClient = nil
            session.listenerTask = nil
            sessions[profileID] = session
        }

        guard session.currentContinuation != nil else { return }
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
                text: "Share the review notes and branch or PR whose writing should be polished."
            )
        }
    }

    private func authenticationStatus(executableURL: URL) -> AuthenticationStatus {
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
}
private enum AuthenticationStatus {
    case loggedIn
    case loggedOut
    case unavailable(String)
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
