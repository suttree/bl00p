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

    var currentQuestion: InteractiveQuestion {
        questions[currentIndex]
    }

    mutating func record(
        entryID: UUID,
        answer: QuestionAnswer
    ) -> QuestionAnswerProgress? {
        guard self.entryID == entryID,
              answer.isValid(for: currentQuestion) else {
            return nil
        }
        answers[currentQuestion.id] = answer
        guard currentIndex + 1 < questions.count else {
            return .readyToSubmit
        }
        currentIndex += 1
        self.entryID = UUID()
        return .next
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
        questions: [InteractiveQuestion]
    ) -> QueuedQuestionRequest<RequestID, Request>? {
        guard !questions.isEmpty,
              !requests.contains(where: { $0.requestID == requestID }) else {
            return nil
        }
        let queued = QueuedQuestionRequest(
            requestID: requestID,
            request: request,
            questions: questions
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

    mutating func removeAll() {
        requests.removeAll()
    }
}

struct ClaudeQuestionRequest: Sendable {
    let questions: [InteractiveQuestion]
    let originalQuestions: JSONValue

    init?(request: JSONValue) {
        guard request["subtype"]?.stringValue == "can_use_tool",
              request["tool_name"]?.stringValue == "AskUserQuestion",
              let values = request["input"]?["questions"]?.arrayValue,
              !values.isEmpty else {
            return nil
        }

        var parsed: [InteractiveQuestion] = []
        var prompts: Set<String> = []
        for (questionIndex, value) in values.enumerated() {
            guard let prompt = value["question"]?.stringValue,
                  !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  prompts.insert(prompt).inserted,
                  let optionValues = value["options"]?.arrayValue else {
                return nil
            }
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
            guard options.count == optionValues.count else { return nil }
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

        questions = parsed
        originalQuestions = .array(values)
    }

    func result(answers: [String: QuestionAnswer]) -> JSONValue? {
        var mapped: [String: JSONValue] = [:]
        for question in questions {
            guard let answer = answers[question.id],
                  answer.isValid(for: question) else {
                return nil
            }
            let values = answer.displayValues(for: question)
            mapped[question.text] = question.allowsMultiple
                ? .array(values.map(JSONValue.string))
                : .string(values[0])
        }
        return .object([
            "behavior": .string("allow"),
            "updatedInput": .object([
                "questions": originalQuestions,
                "answers": .object(mapped)
            ])
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
                return nil
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
            guard options.count == optionValues.count else { return nil }
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
