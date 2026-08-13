// Interaction concepts adapted from OpenCode; no OpenCode source code was copied.
// Design origin: ../../docs/design-origin.md

public enum PermissionRisk: Int, Sendable, Hashable, CaseIterable, Comparable {
    case low
    case elevated
    case destructive
    case persistent

    public static func < (lhs: PermissionRisk, rhs: PermissionRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum PermissionChoiceScope: String, Sendable, Hashable, CaseIterable {
    case deny
    case once
    case session
    case persistent
}

public struct PermissionChoice: Sendable, Hashable {
    public var scope: PermissionChoiceScope
    public var label: String
    public var risk: PermissionRisk

    public init(scope: PermissionChoiceScope, label: String, risk: PermissionRisk) {
        self.scope = scope
        self.label = label
        self.risk = risk
    }

    public var requiresStrongEmphasis: Bool {
        risk >= .destructive || scope == .persistent
    }
}

/// Focus-trapping permission state that requires an explicit choice.
public struct PermissionPrompt: Sendable, Hashable {
    public var requestedAction: String
    public var resources: [String]
    public var risk: PermissionRisk
    public var choices: [PermissionChoice]
    public private(set) var focusedChoiceIndex: Int

    public init(
        requestedAction: String,
        resources: [String] = [],
        risk: PermissionRisk,
        choices: [PermissionChoice],
        focusedChoiceIndex: Int = 0
    ) {
        precondition(choices.isEmpty == false, "A permission prompt requires at least one choice.")
        precondition(choices.indices.contains(focusedChoiceIndex))
        self.requestedAction = requestedAction
        self.resources = resources
        self.risk = risk
        self.choices = choices
        self.focusedChoiceIndex = focusedChoiceIndex
    }

    public var trapsFocus: Bool { true }
    public var requiresExplicitAction: Bool { true }
    public var focusedChoice: PermissionChoice { choices[focusedChoiceIndex] }

    public mutating func moveFocus(by offset: Int) {
        focusedChoiceIndex = min(max(0, focusedChoiceIndex + offset), choices.count - 1)
    }
}

public struct PermissionPromptActions: Sendable {
    public var choose: @MainActor @Sendable (PermissionChoice) -> Void

    public init(choose: @escaping @MainActor @Sendable (PermissionChoice) -> Void) {
        self.choose = choose
    }
}

public enum QuestionKind: String, Sendable, Hashable, CaseIterable {
    case singleSelection
    case multipleSelection
    case customText
}

public struct QuestionOption: Sendable, Hashable {
    public var id: String
    public var label: String
    public var detail: String?

    public init(id: String, label: String, detail: String? = nil) {
        precondition(id.isEmpty == false)
        self.id = id
        self.label = label
        self.detail = detail
    }
}

public enum QuestionValidationRule: Sendable, Hashable {
    case required
    case minimumSelections(Int)
    case maximumSelections(Int)
    case minimumTextLength(Int)
    case maximumTextLength(Int)
}

public struct Question: Sendable, Hashable {
    public var id: String
    public var title: String
    public var detail: String?
    public var kind: QuestionKind
    public var options: [QuestionOption]
    public var validationRules: [QuestionValidationRule]

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        kind: QuestionKind,
        options: [QuestionOption] = [],
        validationRules: [QuestionValidationRule] = []
    ) {
        precondition(id.isEmpty == false)
        precondition(kind == .customText || options.isEmpty == false, "Selection questions require options.")
        precondition(Set(options.map(\.id)).count == options.count, "Question option identifiers must be unique.")
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.options = options
        self.validationRules = validationRules
    }
}

public enum QuestionAnswer: Sendable, Hashable {
    case optionIDs(Set<String>)
    case text(String)
}

public enum QuestionValidationError: Sendable, Hashable {
    case required
    case tooFewSelections(minimum: Int)
    case tooManySelections(maximum: Int)
    case textTooShort(minimum: Int)
    case textTooLong(maximum: Int)
    case incompatibleAnswer
}

/// Questions and answer values owned by the presentation model.
public struct QuestionPrompt: Sendable, Hashable {
    public var questions: [Question]
    public private(set) var answers: [String: QuestionAnswer]

    public init(questions: [Question], answers: [String: QuestionAnswer] = [:]) {
        precondition(questions.isEmpty == false, "A question prompt requires at least one question.")
        precondition(Set(questions.map(\.id)).count == questions.count, "Question identifiers must be unique.")
        self.questions = questions
        self.answers = answers
    }

    public mutating func setAnswer(_ answer: QuestionAnswer, forQuestionID questionID: String) {
        precondition(questions.contains { $0.id == questionID }, "The question identifier must exist.")
        answers[questionID] = answer
    }

    public func validationErrors(forQuestionAt index: Int) -> [QuestionValidationError] {
        precondition(questions.indices.contains(index))
        let question = questions[index]
        let answer = answers[question.id]
        guard isCompatible(answer, with: question) else { return [.incompatibleAnswer] }

        return question.validationRules.compactMap { rule in
            validationError(for: rule, answer: answer)
        }
    }

    public func isQuestionValid(at index: Int) -> Bool {
        validationErrors(forQuestionAt: index).isEmpty
    }

    private func isCompatible(_ answer: QuestionAnswer?, with question: Question) -> Bool {
        guard let answer else { return true }
        return switch (question.kind, answer) {
        case (.singleSelection, .optionIDs(let ids)):
            ids.count <= 1 && ids.isSubset(of: Set(question.options.map(\.id)))
        case (.multipleSelection, .optionIDs(let ids)):
            ids.isSubset(of: Set(question.options.map(\.id)))
        case (.customText, .text): true
        default: false
        }
    }

    private func validationError(for rule: QuestionValidationRule, answer: QuestionAnswer?) -> QuestionValidationError? {
        switch rule {
        case .required:
            return switch answer {
            case .optionIDs(let ids): ids.isEmpty ? .required : nil
            case .text(let text): text.allSatisfy(\.isWhitespace) ? .required : nil
            case nil: .required
            }
        case .minimumSelections(let minimum):
            guard case .optionIDs(let ids) = answer else { return .tooFewSelections(minimum: minimum) }
            return ids.count < minimum ? .tooFewSelections(minimum: minimum) : nil
        case .maximumSelections(let maximum):
            guard case .optionIDs(let ids) = answer else { return nil }
            return ids.count > maximum ? .tooManySelections(maximum: maximum) : nil
        case .minimumTextLength(let minimum):
            guard case .text(let text) = answer else { return .textTooShort(minimum: minimum) }
            return text.count < minimum ? .textTooShort(minimum: minimum) : nil
        case .maximumTextLength(let maximum):
            guard case .text(let text) = answer else { return nil }
            return text.count > maximum ? .textTooLong(maximum: maximum) : nil
        }
    }
}

/// Temporary step and focus state owned by the question view.
public struct QuestionPromptState: Sendable, Hashable {
    public private(set) var stepIndex: Int
    public var focusedOptionIndex: Int?

    public init(stepIndex: Int = 0, focusedOptionIndex: Int? = nil) {
        precondition(stepIndex >= 0)
        self.stepIndex = stepIndex
        self.focusedOptionIndex = focusedOptionIndex
    }

    public mutating func moveToPreviousStep() {
        stepIndex = max(0, stepIndex - 1)
        focusedOptionIndex = nil
    }

    @discardableResult
    public mutating func moveToNextStep(in prompt: QuestionPrompt) -> Bool {
        guard prompt.questions.indices.contains(stepIndex), prompt.isQuestionValid(at: stepIndex) else { return false }
        guard stepIndex + 1 < prompt.questions.count else { return false }
        stepIndex += 1
        focusedOptionIndex = nil
        return true
    }
}

public struct QuestionPromptActions: Sendable {
    public var submit: @MainActor @Sendable ([String: QuestionAnswer]) -> Void
    public var cancel: @MainActor @Sendable () -> Void

    public init(
        submit: @escaping @MainActor @Sendable ([String: QuestionAnswer]) -> Void,
        cancel: @escaping @MainActor @Sendable () -> Void
    ) {
        self.submit = submit
        self.cancel = cancel
    }
}
