import Foundation

protocol ClaudeClient: Actor {
    nonisolated var messages: AsyncStream<JSONValue> { get }

    func connect(arguments: [String], workingDirectory: URL) async throws
    func send(_ message: JSONValue) throws
    func finishInput()
    func respond(to requestID: String, result: JSONValue) throws
    func respondError(to requestID: String, message: String) throws
    func stop()
}

enum ClaudeCLIError: LocalizedError {
    case processLaunch(String)
    case processClosed(String)
    case requestTimedOut(String)
    case control(String)

    var errorDescription: String? {
        switch self {
        case .processLaunch(let detail):
            "Could not launch Claude CLI: \(detail)"
        case .processClosed(let detail):
            detail.isEmpty ? "Claude CLI closed unexpectedly." : detail
        case .requestTimedOut(let subtype):
            "Claude CLI did not answer the \(subtype) control request."
        case .control(let detail):
            "Claude CLI control protocol: \(detail)"
        }
    }
}

actor ClaudeCLIClient: ClaudeClient {
    nonisolated let messages: AsyncStream<JSONValue>

    private let executableURL: URL
    private let messageContinuation: AsyncStream<JSONValue>.Continuation
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var outputBuffer = Data()
    private var stderrText = ""
    private var pendingResponses: [
        String: CheckedContinuation<JSONValue, any Error>
    ] = [:]
    private var isClosing = false
    private var didFinishMessages = false

    init(executableURL: URL) {
        self.executableURL = executableURL
        let pair = AsyncStream.makeStream(of: JSONValue.self)
        messages = pair.stream
        messageContinuation = pair.continuation
    }

    func connect(arguments: [String], workingDirectory: URL) async throws {
        try start(arguments: arguments, workingDirectory: workingDirectory)
        _ = try await request(
            .object([
                "subtype": .string("initialize"),
                "hooks": .null
            ])
        )
    }

    func send(_ message: JSONValue) throws {
        try write(message)
    }

    func finishInput() {
        inputHandle?.closeFile()
        inputHandle = nil
    }

    func respond(
        to requestID: String,
        result: JSONValue
    ) throws {
        try write(
            .object([
                "type": .string("control_response"),
                "response": .object([
                    "subtype": .string("success"),
                    "request_id": .string(requestID),
                    "response": result
                ])
            ])
        )
    }

    func respondError(
        to requestID: String,
        message: String
    ) throws {
        try write(
            .object([
                "type": .string("control_response"),
                "response": .object([
                    "subtype": .string("error"),
                    "request_id": .string(requestID),
                    "error": .string(message)
                ])
            ])
        )
    }

    func stop() {
        guard !isClosing else { return }
        isClosing = true
        finishInput()
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil

        let error = ClaudeCLIError.processClosed(
            stderrText.isEmpty ? "Session stopped." : stderrText
        )
        finishPendingResponses(with: error)

        if process?.isRunning == true {
            process?.terminate()
        } else {
            finishMessages()
        }
    }

    private func start(arguments: [String], workingDirectory: URL) throws {
        guard process == nil else { return }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
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
                // Give the final readability callback a chance to enqueue the
                // result line before the transport-closed sentinel.
                try? await Task.sleep(for: .milliseconds(40))
                await self?.processTerminated(status: status)
            }
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            throw ClaudeCLIError.processLaunch(error.localizedDescription)
        }

        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
    }

    private func request(
        _ request: JSONValue,
        timeout: Duration = .seconds(30)
    ) async throws -> JSONValue {
        guard process?.isRunning == true else {
            throw ClaudeCLIError.processClosed(stderrText)
        }

        let requestID = UUID().uuidString.lowercased()
        let subtype = request["subtype"]?.stringValue ?? "unknown"
        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[requestID] = continuation

            do {
                try write(
                    .object([
                        "type": .string("control_request"),
                        "request_id": .string(requestID),
                        "request": request
                    ])
                )
                Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    await self?.timeOutResponse(
                        requestID: requestID,
                        subtype: subtype
                    )
                }
            } catch {
                pendingResponses[requestID] = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func write(_ value: JSONValue) throws {
        guard let inputHandle else {
            throw ClaudeCLIError.processClosed("stdin is unavailable")
        }

        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }

    private func receiveOutput(_ data: Data) {
        guard !data.isEmpty else {
            outputHandle?.readabilityHandler = nil
            flushFinalOutputLine()
            return
        }

        outputBuffer.append(data)
        let newline = Data([0x0A])

        while let range = outputBuffer.range(of: newline) {
            let line = outputBuffer.subdata(in: outputBuffer.startIndex..<range.lowerBound)
            outputBuffer.removeSubrange(outputBuffer.startIndex...range.lowerBound)
            decode(line)
        }
    }

    private func flushFinalOutputLine() {
        guard !outputBuffer.isEmpty else { return }
        let line = outputBuffer
        outputBuffer.removeAll()
        decode(line)
    }

    private func decode(_ line: Data) {
        guard !line.isEmpty else { return }

        do {
            let raw = try JSONSerialization.jsonObject(
                with: line,
                options: [.fragmentsAllowed]
            )
            route(try JSONValue(any: raw))
        } catch {
            messageContinuation.yield(
                .object([
                    "type": .string("transport_decode_error"),
                    "message": .string(error.localizedDescription),
                    "raw_line": .string(
                        String(decoding: line.prefix(2_000), as: UTF8.self)
                    )
                ])
            )
        }
    }

    private func route(_ message: JSONValue) {
        if message["type"]?.stringValue == "control_response",
           let response = message["response"],
           let requestID = response["request_id"]?.stringValue,
           let continuation = pendingResponses.removeValue(forKey: requestID) {
            if response["subtype"]?.stringValue == "error" {
                continuation.resume(
                    throwing: ClaudeCLIError.control(
                        response["error"]?.stringValue ?? response.compactDescription
                    )
                )
            } else {
                continuation.resume(
                    returning: response["response"] ?? .object([:])
                )
            }
            return
        }

        messageContinuation.yield(message)
    }

    private func timeOutResponse(
        requestID: String,
        subtype: String
    ) {
        guard let continuation = pendingResponses.removeValue(forKey: requestID) else {
            return
        }
        continuation.resume(throwing: ClaudeCLIError.requestTimedOut(subtype))
    }

    private func receiveError(_ data: Data) {
        guard !data.isEmpty else {
            errorHandle?.readabilityHandler = nil
            return
        }

        stderrText.append(String(decoding: data, as: UTF8.self))
        if stderrText.count > 8_000 {
            stderrText = String(stderrText.suffix(8_000))
        }
    }

    private func processTerminated(status: Int32) {
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        flushFinalOutputLine()
        finishPendingResponses(
            with: ClaudeCLIError.processClosed(
                stderrText.isEmpty ? "exit status \(status)" : stderrText
            )
        )
        messageContinuation.yield(
            .object([
                "type": .string("transport_closed"),
                "exit_status": .number(Double(status)),
                "stderr": .string(stderrText)
            ])
        )
        finishMessages()
    }

    private func finishPendingResponses(with error: any Error) {
        let continuations = pendingResponses.values
        pendingResponses.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func finishMessages() {
        guard !didFinishMessages else { return }
        didFinishMessages = true
        messageContinuation.finish()
    }
}
