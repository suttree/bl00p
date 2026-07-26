import Foundation

enum CodexAppServerError: LocalizedError, Sendable {
    case executableNotFound
    case processLaunch(String)
    case processClosed(String)
    case requestTimedOut(String)
    case invalidResponse(String)
    case rpc(code: Int?, message: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "No usable Codex runtime was found."
        case .processLaunch(let detail):
            "Codex app-server could not start: \(detail)"
        case .processClosed(let detail):
            "Codex app-server stopped unexpectedly: \(detail)"
        case .requestTimedOut(let method):
            "Codex app-server did not answer \(method) in time."
        case .invalidResponse(let detail):
            "Codex app-server returned an invalid response: \(detail)"
        case .rpc(_, let message):
            "Codex app-server: \(message)"
        }
    }
}

actor CodexAppServerClient {
    nonisolated let messages: AsyncStream<JSONValue>

    private let executableURL: URL
    private let messageContinuation: AsyncStream<JSONValue>.Continuation
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var outputBuffer = Data()
    private var stderrText = ""
    private var nextRequestID = 1
    private var pendingResponses: [
        String: CheckedContinuation<JSONValue, any Error>
    ] = [:]
    private var isClosing = false

    init(executableURL: URL) {
        self.executableURL = executableURL
        let pair = AsyncStream.makeStream(of: JSONValue.self)
        messages = pair.stream
        messageContinuation = pair.continuation
    }

    func connect() async throws -> String {
        try launchProcess()

        let response = try await request(
            method: "initialize",
            params: [
                "clientInfo": .object([
                    "name": .string("bl00p"),
                    "title": .string("bl00p"),
                    "version": .string("0.1.0")
                ]),
                "capabilities": .object([
                    "experimentalApi": .bool(true),
                    "requestAttestation": .bool(false)
                ])
            ]
        )

        try sendNotification(method: "initialized")
        return response["userAgent"]?.stringValue ?? "Codex"
    }

    func request(
        method: String,
        params: [String: JSONValue],
        timeout: Duration = .seconds(30)
    ) async throws -> JSONValue {
        guard process?.isRunning == true else {
            throw CodexAppServerError.processClosed(stderrText)
        }

        let id = nextRequestID
        nextRequestID += 1
        let key = "n:\(id)"

        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[key] = continuation

            do {
                try write(
                    .object([
                        "method": .string(method),
                        "id": .number(Double(id)),
                        "params": .object(params)
                    ])
                )
                Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    await self?.timeOutResponse(key: key, method: method)
                }
            } catch {
                pendingResponses[key] = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func sendNotification(method: String, params: [String: JSONValue]? = nil) throws {
        var object: [String: JSONValue] = ["method": .string(method)]
        if let params {
            object["params"] = .object(params)
        }
        try write(.object(object))
    }

    func respond(to requestID: JSONValue, result: JSONValue) throws {
        try write(
            .object([
                "id": requestID,
                "result": result
            ])
        )
    }

    func respondError(
        to requestID: JSONValue,
        code: Int,
        message: String
    ) throws {
        try write(
            .object([
                "id": requestID,
                "error": .object([
                    "code": .number(Double(code)),
                    "message": .string(message)
                ])
            ])
        )
    }

    func stop() {
        guard !isClosing else { return }
        isClosing = true

        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        inputHandle?.closeFile()

        if process?.isRunning == true {
            process?.terminate()
        }

        finish(
            with: CodexAppServerError.processClosed(
                stderrText.isEmpty ? "Session stopped." : stderrText
            ),
            notifyRuntime: false
        )
    }

    private func launchProcess() throws {
        guard process == nil else { return }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.receiveOutput(data)
            }
        }

        errorHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.receiveError(data)
            }
        }

        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task {
                await self?.processTerminated(status: status)
            }
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            throw CodexAppServerError.processLaunch(error.localizedDescription)
        }

        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
    }

    private func write(_ value: JSONValue) throws {
        guard let inputHandle else {
            throw CodexAppServerError.processClosed("stdin is unavailable")
        }

        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }

    private func receiveOutput(_ data: Data) {
        guard !data.isEmpty else {
            outputHandle?.readabilityHandler = nil
            return
        }

        outputBuffer.append(data)
        let newline = Data([0x0A])

        while let range = outputBuffer.range(of: newline) {
            let line = outputBuffer.subdata(in: outputBuffer.startIndex..<range.lowerBound)
            outputBuffer.removeSubrange(outputBuffer.startIndex...range.lowerBound)

            guard !line.isEmpty else { continue }
            let whitespace: Set<UInt8> = [0x09, 0x0A, 0x0D, 0x20]
            guard let firstIndex = line.firstIndex(where: { !whitespace.contains($0) }),
                  line[firstIndex] == 0x7B else {
                // The experimental app-server occasionally leaks command output
                // onto stdout. It is not part of the JSON-RPC transport.
                continue
            }
            do {
                let raw = try JSONSerialization.jsonObject(
                    with: line,
                    options: [.fragmentsAllowed]
                )
                let message = try JSONValue(any: raw)
                route(message)
            } catch {
                let rawLine = String(decoding: line.prefix(2_000), as: UTF8.self)
                messageContinuation.yield(
                    .object([
                        "method": .string("transport/decodeError"),
                        "params": .object([
                            "message": .string(
                                "Could not decode Codex output: \(error.localizedDescription)"
                            ),
                            "rawLine": .string(rawLine)
                        ])
                    ])
                )
            }
        }
    }

    private func receiveError(_ data: Data) {
        guard !data.isEmpty else {
            errorHandle?.readabilityHandler = nil
            return
        }

        if let text = String(data: data, encoding: .utf8) {
            stderrText.append(text)
            if stderrText.count > 8_000 {
                stderrText = String(stderrText.suffix(8_000))
            }
        }
    }

    private func route(_ message: JSONValue) {
        if let requestID = message["id"],
           let key = requestID.requestIDKey,
           message["result"] != nil || message["error"] != nil,
           let continuation = pendingResponses.removeValue(forKey: key) {
            if let error = message["error"] {
                continuation.resume(throwing: rpcError(from: error))
            } else if let result = message["result"] {
                continuation.resume(returning: result)
            } else {
                continuation.resume(
                    throwing: CodexAppServerError.invalidResponse(message.compactDescription)
                )
            }
            return
        }

        messageContinuation.yield(message)
    }

    private func rpcError(from value: JSONValue) -> CodexAppServerError {
        let message = value["message"]?.stringValue ?? value.compactDescription
        return .rpc(code: value["code"]?.intValue, message: message)
    }

    private func timeOutResponse(key: String, method: String) {
        guard let continuation = pendingResponses.removeValue(forKey: key) else { return }
        continuation.resume(
            throwing: CodexAppServerError.requestTimedOut(method)
        )
    }

    private func processTerminated(status: Int32) {
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil

        let detail = stderrText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        finish(
            with: CodexAppServerError.processClosed(
                detail.isEmpty ? "exit status \(status)" : detail
            ),
            notifyRuntime: !isClosing
        )
    }

    private func finish(with error: any Error, notifyRuntime: Bool) {
        let continuations = pendingResponses.values
        pendingResponses.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }

        if notifyRuntime {
            messageContinuation.yield(
                .object([
                    "method": .string("transport/closed"),
                    "params": .object([
                        "message": .string(error.localizedDescription)
                    ])
                ])
            )
        }
        messageContinuation.finish()
    }
}
