// Design origin: ../../docs/design-origin.md

/// The risk level of a requested action.
public enum PermissionRisk: Int, Sendable, Hashable, CaseIterable, Comparable {
    /// An action with low risk.
    case low
    /// An action with elevated risk.
    case elevated
    /// An action that can destroy data or state.
    case destructive
    /// An action that persists beyond the current session.
    case persistent

    /// Returns whether the left risk is lower than the right risk.
    /// - Complexity: O(1).
    public static func < (lhs: PermissionRisk, rhs: PermissionRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The duration and effect of a permission choice.
public enum PermissionChoiceScope: String, Sendable, Hashable, CaseIterable {
    /// Denies the requested action.
    case deny
    /// Allows the action once.
    case once
    /// Allows the action for the current session.
    case session
    /// Allows the action persistently.
    case persistent
}

/// A selectable response to a permission request.
public struct PermissionChoice: Sendable, Hashable {
    /// The choice scope.
    public var scope: PermissionChoiceScope
    /// The displayed choice label.
    public var label: String
    /// The risk associated with the choice.
    public var risk: PermissionRisk

    /// Creates a permission choice.
    public init(scope: PermissionChoiceScope, label: String, risk: PermissionRisk) {
        self.scope = scope
        self.label = label
        self.risk = risk
    }

    /// A Boolean value that indicates whether the choice needs strong emphasis.
    /// - Complexity: O(1).
    public var requiresStrongEmphasis: Bool {
        risk >= .destructive || scope == .persistent
    }
}

/// Focus-trapping permission state that requires an explicit choice.
public struct PermissionPrompt: Sendable, Hashable {
    /// The action that requires permission.
    public var requestedAction: String
    /// The resources affected by the action.
    public var resources: [String]
    /// The risk of the requested action.
    public var risk: PermissionRisk
    /// The available permission choices.
    public var choices: [PermissionChoice]
    /// The index of the focused choice.
    public private(set) var focusedChoiceIndex: Int

    /// Creates a permission prompt.
    public init(
        requestedAction: String,
        risk: PermissionRisk,
        choices: [PermissionChoice],
        resources: [String] = [],
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

    /// A Boolean value that indicates whether the prompt traps focus.
    public var trapsFocus: Bool { true }
    /// A Boolean value that indicates whether the prompt requires an explicit action.
    public var requiresExplicitAction: Bool { true }
    /// The currently focused permission choice.
    /// - Complexity: O(1).
    public var focusedChoice: PermissionChoice { choices[focusedChoiceIndex] }

    /// Moves focus by the specified offset and clamps it to the choices.
    /// - Complexity: O(1).
    public mutating func moveFocus(by offset: Int) {
        focusedChoiceIndex = min(max(0, focusedChoiceIndex + offset), choices.count - 1)
    }
}

/// Actions emitted by a permission prompt.
public struct PermissionPromptActions: Sendable {
    /// Selects a permission choice.
    public var choose: @MainActor @Sendable (_ choice: PermissionChoice) -> Void

    /// Creates permission prompt actions.
    public init(choose: @escaping @MainActor @Sendable (_ choice: PermissionChoice) -> Void) {
        self.choose = choose
    }
}

/// The input format of a question.
public enum QuestionKind: String, Sendable, Hashable, CaseIterable {
    /// Selects one option.
    case singleSelection
    /// Selects one or more options.
    case multipleSelection
    /// Accepts free-form text.
    case customText
}

/// A selectable option for a question.
public struct QuestionOption: Sendable, Hashable {
    /// The stable option identifier.
    public var id: String
    /// The option label.
    public var label: String
    /// Additional option details, if available.
    public var detail: String?

    /// Creates a question option.
    public init(id: String, label: String, detail: String? = nil) {
        precondition(id.isEmpty == false)
        self.id = id
        self.label = label
        self.detail = detail
    }
}

/// A validation constraint for a question answer.
public enum QuestionValidationRule: Sendable, Hashable {
    /// Requires a nonempty answer.
    case required
    /// Requires at least the specified number of selections.
    case minimumSelections(Int)
    /// Allows at most the specified number of selections.
    case maximumSelections(Int)
    /// Requires at least the specified number of characters.
    case minimumTextLength(Int)
    /// Allows at most the specified number of characters.
    case maximumTextLength(Int)
}

/// A question, its options, and its validation rules.
public struct Question: Sendable, Hashable {
    /// The stable question identifier.
    public var id: String
    /// The question title.
    public var title: String
    /// Additional question details, if available.
    public var detail: String?
    /// The expected answer format.
    public var kind: QuestionKind
    /// The selectable options.
    public var options: [QuestionOption]
    /// The answer validation rules.
    public var validationRules: [QuestionValidationRule]

    /// Creates a question.
    public init(
        id: String,
        title: String,
        kind: QuestionKind,
        detail: String? = nil,
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

/// An answer to a question.
public enum QuestionAnswer: Sendable, Hashable {
    /// A set of selected option identifiers.
    case optionIDs(Set<String>)
    /// A free-form text answer.
    case text(String)
}

/// An error produced by question validation.
public enum QuestionValidationError: Sendable, Hashable {
    /// A required answer is missing.
    case required
    /// The answer contains too few selections.
    case tooFewSelections(minimum: Int)
    /// The answer contains too many selections.
    case tooManySelections(maximum: Int)
    /// The text answer is too short.
    case textTooShort(minimum: Int)
    /// The text answer is too long.
    case textTooLong(maximum: Int)
    /// The answer format does not match the question kind.
    case incompatibleAnswer
}

/// Questions and answer values owned by the presentation model.
public struct QuestionPrompt: Sendable, Hashable {
    /// The questions in display order.
    public var questions: [Question]
    /// The answers keyed by question identifier.
    public private(set) var answers: [String: QuestionAnswer]

    /// Creates a question prompt.
    public init(questions: [Question], answers: [String: QuestionAnswer] = [:]) {
        precondition(questions.isEmpty == false, "A question prompt requires at least one question.")
        precondition(Set(questions.map(\.id)).count == questions.count, "Question identifiers must be unique.")
        self.questions = questions
        self.answers = answers
    }

    /// Sets the answer for a question identifier.
    /// - Complexity: O(n), where n is the number of questions.
    public mutating func setAnswer(_ answer: QuestionAnswer, forQuestionID questionID: String) {
        precondition(questions.contains { $0.id == questionID }, "The question identifier must exist.")
        answers[questionID] = answer
    }

    /// Returns the validation errors for the question at an index.
    /// - Complexity: O(r + o), where r is the rule count and o is the option count.
    public func validationErrors(forQuestionAt index: Int) -> [QuestionValidationError] {
        precondition(questions.indices.contains(index))
        let question = questions[index]
        let answer = answers[question.id]
        guard isCompatible(answer, with: question) else { return [.incompatibleAnswer] }

        return question.validationRules.compactMap { rule in
            validationError(for: rule, answer: answer)
        }
    }

    /// Returns whether the question at an index has a valid answer.
    /// - Complexity: O(r + o), where r is the rule count and o is the option count.
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
    /// The index of the current question step.
    public private(set) var stepIndex: Int
    /// The focused option index, if an option has focus.
    public var focusedOptionIndex: Int?

    /// Creates question prompt state.
    public init(stepIndex: Int = 0, focusedOptionIndex: Int? = nil) {
        precondition(stepIndex >= 0)
        self.stepIndex = stepIndex
        self.focusedOptionIndex = focusedOptionIndex
    }

    /// Moves to the previous question step.
    /// - Complexity: O(1).
    public mutating func moveToPreviousStep() {
        stepIndex = max(0, stepIndex - 1)
        focusedOptionIndex = nil
    }

    /// Moves to the next step when the current answer is valid.
    /// - Complexity: O(r + o), where r is the rule count and o is the option count.
    @discardableResult
    public mutating func moveToNextStep(in prompt: QuestionPrompt) -> Bool {
        guard prompt.questions.indices.contains(stepIndex), prompt.isQuestionValid(at: stepIndex) else { return false }
        guard stepIndex + 1 < prompt.questions.count else { return false }
        stepIndex += 1
        focusedOptionIndex = nil
        return true
    }
}

/// Actions emitted by a question prompt.
public struct QuestionPromptActions: Sendable {
    /// Submits answers keyed by question identifier.
    public var submit: @MainActor @Sendable (_ answers: [String: QuestionAnswer]) -> Void
    /// Cancels the prompt.
    public var cancel: @MainActor @Sendable () -> Void

    /// Creates question prompt actions.
    public init(
        submit: @escaping @MainActor @Sendable (_ answers: [String: QuestionAnswer]) -> Void,
        cancel: @escaping @MainActor @Sendable () -> Void
    ) {
        self.submit = submit
        self.cancel = cancel
    }
}
