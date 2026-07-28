import Foundation

enum QuestionAnswerProgress: Equatable, Sendable {
    case next
    case readyToSubmit
}

struct QueuedQuestionRequest<RequestID: Equatable & Sendable, Request: Sendable>: Sendable {
    let requestID: RequestID
    let request: Request
    let questions: [InteractiveQuestion]
    var answers: [String: QuestionAnswer] = [:]
    var currentIndex = 0
    var entryID = UUID()
    var isResponding = false

    var currentQuestion: InteractiveQuestion {
        questions[currentIndex]
    }

    mutating func record(
        entryID: UUID,
        answer: QuestionAnswer
    ) -> QuestionAnswerProgress? {
        guard self.entryID == entryID,
              !isResponding,
              answer.isValid(for: currentQuestion) else {
            return nil
        }
        answers[currentQuestion.id] = answer
        guard currentIndex + 1 < questions.count else {
            isResponding = true
            return .readyToSubmit
        }
        currentIndex += 1
        self.entryID = UUID()
        return .next
    }

    mutating func beginDecline(entryID: UUID) -> Bool {
        guard self.entryID == entryID, !isResponding else { return false }
        isResponding = true
        return true
    }

    mutating func resetResponse() {
        isResponding = false
    }
}

struct QuestionRequestQueue<RequestID: Equatable & Sendable, Request: Sendable>: Sendable {
    private(set) var requests: [
        QueuedQuestionRequest<RequestID, Request>
    ] = []

    var first: QueuedQuestionRequest<RequestID, Request>? {
        requests.first
    }

    var isEmpty: Bool {
        requests.isEmpty
    }

    mutating func enqueue(
        requestID: RequestID,
        request: Request,
        questions: [InteractiveQuestion],
        entryID: UUID = UUID()
    ) -> QueuedQuestionRequest<RequestID, Request>? {
        guard !questions.isEmpty,
              !requests.contains(where: { $0.requestID == requestID }) else {
            return nil
        }
        let queued = QueuedQuestionRequest(
            requestID: requestID,
            request: request,
            questions: questions,
            entryID: entryID
        )
        requests.append(queued)
        return queued
    }

    mutating func updateFirst(
        _ request: QueuedQuestionRequest<RequestID, Request>
    ) {
        guard !requests.isEmpty else { return }
        requests[0] = request
    }

    @discardableResult
    mutating func removeFirst() -> QueuedQuestionRequest<RequestID, Request>? {
        requests.isEmpty ? nil : requests.removeFirst()
    }

    mutating func cancel(
        requestID: RequestID
    ) -> (
        request: QueuedQuestionRequest<RequestID, Request>,
        wasActive: Bool
    )? {
        guard let index = requests.firstIndex(where: {
            $0.requestID == requestID
        }) else {
            return nil
        }
        return (requests.remove(at: index), index == 0)
    }

    mutating func drain() -> [QueuedQuestionRequest<RequestID, Request>] {
        defer { requests.removeAll() }
        return requests
    }
}

struct ClaudeQuestionRequest: Sendable {
    let questions: [InteractiveQuestion]
    let originalInput: JSONValue

    init?(request: JSONValue) {
        guard request["subtype"]?.stringValue == "can_use_tool",
              request["tool_name"]?.stringValue == "AskUserQuestion",
              let input = request["input"] else {
            return nil
        }
        self.init(input: input)
    }

    init?(input: JSONValue) {
        guard input.objectValue != nil,
              let values = input["questions"]?.arrayValue,
              !values.isEmpty else {
            return nil
        }
        var parsed: [InteractiveQuestion] = []
        var prompts: Set<String> = []
        for (questionIndex, value) in values.enumerated() {
            guard let prompt = value["question"]?.stringValue,
                  !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  prompts.insert(prompt).inserted else { continue }
            let optionValues = value["options"]?.arrayValue ?? []
            let options: [QuestionOption] = optionValues.enumerated().compactMap { optionIndex, option in
                guard let label = option["label"]?.stringValue,
                      !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return QuestionOption(
                    id: "option-\(optionIndex)",
                    label: label,
                    description: option["description"]?.stringValue
                )
            }
            parsed.append(
                InteractiveQuestion(
                    id: "question-\(questionIndex)",
                    header: value["header"]?.stringValue ?? "Claude asks",
                    text: prompt,
                    options: options,
                    allowsMultiple: value["multiSelect"]?.boolValue ?? false
                )
            )
        }

        guard !parsed.isEmpty else { return nil }
        questions = parsed
        originalInput = input
    }

    func result(answers: [String: QuestionAnswer]) -> JSONValue? {
        var mapped: [String: JSONValue] = [:]
        for question in questions {
            guard let answer = answers[question.id],
                  answer.isValid(for: question) else {
                return nil
            }
            let values = answer.displayValues(for: question)
            mapped[question.text] = .string(values.joined(separator: ", "))
        }
        guard var updatedInput = originalInput.objectValue else { return nil }
        updatedInput["answers"] = .object(mapped)
        return .object([
            "behavior": .string("allow"),
            "updatedInput": .object(updatedInput)
        ])
    }

    var declinedResult: JSONValue {
        .object([
            "behavior": .string("deny"),
            "message": .string("The user declined to answer this question in bl00p.")
        ])
    }
}

struct CodexQuestionRequest: Sendable {
    let questions: [InteractiveQuestion]

    init?(params: JSONValue) {
        guard let values = params["questions"]?.arrayValue,
              !values.isEmpty else {
            return nil
        }

        var parsed: [InteractiveQuestion] = []
        var ids: Set<String> = []
        for value in values {
            guard let id = value["id"]?.stringValue,
                  !id.isEmpty,
                  ids.insert(id).inserted,
                  let prompt = value["question"]?.stringValue,
                  !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let optionValues = value["options"]?.arrayValue ?? []
            let options: [QuestionOption] = optionValues.enumerated().compactMap { index, option in
                guard let label = option["label"]?.stringValue,
                      !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return QuestionOption(
                    id: "option-\(index)",
                    label: label,
                    description: option["description"]?.stringValue
                )
            }
            parsed.append(
                InteractiveQuestion(
                    id: id,
                    header: value["header"]?.stringValue ?? "Codex asks",
                    text: prompt,
                    options: options,
                    allowsMultiple: value["multiSelect"]?.boolValue ?? false
                )
            )
        }
        guard !parsed.isEmpty else { return nil }
        questions = parsed
    }

    func result(answers: [String: QuestionAnswer]) -> JSONValue? {
        var mapped: [String: JSONValue] = [:]
        for question in questions {
            guard let answer = answers[question.id],
                  answer.isValid(for: question) else {
                return nil
            }
            mapped[question.id] = .object([
                "answers": .array(
                    answer.displayValues(for: question).map(JSONValue.string)
                )
            ])
        }
        return .object(["answers": .object(mapped)])
    }
}
