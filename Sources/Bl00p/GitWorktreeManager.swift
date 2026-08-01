import Foundation

protocol GitWorktreeManaging: Sendable {
    func prepareWorktree(
        for profile: BotProfile,
        startingPoint: String?,
        handoffID: UUID?
    ) async throws -> GitWorktreeOwnership

    func makeHandoff(
        from profile: BotProfile,
        session: AgentSessionState
    ) async throws -> GitHandoffPackage

    func prepareWorktree(
        for profile: BotProfile,
        sessionID: UUID,
        startingPoint: String?,
        handoffID: UUID?
    ) async throws -> GitWorktreeOwnership

    func worktreeIsDirty(_ ownership: GitWorktreeOwnership) async throws -> Bool
    func removeWorktree(
        _ ownership: GitWorktreeOwnership,
        force: Bool
    ) async throws
}

extension GitWorktreeManaging {
    func prepareWorktree(
        for profile: BotProfile,
        sessionID: UUID,
        startingPoint: String?,
        handoffID: UUID?
    ) async throws -> GitWorktreeOwnership {
        var ownership = try await prepareWorktree(
            for: profile,
            startingPoint: startingPoint,
            handoffID: handoffID
        )
        ownership.ownerSessionID = sessionID
        return ownership
    }

    func worktreeIsDirty(_ ownership: GitWorktreeOwnership) async throws -> Bool {
        false
    }

    func removeWorktree(
        _ ownership: GitWorktreeOwnership,
        force: Bool
    ) async throws {
        // Test and preview managers without worktree cleanup have no filesystem
        // resource to remove.
    }
}

enum GitWorktreeError: LocalizedError {
    case noRepository
    case invalidRepository(String)
    case conflictingWorktree(String)
    case unsafeCleanupTarget(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRepository:
            "Choose a Git repository before launching this implementation bot."
        case .invalidRepository(let path):
            "\(path) is not inside a Git repository."
        case .conflictingWorktree(let path):
            "The managed worktree at \(path) belongs to a different branch."
        case .unsafeCleanupTarget(let path):
            "Refusing to remove an unregistered or unsafe worktree path: \(path)"
        case .commandFailed(let detail):
            detail
        }
    }
}

actor GitWorktreeManager: GitWorktreeManaging {
    func prepareWorktree(
        for profile: BotProfile,
        sessionID: UUID,
        startingPoint: String? = nil,
        handoffID: UUID? = nil
    ) async throws -> GitWorktreeOwnership {
        try await prepareWorktree(
            for: profile,
            sessionID: sessionID,
            startingPoint: startingPoint,
            handoffID: handoffID,
            legacyOwnership: profile.worktree
        )
    }

    func prepareWorktree(
        for profile: BotProfile,
        startingPoint: String? = nil,
        handoffID: UUID? = nil
    ) async throws -> GitWorktreeOwnership {
        try await prepareWorktree(
            for: profile,
            sessionID: profile.id,
            startingPoint: startingPoint,
            handoffID: handoffID,
            legacyOwnership: profile.worktree
        )
    }

    private func prepareWorktree(
        for profile: BotProfile,
        sessionID: UUID,
        startingPoint: String?,
        handoffID: UUID?,
        legacyOwnership: GitWorktreeOwnership?
    ) async throws -> GitWorktreeOwnership {
        guard !profile.workingDirectory.isEmpty else {
            throw GitWorktreeError.noRepository
        }

        let selectedDirectory = URL(fileURLWithPath: profile.workingDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let repository = try await primaryRepositoryRoot(from: selectedDirectory)

        if let ownership = legacyOwnership,
           ownership.ownerProfileID == profile.id,
           ownership.ownerSessionID == sessionID
                || (ownership.ownerSessionID == nil && sessionID == profile.id),
           canonicalPath(ownership.repositoryPath) == repository.path,
           await isReusable(ownership) {
            var migrated = ownership
            migrated.ownerSessionID = sessionID
            return migrated
        }

        let sessionMark = String(
            sessionID.uuidString
                .lowercased()
                .replacingOccurrences(of: "-", with: "")
                .prefix(8)
        )
        let handoffMark = handoffID.map {
            "-" + String(
                $0.uuidString
                    .lowercased()
                    .replacingOccurrences(of: "-", with: "")
                    .prefix(6)
            )
        } ?? ""
        let name = branchSlug(profile.name)
        let branch = "bl00p/\(name)-\(sessionMark)\(handoffMark)"
        let worktreeRoot = repository
            .deletingLastPathComponent()
            .appendingPathComponent(".bl00p-worktrees", isDirectory: true)
        let worktree = worktreeRoot.appendingPathComponent(
            "\(repository.lastPathComponent)-\(sessionMark)\(handoffMark)",
            isDirectory: true
        )
        let worktreePath = canonicalPath(worktree.path)
        let base = startingPoint ?? "HEAD"
        let baseRevision = try await git(
            ["rev-parse", "\(base)^{commit}"],
            in: repository
        ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        let registered = try await registeredWorktrees(in: repository)
        if let registeredBranch = registered[worktreePath] {
            guard registeredBranch == branch else {
                throw GitWorktreeError.conflictingWorktree(worktreePath)
            }
        } else {
            guard !FileManager.default.fileExists(atPath: worktreePath) else {
                throw GitWorktreeError.conflictingWorktree(worktreePath)
            }
            try FileManager.default.createDirectory(
                at: worktreeRoot,
                withIntermediateDirectories: true
            )

            let branchExists = try await git(
                ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
                in: repository,
                allowFailure: true
            ).status == 0
            let arguments = branchExists
                ? ["worktree", "add", worktreePath, branch]
                : ["worktree", "add", "-b", branch, worktreePath, base]
            _ = try await git(arguments, in: repository)
        }

        return GitWorktreeOwnership(
            ownerProfileID: profile.id,
            ownerSessionID: sessionID,
            repositoryPath: repository.path,
            worktreePath: worktreePath,
            branch: branch,
            baseRevision: baseRevision
        )
    }

    func worktreeIsDirty(_ ownership: GitWorktreeOwnership) async throws -> Bool {
        _ = try await validateCleanupTarget(ownership)
        let result = try await git(
            ["status", "--porcelain"],
            in: URL(fileURLWithPath: ownership.worktreePath)
        )
        return !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func removeWorktree(
        _ ownership: GitWorktreeOwnership,
        force: Bool
    ) async throws {
        let repository = try await validateCleanupTarget(ownership)
        var arguments = ["worktree", "remove"]
        if force {
            arguments.append("--force")
        }
        arguments.append(ownership.worktreePath)
        _ = try await git(arguments, in: repository)
    }

    private func validateCleanupTarget(
        _ ownership: GitWorktreeOwnership
    ) async throws -> URL {
        let repository = URL(fileURLWithPath: ownership.repositoryPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let path = canonicalPath(ownership.worktreePath)
        let expectedRoot = canonicalPath(
            repository.deletingLastPathComponent()
                .appendingPathComponent(".bl00p-worktrees", isDirectory: true)
                .path
        )
        guard path.hasPrefix(expectedRoot + "/"),
              path != repository.path else {
            throw GitWorktreeError.unsafeCleanupTarget(path)
        }
        let registered = try await registeredWorktrees(in: repository)
        guard registered[path] == ownership.branch else {
            throw GitWorktreeError.unsafeCleanupTarget(path)
        }
        return repository
    }

    func makeHandoff(
        from profile: BotProfile,
        session: AgentSessionState
    ) async throws -> GitHandoffPackage {
        guard let ownership = profile.worktree,
              ownership.ownerProfileID == profile.id else {
            throw GitWorktreeError.noRepository
        }

        let worktree = URL(fileURLWithPath: ownership.worktreePath)
        let branch = try await git(["branch", "--show-current"], in: worktree)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = URL(fileURLWithPath: ownership.repositoryPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let registered = try await registeredWorktrees(in: repository)
        guard !branch.isEmpty,
              registered[canonicalPath(ownership.worktreePath)] == branch else {
            throw GitWorktreeError.conflictingWorktree(ownership.worktreePath)
        }
        let head = try await git(["rev-parse", "HEAD"], in: worktree)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let status = try await git(["status", "--short"], in: worktree)
            .stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let task = session.entries
            .last(where: { $0.kind == .user && !$0.text.isEmpty })?
            .text
            ?? session.entries
                .last(where: { $0.kind == .handoff && !$0.text.isEmpty })?
                .text
            ?? "No task context was captured."
        let evidence = HandoffTestEvidence.latest(in: session.entries)

        return GitHandoffPackage(
            sourceProfileID: profile.id,
            sourceName: profile.name,
            repositoryPath: ownership.repositoryPath,
            worktreePath: ownership.worktreePath,
            branch: branch,
            baseRevision: ownership.baseRevision,
            headRevision: head,
            taskContext: task,
            testStatus: evidence.status,
            testSummary: evidence.summary,
            testEvidenceAt: evidence.recordedAt,
            workingTreeSummary: status.isEmpty
                ? "Clean"
                : status.truncated(to: 1_000)
        )
    }

    private func primaryRepositoryRoot(from directory: URL) async throws -> URL {
        let rootResult = try await git(
            ["rev-parse", "--show-toplevel"],
            in: directory,
            allowFailure: true
        )
        guard rootResult.status == 0 else {
            throw GitWorktreeError.invalidRepository(directory.path)
        }

        let list = try await git(["worktree", "list", "--porcelain"], in: directory)
            .stdout
        guard let primaryPath = list
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("worktree ") })?
            .dropFirst("worktree ".count),
            !primaryPath.isEmpty else {
            let fallback = rootResult.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(fileURLWithPath: fallback)
                .standardizedFileURL
                .resolvingSymlinksInPath()
        }
        return URL(fileURLWithPath: String(primaryPath))
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    private func isReusable(_ ownership: GitWorktreeOwnership) async -> Bool {
        let worktree = URL(fileURLWithPath: ownership.worktreePath)
        guard FileManager.default.fileExists(atPath: worktree.path) else {
            return false
        }
        guard let branch = try? await git(
            ["branch", "--show-current"],
            in: worktree,
            allowFailure: true
        ) else { return false }
        return branch.status == 0
            && branch.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                == ownership.branch
    }

    private func registeredWorktrees(in repository: URL) async throws -> [String: String] {
        let output = try await git(["worktree", "list", "--porcelain"], in: repository)
            .stdout
        var result: [String: String] = [:]
        var path: String?

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("worktree ") {
                path = canonicalPath(String(line.dropFirst("worktree ".count)))
            } else if line.hasPrefix("branch refs/heads/"), let path {
                result[path] = String(line.dropFirst("branch refs/heads/".count))
            } else if line.isEmpty {
                path = nil
            }
        }
        return result
    }

    private func branchSlug(_ name: String) -> String {
        let lowered = name.lowercased()
        var result = ""
        var previousWasDash = false

        for character in lowered {
            if character.isLetter || character.isNumber {
                result.append(character)
                previousWasDash = false
            } else if !previousWasDash && !result.isEmpty {
                result.append("-")
                previousWasDash = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "builder" : String(trimmed.prefix(32))
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private struct GitResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// Single-writer handoff from a background pipe-reading closure back to
    /// the continuation resumed once all reads complete. Safe by
    /// construction: exactly one closure ever writes `data`, and the
    /// `DispatchGroup` happens-before relationship orders that write
    /// before the code that reads it.
    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    /// Runs `git` without ever blocking Swift's cooperative thread pool.
    /// Actor methods run on that small, fixed-size pool; blocking one of
    /// those threads synchronously (`Process.waitUntilExit()`,
    /// `DispatchGroup.wait()`) can starve the whole pool once enough
    /// concurrent callers do it at once, which looks like every unrelated
    /// async task in the process silently stalling.
    ///
    /// Draining only after `waitUntilExit()` deadlocks the moment output
    /// exceeds the OS pipe buffer, so both pipes are drained concurrently
    /// with the process running. Every blocking step here — both reads, the
    /// wait for them to finish, and the final `waitUntilExit()` — runs on
    /// its own dedicated `Thread` rather than any `DispatchQueue`: GCD's
    /// global queues share a small, capped worker pool, and a blocking call
    /// there can exhaust the very pool the next concurrent `git()` call
    /// needs — the same starvation this is trying to avoid, just relocated.
    /// A plain `Thread` has no such shared cap, so nothing here can starve
    /// anything else. (Two earlier attempts got this partly right and still
    /// hung under heavy concurrency: one used `Process`'s
    /// `readabilityHandler`/`terminationHandler`, which also hung
    /// intermittently on Linux's swift-corelibs-foundation; the other used
    /// `DispatchGroup.notify(queue: .global())` for the final wait, still a
    /// shared pool.)
    private func git(
        _ arguments: [String],
        in directory: URL,
        allowFailure: Bool = false
    ) async throws -> GitResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw GitWorktreeError.commandFailed(error.localizedDescription)
        }

        let (outputData, errorData, status): (Data, Data, Int32) = await withCheckedContinuation { continuation in
            let stdoutHandle = standardOutput.fileHandleForReading
            let stderrHandle = standardError.fileHandleForReading
            let outputBox = DataBox()
            let errorBox = DataBox()
            let group = DispatchGroup()
            group.enter()
            Thread.detachNewThread {
                outputBox.data = stdoutHandle.readDataToEndOfFile()
                group.leave()
            }
            group.enter()
            Thread.detachNewThread {
                errorBox.data = stderrHandle.readDataToEndOfFile()
                group.leave()
            }
            // Waiting for the group and for exit both block, so both run on
            // their own dedicated thread too rather than handing off to
            // group.notify(queue:), which would run on one of libdispatch's
            // shared global queues — a smaller, capped pool that can still
            // exhaust under enough concurrent git() calls, same as this
            // whole rewrite exists to avoid in the first place.
            Thread.detachNewThread {
                group.wait()
                process.waitUntilExit()
                continuation.resume(
                    returning: (outputBox.data, errorBox.data, process.terminationStatus)
                )
            }
        }

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        let result = GitResult(status: status, stdout: output, stderr: error)
        if !allowFailure && result.status != 0 {
            let command = (["git"] + arguments).joined(separator: " ")
            let detail = error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitWorktreeError.commandFailed(
                detail.isEmpty ? "\(command) failed." : detail
            )
        }
        return result
    }
}

struct HandoffTestEvidence: Equatable {
    let status: HandoffTestStatus
    let summary: String
    let recordedAt: Date?

    /// Shared by completed-command and permission-denial classification. It
    /// intentionally only examines a command invocation, never tool output:
    /// `Read`/`Grep` cards mentioning passing tests are not test evidence.
    static func isTestCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
            .replacingOccurrences(of: "\n", with: " ")
        let segments = normalized.split(whereSeparator: { character in
            character == ";" || character == "|" || character == "&"
        })
        return segments.contains { segment in
            looksLikeTestInvocation(String(segment))
        }
    }

    private static func looksLikeTestInvocation(_ command: String) -> Bool {
        let cleaned = command.trimmingCharacters(
            in: CharacterSet(charactersIn: "•- ")
        )
        let tokens = cleaned.split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        guard !tokens.isEmpty else { return false }

        var index = 0
        // Common wrappers can precede a runner, including `env FOO=bar`,
        // timing/priority wrappers, and package-manager executors.
        while index < tokens.count {
            let token = tokens[index]
            if token == "env" || token == "command" || token == "time"
                || token == "nice" || token == "nohup" || token == "xcrun" {
                index += 1
                while index < tokens.count, tokens[index].contains("=") {
                    index += 1
                }
                continue
            }
            if token == "timeout" {
                index += min(2, tokens.count - index)
                continue
            }
            break
        }
        guard index < tokens.count else { return false }

        let executable = tokens[index]
            .split(separator: "/").last.map(String.init) ?? tokens[index]
        let arguments = Array(tokens.dropFirst(index + 1))
        let firstArgument = arguments.first ?? ""
        let secondArgument = arguments.dropFirst().first ?? ""

        if ["pytest", "ctest", "phpunit", "rspec", "vitest", "jest",
            "ava", "mocha", "tap", "phpunit"].contains(executable) {
            return true
        }
        if executable == "swift" || executable == "xcodebuild"
            || executable == "cargo" || executable == "go"
            || executable == "dotnet" || executable == "deno"
            || executable == "bun" || executable == "mix"
            || executable == "rake" || executable == "mvn" {
            return firstArgument == "test"
        }
        if executable == "gradle" || executable == "gradlew" {
            return arguments.contains { $0 == "test" || $0.hasPrefix("test") }
        }
        if executable == "make" || executable == "just" {
            return ["test", "check", "verify"].contains(firstArgument)
        }
        if executable == "bundle" {
            return firstArgument == "exec" && ["rspec", "cucumber"].contains(secondArgument)
        }
        if executable == "npm" || executable == "pnpm" || executable == "yarn" {
            return firstArgument == "test"
                || (firstArgument == "run" && ["test", "check", "verify"].contains(secondArgument))
                || (firstArgument == "exec" && ["vitest", "jest", "mocha"].contains(secondArgument))
        }
        if executable == "npx" {
            return ["vitest", "jest", "mocha", "ava", "cypress"].contains(firstArgument)
        }
        // Project-owned test wrappers are allowed; arbitrary shell commands
        // are not inferred from their output.
        return executable == "test" || executable == "check" || executable == "verify"
            || executable.hasPrefix("test-") || executable.hasPrefix("check-")
            || executable.hasPrefix("verify-")
    }

    static func latest(in entries: [TimelineEntry]) -> HandoffTestEvidence {
        let testEntry = entries.last {
            $0.kind == .command && isTestCommand($0.text)
        }

        guard let testEntry else {
            return .init(
                status: .notRun,
                summary: "No test command was recorded.",
                recordedAt: nil
            )
        }

        let legacyFailed = testEntry.title?
            .localizedCaseInsensitiveContains("failed") == true
            || testEntry.title?
                .localizedCaseInsensitiveContains("error") == true
        let legacyCompleted = testEntry.title?
            .localizedCaseInsensitiveContains("finished") == true
            || testEntry.title?
                .localizedCaseInsensitiveContains("completed") == true
            || testEntry.title?
                .localizedCaseInsensitiveContains("succeeded") == true
            || testEntry.title?
                .localizedCaseInsensitiveContains("success") == true
            || testEntry.title?
                .localizedCaseInsensitiveContains("passed") == true
            || testEntry.title?
                .localizedCaseInsensitiveContains("exited 0") == true
        let legacyRunning = testEntry.title?
            .localizedCaseInsensitiveContains("running") == true
            || testEntry.title?
                .localizedCaseInsensitiveContains("requested") == true
        let status: HandoffTestStatus
        switch testEntry.commandOutcome {
        case .failed:
            status = .failed
        case .succeeded:
            // A terminal failure marker is safety-critical even when a
            // provider has emitted contradictory success state.
            status = legacyFailed ? .failed : .passed
        case .running:
            status = .notRun
        case nil:
            // Old persisted entries have no structured state. Explicit
            // failures always win over success-looking text or generic titles.
            status = legacyFailed
                ? .failed
                : (legacyCompleted && !legacyRunning ? .passed : .notRun)
        }
        let detail = testEntry.detail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = [
            "`\(testEntry.text)`",
            detail?.isEmpty == false ? detail?.truncated(to: 500) : nil
        ]
            .compactMap { $0 }
            .joined(separator: "\n")

        return .init(
            status: status,
            summary: summary,
            recordedAt: testEntry.commandCompletedAt ?? testEntry.timestamp
        )
    }
}

private extension String {
    func truncated(to limit: Int) -> String {
        guard count > limit else { return self }
        return String(prefix(limit)) + "…"
    }
}
