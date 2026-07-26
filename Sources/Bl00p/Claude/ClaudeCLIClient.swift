import Foundation

enum ClaudeCLIError: LocalizedError {
    case processLaunch(String)
    case processClosed(String)

    var errorDescription: String? {
        switch self {
        case .processLaunch(let detail):
            "Could not launch Claude CLI: \(detail)"
        case .processClosed(let detail):
            detail.isEmpty ? "Claude CLI closed unexpectedly." : detail
        }
    }
}

actor ClaudeCLIClient {
    nonisolated let messages: AsyncStream<JSONValue>

    private let executableURL: URL
    private let messageContinuation: AsyncStream<JSONValue>.Continuation
    private var process: Process?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var outputBuffer = Data()
    private var stderrText = ""
    private var isClosing = false
    private var didFinishMessages = false

    init(executableURL: URL) {
        self.executableURL = executableURL
        let pair = AsyncStream.makeStream(of: JSONValue.self)
        messages = pair.stream
        messageContinuation = pair.continuation
    }

    func start(arguments: [String], workingDirectory: URL) throws {
        guard process == nil else { return }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = ProcessInfo.processInfo.environment
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
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
    }

    func stop() {
        guard !isClosing else { return }
        isClosing = true
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil

        if process?.isRunning == true {
            process?.terminate()
        } else {
            finishMessages()
        }
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
            messageContinuation.yield(try JSONValue(any: raw))
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
        messageContinuation.yield(
            .object([
                "type": .string("transport_closed"),
                "exit_status": .number(Double(status)),
                "stderr": .string(stderrText)
            ])
        )
        finishMessages()
    }

    private func finishMessages() {
        guard !didFinishMessages else { return }
        didFinishMessages = true
        messageContinuation.finish()
    }
}
